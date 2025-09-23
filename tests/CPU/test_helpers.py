import cocotb
from cocotb.clock import Clock, Timer
from cocotb.triggers import RisingEdge, ReadOnly, ReadWrite, First
import sys, os
sys.path.append(os.path.dirname(__file__))
from tests.CPU.riscv_tests_gen import *

async def resetAndPrepare(dut):
    dut.rst.value = 1
    await ReadWrite()
    dut.rst.value = 0
    await ReadWrite()


def _mem_params(dut):
    NUMBER_OF_BLOCKS    = dut.main_memory.NUMBER_OF_BLOCKS.value.to_unsigned()
    ENTRIES_PER_BLOCK   = dut.main_memory.ENTRIES_PER_BLOCK.value.to_unsigned()
    BLOCK_SIZE_BITS     = dut.main_memory.BLOCK_SIZE.value.to_unsigned()           # width of one mem word
    WORD_BYTES          = BLOCK_SIZE_BITS // 8
    assert BLOCK_SIZE_BITS % 8 == 0, "BLOCK_SIZE must be byte-aligned"
    WORD_BYTES = BLOCK_SIZE_BITS // 8
    return NUMBER_OF_BLOCKS, ENTRIES_PER_BLOCK, WORD_BYTES

def _get_word_handle(dut, word_index):
    """
    Map linear word index -> (block, entry):
      block = w % NUMBER_OF_BLOCKS
      entry = w // NUMBER_OF_BLOCKS
    Adjust the path if your hierarchy differs.
    """
    NUMBER_OF_BLOCKS, _, _ = _mem_params(dut)
    block = word_index % NUMBER_OF_BLOCKS
    entry = word_index // NUMBER_OF_BLOCKS
    return dut.main_memory.generate_blocks[block].mem_blk[entry]

async def awrite_bytes_to_mem(dut, base_addr: int, data: bytes):
    """
    Async byte-accurate write:
    - Batches updates per *word* (fast).
    - After each word assignment, awaits one delta (ReadWrite) so
      downstream reads in the same timestep see the new value.
    """
    if not data:
        return

    NUMBER_OF_BLOCKS, ENTRIES_PER_BLOCK, WORD_BYTES = _mem_params(dut)
    max_words = ENTRIES_PER_BLOCK * NUMBER_OF_BLOCKS

    last_byte = base_addr + len(data) - 1
    last_word = last_byte // WORD_BYTES
    if last_word >= max_words:
        raise ValueError(f"Write past memory end (last_word={last_word}, max_words={max_words})")

    first_word = base_addr // WORD_BYTES
    # Iterate word-by-word over the touched range
    for w in range(first_word, last_word + 1):
        # Compute slice of `data` landing in this word
        word_base_addr = w * WORD_BYTES
        # data indices overlapping this word:
        lo = max(0, word_base_addr - base_addr)
        hi = min(len(data), (word_base_addr + WORD_BYTES) - base_addr)
        if lo >= hi:
            continue

        boff = (base_addr + lo) - word_base_addr  # byte offset in word
        chunk = hi - lo

        h = _get_word_handle(dut, w)

        # Read current word, patch bytes (LE), write back
        cur = int(h.value)
        word_bytes = bytearray(cur.to_bytes(WORD_BYTES, "little"))
        word_bytes[boff:boff+chunk] = data[lo:hi]
        h.value = int.from_bytes(word_bytes, "little")

        # Let the assignment settle this delta
        await ReadWrite()

async def awrite_u64(dut, addr: int, value: int):
    await awrite_bytes_to_mem(dut, addr, value.to_bytes(8, "little"))

async def awrite_u32(dut, addr: int, value: int):
    await awrite_bytes_to_mem(dut, addr, value.to_bytes(4, "little"))

async def awrite_u16(dut, addr: int, value: int):
    await awrite_bytes_to_mem(dut, addr, value.to_bytes(2, "little"))

