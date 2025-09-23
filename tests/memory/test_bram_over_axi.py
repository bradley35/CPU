import logging
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.result import TestFailure

from cocotbext.axi import AxiLiteBus, AxiLiteMaster

ALIGN = 8  # 64-bit AXI-Lite


# IMPORTANT: These tests require cocotb 1.9.2. They do not work with 2.0 or >
# This is contrary to the other tests the REQUIRE >2.0

# ----------------- helpers -----------------

def _as_bytes(x):
    return x if isinstance(x, (bytes, bytearray)) else x.encode("utf-8")

def _assert_eq_bytes(actual: bytes, expected: bytes, where: str = ""):
    if actual != expected:
        msg = (
            f"{where} mismatch:\n"
            f"  expected ({len(expected)}B): {expected!r}\n"
            f"  actual   ({len(actual)}B): {actual!r}\n"
            f"  expected hex: {expected.hex()}\n"
            f"  actual   hex: {actual.hex()}"
        )
        raise TestFailure(msg)

def _ceil_div(x, y):  # integer ceil
    return (x + y - 1) // y

async def write_aligned(axi: AxiLiteMaster, addr: int, payload: bytes, align: int = ALIGN):
    """Write using only full aligned beats; pad last beat with zeros."""
    if addr % align != 0:
        raise TestFailure(f"write_aligned: address 0x{addr:X} not {align}-byte aligned")
    beats = _ceil_div(len(payload), align)
    for i in range(beats):
        beat_addr = addr + i * align
        start = i * align
        end = min(start + align, len(payload))
        beat = bytearray(align)
        beat[: end - start] = payload[start:end]
        await axi.write(beat_addr, bytes(beat))

async def read_aligned(axi: AxiLiteMaster, addr: int, nbytes: int, align: int = ALIGN) -> bytes:
    """Read using only full aligned beats; trim to requested length."""
    if addr % align != 0:
        raise TestFailure(f"read_aligned: address 0x{addr:X} not {align}-byte aligned")
    beats = _ceil_div(nbytes, align)
    data = bytearray()
    for i in range(beats):
        beat_addr = addr + i * align
        rsp = await axi.read(beat_addr, align)
        data += rsp.data  # exactly 'align' bytes
    return bytes(data[:nbytes])

async def _reset(dut, cycles: int = 2):
    dut.rst.value = 1
    await Timer(50, units="ns")
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)

# ----------------- tests -----------------

@cocotb.test()
async def test_cache_same_line_rw(dut):
    """
    Two aligned writes within the same 128B line; read back in aligned beats.
    """
    log = logging.getLogger("cocotb.tb")
    log.setLevel(logging.DEBUG)
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _reset(dut)

    axi = AxiLiteMaster(AxiLiteBus.from_entity(dut.cache_bus), dut.clk, dut.rst)

    # Same line: [0x000..0x07F]; pick aligned base
    base = 0x020  # 32, 8-byte aligned and clearly inside the line
    part1 = _as_bytes("Hello ")   # 6B
    part2 = _as_bytes("World!!!") # 8B (already a full beat)

    # Compose expected and pad/align writes
    expected = part1 + part2
    await write_aligned(axi, base, expected)  # will issue two aligned writes (total 16B)

    # Read back exactly len(expected), but using aligned beats
    got = await read_aligned(axi, base, len(expected))
    _assert_eq_bytes(got, expected, where="same-line aligned R/W")

    log.info("Same-line aligned R/W passed: %r", got)


@cocotb.test()
async def test_cache_cross_line_write(dut):
    """
    Write across the 0x7F->0x80 boundary using aligned beats only.
    Start at 0x78 (aligned), write 16 bytes (two beats) so we span two lines.
    """
    log = logging.getLogger("cocotb.tb")
    log.setLevel(logging.DEBUG)
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _reset(dut)

    axi = AxiLiteMaster(AxiLiteBus.from_entity(dut.cache_bus), dut.clk, dut.rst)

    start = 0x078  # 120, aligned to 8; last beat of line 0 and first beat of line 1
    payload = _as_bytes("ABCDEFGHIJKLMNO")  # 15B
    await write_aligned(axi, start, payload)  # two 8B writes at 0x78 and 0x80

    got = await read_aligned(axi, start, len(payload))
    _assert_eq_bytes(got, payload, where="cross-line aligned write/read")

    log.info("Cross-line aligned write/read passed (len=%d)", len(payload))


