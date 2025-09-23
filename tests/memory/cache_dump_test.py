import logging
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, with_timeout
from cocotb.result import TestFailure
from cocotbext.axi import AxiLiteBus, AxiLiteMaster


# ----------------- utilities to peek/poke backing memory -----------------

def _int(x):  # shorthand
    return int(x)

def _get_params_from_dut(dut):
    """
    Pulls sizes from your DUT hierarchy so we can map byte addresses -> (block, entry, byte)
    Assumes:
      DATA_W = NUMBER_OF_BLOCKS * BLOCK_SIZE
      mem organization = mem_blk[entry] for each block
    """
    # Adjust these paths if your hierarchy differs:
    root = dut.cache_memory_backing

    DATA_W      = 64
    BLOCK_SIZE  = _int(root.BLOCK_SIZE.value)                  # bits per block
    NUM_BLOCKS  = _int(root.NUMBER_OF_BLOCKS.value)
    BYTES_PER_BEAT = DATA_W // 8
    BLOCK_BYTES     = BLOCK_SIZE // 8

    # Sanity: DATA_W must match NUM_BLOCKS * BLOCK_SIZE
    if DATA_W != NUM_BLOCKS * BLOCK_SIZE:
        raise TestFailure(f"DATA_W ({DATA_W}) != NUM_BLOCKS*BLOCK_SIZE ({NUM_BLOCKS*BLOCK_SIZE})")

    return root, DATA_W, BLOCK_SIZE, NUM_BLOCKS, BYTES_PER_BEAT, BLOCK_BYTES

def _addr_to_indices(addr, BYTES_PER_BEAT, BLOCK_BYTES):
    entry   = addr // BYTES_PER_BEAT
    within  = addr %  BYTES_PER_BEAT
    blk     = within // BLOCK_BYTES
    j       = within %  BLOCK_BYTES  # byte index inside that block
    return entry, blk, j

def _get_block_handle(root, blk):
    # Access the generate block handle: root.generate_blocks[blk]
    try:
        return root.generate_blocks[blk]
    except Exception as e:
        raise TestFailure(
            f"Could not access backing memory block {blk} at root.generate_blocks[{blk}]. "
            f"Adjust the hierarchy path if your instance name differs. ({e})"
        )

def _peek_mem_bytes(dut, base_addr: int, length: int) -> bytes:
    """
    Reads raw bytes directly from the backing memory arrays via integer mask/shift.
    """
    root, DATA_W, BLOCK_SIZE, NUM_BLOCKS, BYTES_PER_BEAT, BLOCK_BYTES = _get_params_from_dut(dut)
    out = bytearray(length)
    for off in range(length):
        addr = base_addr + off
        entry, blk, j = _addr_to_indices(addr, BYTES_PER_BEAT, BLOCK_BYTES)

        blk_handle = _get_block_handle(root, blk)
        if entry >= len(blk_handle.mem_blk):
            raise TestFailure(f"peek out of range: entry {entry} >= len(mem_blk)")

        val = int(blk_handle.mem_blk[entry].value)   # packed BLOCK_SIZE-bit word as int
        out[off] = (val >> (j * 8)) & 0xFF          # byte j is the lowest 8 bits shifted by j*8
    return bytes(out)


def _poke_mem_byte(dut, addr: int, value: int):
    """
    Writes a single byte in the packed entry via integer mask/shift.
    """
    root, DATA_W, BLOCK_SIZE, NUM_BLOCKS, BYTES_PER_BEAT, BLOCK_BYTES = _get_params_from_dut(dut)
    entry, blk, j = _addr_to_indices(addr, BYTES_PER_BEAT, BLOCK_BYTES)

    blk_handle = _get_block_handle(root, blk)
    if entry >= len(blk_handle.mem_blk):
        raise TestFailure(f"poke out of range: entry {entry} >= len(mem_blk)")

    cur = int(blk_handle.mem_blk[entry].value)
    mask = 0xFF << (j * 8)
    new  = (cur & ~mask) | ((int(value) & 0xFF) << (j * 8))

    blk_handle.mem_blk[entry].value = new   # cocotb allows assigning int to packed vectors


def _assert_eq_bytes(actual: bytes, expected: bytes, where: str):
    if actual != expected:
        # find first mismatch and show a small hex window
        idx = next((i for i,(a,b) in enumerate(zip(actual, expected)) if a != b), None)
        if idx is None:
            idx = min(len(actual), len(expected))
        s = max(0, idx-16); e = min(max(len(actual), len(expected)), idx+16)
        raise TestFailure(
            f"{where} mismatch at +0x{idx:X}: exp=0x{expected[idx]:02X} got=0x{actual[idx]:02X}\n"
            f"expected[{s:04X}:{e:04X}]={expected[s:e].hex()}\n"
            f"actual  [{s:04X}:{e:04X}]={actual[s:e].hex()}"
        )

async def _reset(dut, cycles=2):
    dut.rst.value = 1
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(50, units="ns")
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)