async def awrite_u8(dut, addr: int, value: int):
    # Per-byte path still batches per word and awaits once
    await awrite_bytes_to_mem(dut, addr, bytes([value & 0xFF]))

async def awrite_pattern(dut, base_addr: int, byte_list):
    """Convenience: write a Python list of byte values."""
    await awrite_bytes_to_mem(dut, base_addr, bytes([b & 0xFF for b in byte_list]))

# Optional async read helpers (nice for quick asserts)
async def aread_word_le(dut, addr_aligned: int):
    """
    Read a full word at an aligned address (LE), after a ReadOnly to
    sample a stable value in the current timestep.
    """
    _, _, WORD_BYTES = _mem_params(dut)
    assert addr_aligned % WORD_BYTES == 0, "Unaligned word read"
    widx = addr_aligned // WORD_BYTES
    h = _get_word_handle(dut, widx)
    await ReadOnly()
    return int(h.value)


def loadAsmToMemory(asm_string, dut, *, clear_mem=True):
    compiled = assemble_rv32i_bytes(asm_string)  # list/bytes of assembled code
    mnemonics = disassemble_rv32i(asm_string)
    log_bit_grid(dut, compiled, mnemonics)
    return loadCompiledToMemory(compiled, dut, clear_mem=clear_mem)



def loadCompiledToMemory(compiled, dut, *, clear_mem=True):

    # Read SV params from the DUT
    NUMBER_OF_BLOCKS    = dut.main_memory.NUMBER_OF_BLOCKS.value.to_unsigned()
    ENTRIES_PER_BLOCK   = dut.main_memory.ENTRIES_PER_BLOCK.value.to_unsigned()
    BLOCK_SIZE_BITS     = dut.main_memory.BLOCK_SIZE.value.to_unsigned()           # width of one mem word
    WORD_BYTES          = BLOCK_SIZE_BITS // 8

    if BLOCK_SIZE_BITS % 8 != 0:
        raise ValueError(f"BLOCK_SIZE ({BLOCK_SIZE_BITS}) must be byte-aligned")

    # How many words do we need to hold the compiled bytes?
    total_words = (len(compiled) + WORD_BYTES - 1) // WORD_BYTES
    needed_entries = (total_words + NUMBER_OF_BLOCKS - 1) // NUMBER_OF_BLOCKS
    if needed_entries > ENTRIES_PER_BLOCK:
        raise ValueError(
            f"Program needs {needed_entries} entries per block, "
            f"but ENTRIES_PER_BLOCK={ENTRIES_PER_BLOCK}"
        )

    # Optional: clear memory
    if clear_mem:
        for bi in range(NUMBER_OF_BLOCKS):
            for ei in range(ENTRIES_PER_BLOCK):
                dut.main_memory.generate_blocks[bi].mem_blk[ei].value = 0

    # Pack bytes -> words (little-endian within each word) and store
    for w in range(total_words):
        start = w * WORD_BYTES
        end   = min(start + WORD_BYTES, len(compiled))
        word_val = 0
        for b, byte in enumerate(compiled[start:end]):
            word_val |= int(byte) << (8 * b)  # little-endian byte order

        block_idx = w % NUMBER_OF_BLOCKS
        entry_idx = w // NUMBER_OF_BLOCKS

        # Path: generate_blocks[block].mem_blk[entry]
        dut.main_memory.generate_blocks[block_idx].mem_blk[entry_idx].value = word_val


def loadRegisters(register_list, dut):
    for i in range(len(register_list)):
        if i == 0:
            continue
        dut.register_table.register_storage[i].value = register_list[i]
def checkFinished(dut):
    assert dut.program_complete.value == 1, "Program did not complete"
def checkRegister(number, ref, dut, signed=False):
    if signed:
        val = dut.register_table.register_storage[number].value.to_signed()
    else:
        val = dut.register_table.register_storage[number].value.to_unsigned()
    assert val == ref, f"Expected {ref:d} for register {number:d}, got {val:d}"