@cocotb.test()
async def test_cache_eviction_writeback(dut):
    """
    Force an eviction at index=3 by accessing two lines that share index/offset but differ in the (effective) tag.
    Verify the dirty line is written back by reading it after eviction.
    """
    log = logging.getLogger("cocotb.tb")
    log.setLevel(logging.DEBUG)
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _reset(dut)

    axi = AxiLiteMaster(AxiLiteBus.from_entity(dut.cache_bus), dut.clk, dut.rst)

    # OFFSET_BITS=7 (128B), INDEX_BITS=4 (16 lines). With 4KB backing, only low 12 bits matter.
    # Choose index=3 (bits [10:7] = 3) and offset=0; toggle bit 11 to change the "real" tag.
    addr_a = 0x000 | (3 << 7) | 0x000  # 0x180, tag=0
    addr_b = 0x800 | (3 << 7) | 0x000  # 0x980, tag=1 (bit 11 set)
    assert addr_a % ALIGN == 0 and addr_b % ALIGN == 0

    data_a = _as_bytes("FirstLineData!!")  # 16B -> two aligned beats
    data_b = _as_bytes("SecondLineDATA")   # 15B -> two aligned beats (last padded on write)

    # 1) Write to line A (dirty in cache)
    await write_aligned(axi, addr_a, data_a)

    # 2) Access line B (same index, different tag) to evict A; write so B becomes resident (possibly dirty)
    await write_aligned(axi, addr_b, data_b)

    # 3) Read A back; if write-back worked, backing store now contains data_a
    got_a = await read_aligned(axi, addr_a, len(data_a))
    _assert_eq_bytes(got_a, data_a, where="eviction write-back (A after B)")

    # 4) Sanity: read B too
    got_b = await read_aligned(axi, addr_b, len(data_b))
    _assert_eq_bytes(got_b, data_b, where="post-eviction read B")

    log.info("Eviction write-back verified for A and B")

@cocotb.test()
async def test_cache_fill_evict_read_full_line(dut):
    """
    Fill an entire 128B line, evict it by accessing the same index with a different tag,
    then read the whole line back and verify contents (write-back).
    """
    log = logging.getLogger("cocotb.tb")
    log.setLevel(logging.DEBUG)

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _reset(dut)

    axi = AxiLiteMaster(AxiLiteBus.from_entity(dut.cache_bus), dut.clk, dut.rst)

    # Parameters from your design:
    # OFFSET_BITS = 7 (128B/line), INDEX_BITS = 4 (16 indices), 4KB backing => bit 11 is the real tag.
    # Pick index = 5 (bits [10:7]=5) and offset = 0; toggle bit 11 to change tag.
    base_a = (5 << 7) | 0x000      # 0x280, tag=0
    base_b = 0x800 | (5 << 7)      # 0xA80, tag=1 (bit 11 set)
    assert base_a % 8 == 0 and base_b % 8 == 0

    LINE_BYTES = 128

    # Build deterministic 128B payloads (ASCII so it's easy to eyeball in logs)
    payload_a = ''.join(chr(65 + (i % 26)) for i in range(LINE_BYTES)).encode('ascii')  # ABC... repeated to 128B
    payload_b = ''.join(chr(97 + (i % 26)) for i in range(LINE_BYTES)).encode('ascii')  # abc... repeated to 128B

    # 1) Fill entire line A in one giant write; AxiLiteMaster will split into aligned beats
    await axi.write(base_a, payload_a)

    # Optional sanity: immediate read-back should be a cache hit with exact data
    rsp_a_hit = await axi.read(base_a, LINE_BYTES)
    _assert_eq_bytes(bytes(rsp_a_hit.data), payload_a, where="full-line immediate read (cache hit)")

    # 2) Touch line B (same index, different tag) to force eviction of A
    await axi.write(base_b, payload_b)

    # 3) Read A again: should miss, fetch from backing, and match payload_a if write-back worked
    rsp_a_after_evict = await axi.read(base_a, LINE_BYTES)
    _assert_eq_bytes(bytes(rsp_a_after_evict.data), payload_a, where="full-line read after eviction (write-back)")

    # 4) And B should still be what we wrote
    rsp_b = await axi.read(base_b, LINE_BYTES)
    _assert_eq_bytes(bytes(rsp_b.data), payload_b, where="post-eviction read of B")

    log.info("Full-line fill/evict/read passed for index 5 (0x%03X/0x%03X)", base_a, base_b)

import random

@cocotb.test()
async def test_write_and_read_entire_4kb_random(dut):
    """
    Stress test with randomness: write 4KB of random bytes (0x000–0xFFF) in one axi.write,
    then read 4KB back in one axi.read and compare. Ensures no accidental "pattern pass".
    """
    log = logging.getLogger("cocotb.tb")
    log.setLevel(logging.DEBUG)

    # Clock + reset
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _reset(dut)

    axi = AxiLiteMaster(AxiLiteBus.from_entity(dut.cache_bus), dut.clk, dut.rst)

    BASE   = 0x000
    LENGTH = 4096  # full 4KB backing store

    # Seed for reproducibility (same test run always same pattern)
    random.seed(12345)
    payload = bytes(random.getrandbits(8) for _ in range(LENGTH))

    # 1) One single axi.write of full 4KB
    await axi.write(BASE, payload)

    # 2) One single axi.read of full 4KB
    rsp = await axi.read(BASE, LENGTH)
    got = bytes(rsp.data)

    # 3) Compare with clear error reporting
    if got != payload:
        # first mismatch
        idx = next((i for i, (a, b) in enumerate(zip(got, payload)) if a != b), None)
        start = max(0, idx - 16)
        end   = min(LENGTH, idx + 16)
        exp_slice = payload[start:end]
        got_slice = got[start:end]
        raise TestFailure(
            f"Random 4KB mismatch at offset 0x{idx:03X}: "
            f"expected 0x{payload[idx]:02X}, got 0x{got[idx]:02X}\n"
            f"window [{start:03X}:{end:03X}] expected: {exp_slice.hex()}\n"
            f"window [{start:03X}:{end:03X}] actual  : {got_slice.hex()}"
        )

    log.info("Random full 4KB single-call write/read passed")