# ----------------- the test -----------------

@cocotb.test()
async def test_dump_cache_flush_and_invalidate(dut):
    """
    1) Write two distinct, non-consecutive cache lines via AXI (they share neither index nor adjacency).
    2) Verify backing memory is unchanged (write-back not yet flushed).
    3) Assert dut.cache.dump_cache until the cache completes the dump; wait until it's ready to accept reads again.
    4) Verify backing memory now contains the written data (flush worked).
    5) Verify invalidation: mutate one byte in backing memory directly and confirm an AXI read observes it.
    """
    log = logging.getLogger("cocotb.tb")
    log.setLevel(logging.DEBUG)

    await _reset(dut)
    axi = AxiLiteMaster(AxiLiteBus.from_entity(dut.cache_bus), dut.clk, dut.rst)

    # Helpful locals from DUT for address math
    root, DATA_W, BLOCK_SIZE, NUM_BLOCKS, BYTES_PER_BEAT, BLOCK_BYTES = _get_params_from_dut(dut)

    # Choose two non-consecutive lines (same tag=0, different indices far apart), offset=0
    # OFFSET_BITS=7 => 128B per line; INDEX_BITS=4 => indices in bits [10:7]
    # We'll pick index=1 and index=9
    line_bytes = 128
    addr_a = (1 << 7) | 0x00   # 0x080
    addr_b = (9 << 7) | 0x00   # 0x480
    assert addr_a % 8 == 0 and addr_b % 8 == 0

    # Payloads (shorter than a line; AXI-lite will split under the hood)
    payload_a = b"LINE_A::" + bytes([0xAA]) * 24   # 32B distinct signature
    payload_b = b"LINE_B::" + bytes([0xBB]) * 24   # 32B distinct signature

    # Snapshot backing memory BEFORE writes (ground truth for "not flushed yet")
    before_a = _peek_mem_bytes(dut, addr_a, len(payload_a))
    before_b = _peek_mem_bytes(dut, addr_b, len(payload_b))

    # 1) Fill the two lines via AXI (these go into cache and become dirty)
    await axi.write(addr_a, payload_a)
    await axi.write(addr_b, payload_b)

    # 2) Verify backing memory has NOT changed yet (still equals the "before" snapshot)
    after_write_a = _peek_mem_bytes(dut, addr_a, len(payload_a))
    after_write_b = _peek_mem_bytes(dut, addr_b, len(payload_b))
    if after_write_a == payload_a:
        raise TestFailure("Backing memory for A unexpectedly updated before dump (write-back happened too early?)")
    if after_write_b == payload_b:
        raise TestFailure("Backing memory for B unexpectedly updated before dump (write-back happened too early?)")
    _assert_eq_bytes(after_write_a, before_a, "pre-dump backing A")
    _assert_eq_bytes(after_write_b, before_b, "pre-dump backing B")

    # 3) Trigger dump+invalidate
    # Hold dump_cache high long enough to be sampled; your RTL: "held high on an edge"
    dut.cache.dump_cache.value = 1
    await RisingEdge(dut.clk)
    # keep it asserted for one more cycle just to be safe
    await RisingEdge(dut.clk)
    dut.cache.dump_cache.value = 0

    # Wait until cache signals it's ready to accept a read again.
    # We'll consider this when AR channel is idle-ready (awready+arready both high).
    # (If your adapter holds ready high commonly, the busy interval will drop it low while dumping.)
    async def _wait_ready_again(timeout_ns=500_000):
        async def _wait():
            while True:
                ar = int(dut.cache_bus.arready.value)
                if ar:
                    # require it to be stable for a cycle to avoid glitch
                    await RisingEdge(dut.clk)
                    if int(dut.cache_bus.arready.value):
                        return
                await RisingEdge(dut.clk)
        await with_timeout(_wait(), timeout_ns, 'ns')

    await _wait_ready_again()

    # 4) Now backing memory should contain the written data (flush completed)
    after_dump_a = _peek_mem_bytes(dut, addr_a, len(payload_a))
    after_dump_b = _peek_mem_bytes(dut, addr_b, len(payload_b))
    _assert_eq_bytes(after_dump_a, payload_a, "post-dump backing A")
    _assert_eq_bytes(after_dump_b, payload_b, "post-dump backing B")

    # 5) Invalidation proof:
    # Patch a single byte in backing memory, then AXI read must reflect the change (i.e., no stale cache copy).
    patch_addr = addr_a  # first byte of line A
    _poke_mem_byte(dut, patch_addr, 0x5A)  # mutate backing store directly

    # If cache were NOT invalidated, a subsequent read could still return the old cached data.
    rsp = await axi.read(patch_addr, 1)
    got = bytes(rsp.data)[0:1]
    exp = bytes([0x5A])
    _assert_eq_bytes(got, exp, "invalidate check (AXI read after memory patch)")

    log.info("Dump+invalidate test passed: pre-dump unflushed, post-dump flushed, and cache invalidated.")
