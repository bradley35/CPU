import random
import math
import cocotb
from cocotb.clock import Clock, Timer
from cocotb.triggers import RisingEdge, ReadOnly, ReadWrite, First
import sys, os
sys.path.append(os.path.dirname(__file__))
from tests.CPU.riscv_tests_gen import *
from tests.CPU.test_helpers import *

# -------------------------
# Constants / helpers
# -------------------------
XLEN = 64
MASK = (1 << XLEN) - 1
MEMORY_SIZE = 4096  # 4 KiB memory space

# Keep *all* randomized data traffic in the top 1 KiB so it never aliases code.
DATA_WINDOW_START = MEMORY_SIZE - 1024  # 3072
DATA_WINDOW_END   = MEMORY_SIZE - 1

def wrap_addr(addr: int) -> int:
    """Wrap address into the 4 KiB memory space used by the DUT."""
    return addr % MEMORY_SIZE

def sxt(v, bits):
    """Sign-extend v (int) of width 'bits' to Python int with 64-bit wrap."""
    v &= (1 << bits) - 1
    if v >> (bits - 1):
        v -= (1 << bits)
    return (v & MASK)

def to_s64(v):
    v &= MASK
    return v - (1 << XLEN) if v >> (XLEN - 1) else v

def rand_imm12():
    return random.randint(-2048, 2047)

def rand_shamt64():
    return random.randint(0, 63)

def choose_regs(k=3, avoid_zero=True):
    pool = list(range(1 if avoid_zero else 0, 32))
    random.shuffle(pool
    )
    return pool[:k]

def rand_base_addr(alignment=8):
    """Pick an aligned base inside the data window."""
    start = (DATA_WINDOW_START + alignment - 1) // alignment * alignment
    end   = (DATA_WINDOW_END   - 7) // alignment * alignment
    return random.randrange(start, end + 1, alignment)

def rand_offset_within_window(base, width_bytes, max_words=64):
    """
    Choose an 8-byte-multiple offset so base+offset..+width-1 stays inside [DATA_WINDOW_START..DATA_WINDOW_END].
    Limits magnitude to +/- max_words * 8 to keep addresses "nearby".
    """
    low  = DATA_WINDOW_START
    high = DATA_WINDOW_END - (width_bytes - 1)

    # allowable offset range in bytes (aligned to 8)
    min_off = ((low  - base + 7) // 8) * 8
    max_off = ((high - base)     // 8) * 8

    # clamp to +/- window
    min_off = max(min_off, -max_words * 8)
    max_off = min(max_off,  max_words * 8)

    if min_off > max_off:
        return 0
    k = random.randrange(min_off // 8, max_off // 8 + 1)
    return k * 8

# -------------------------
# DUT helpers
# -------------------------





# -------------------------
# Oracle
# -------------------------
class RefState:
    def __init__(self, prog_end_addr=DATA_WINDOW_START):
        self.trace = []   # [(op, addr, width, val_before/after, reg, pc_tag)]
        self.x = [0]*32
        self.x[0] = 0  # x0
        self.memory = {}            # addr->byte_value
        self.verify_regs = set()    # registers that should be verified
        self.data_start = prog_end_addr  # treat [0..data_start-1] as "code"
        self.data_end = MEMORY_SIZE - 1

    def seed_code(self, code_bytes):
        """Copy assembled program bytes into oracle memory at [0..len-1]."""
        for i, b in enumerate(code_bytes):
            self.mem_write_byte(i, b)

    def w(self, rd, val):
        if rd != 0:
            self.x[rd] = val & MASK
            self.verify_regs.add(rd)


    def mem_write_byte(self, addr, val):
        a = wrap_addr(addr)
        self.memory[a] = val & 0xFF

    def mem_read_byte(self, addr):
        a = wrap_addr(addr)
        return self.memory.get(a, 0)

    def mem_write(self, addr, val, width):
        for i in range(width):
            a = wrap_addr(addr + i)
            vb = self.memory.get(a, 0)
            self.memory[a] = (val >> (i * 8)) & 0xFF
            self.trace.append(("W", a, 1, (vb, self.memory[a]), None, "mem"))

    def mem_read(self, addr, width, signed=False):
        val = 0
        for i in range(width):
            a = wrap_addr(addr + i)
            byte_val = self.memory.get(a, 0)
            val |= (byte_val << (i * 8))
            self.trace.append(("R", a, 1, byte_val, None, "mem"))
        if signed:
            val = sxt(val, width * 8)
        return val & MASK
    def dump_trace(self, last=32):
        print("---- Oracle mem trace (tail) ----")
        for t in self.trace[-last:]:
            print(t)
    def alu_bin(self, op, rd, rs1, rs2):
        a = self.x[rs1] & MASK
        b = self.x[rs2] & MASK

        if op == "add":
            res = (a + b) & MASK
        elif op == "sub":
            res = (a - b) & MASK
        elif op == "sll":
            res = (a << (b & 63)) & MASK
        elif op == "srl":
            res = ((a & MASK) >> (b & 63)) & MASK
        elif op == "sra":
            res = (to_s64(a) >> (b & 63)) & MASK
        elif op == "slt":
            res = 1 if to_s64(a) < to_s64(b) else 0
        elif op == "sltu":
            res = 1 if a < b else 0
        elif op == "xor":
            res = (a ^ b) & MASK
        elif op == "or":
            res = (a | b) & MASK
        elif op == "and":
            res = (a & b) & MASK
        else:
            raise ValueError(op)
        self.w(rd, res)

    def alu_imm(self, op, rd, rs1, imm):
        a = self.x[rs1] & MASK
        # Debug x2 andi operation

        if op == "addi":
            res = (a + sxt(imm, 12)) & MASK
        elif op == "slti":
            res = 1 if to_s64(a) < to_s64(sxt(imm, 12)) else 0
        elif op == "sltiu":
            res = 1 if a < (sxt(imm, 12) & MASK) else 0
        elif op == "xori":
            res = (a ^ sxt(imm, 12)) & MASK
        elif op == "ori":
            res = (a | sxt(imm, 12)) & MASK
        elif op == "andi":
            res = (a & sxt(imm, 12)) & MASK
        elif op == "slli":
            res = (a << (imm & 63)) & MASK
        elif op == "srli":
            res = ((a & MASK) >> (imm & 63)) & MASK
        elif op == "srai":
            res = (to_s64(a) >> (imm & 63)) & MASK
        else:
            raise ValueError(op)
        self.w(rd, res)

    def load_op(self, op, rd, rs1, imm):
        """Execute load (oracle mirrors DUT byte semantics; addresses already kept in data window by generator)."""
        addr = wrap_addr((self.x[rs1] + sxt(imm, 12)) & MASK)
        if op == "lb":
            val = self.mem_read(addr, 1, signed=True)
        elif op == "lh":
            val = self.mem_read(addr, 2, signed=True)
        elif op == "lw":
            val = self.mem_read(addr, 4, signed=True)   # RV64 LW sign-extends
        elif op == "ld":
            val = self.mem_read(addr, 8, signed=False)
        elif op == "lbu":
            val = self.mem_read(addr, 1, signed=False)
        elif op == "lhu":
            val = self.mem_read(addr, 2, signed=False)
        elif op == "lwu":
            val = self.mem_read(addr, 4, signed=False)  # RV64 LWU zero-extends
        else:
            raise ValueError(op)
        self.w(rd, val)

    def store_op(self, op, rs1, rs2, imm):
        """Execute store (addresses are kept in data window by generator)."""
        addr = wrap_addr((self.x[rs1] + sxt(imm, 12)) & MASK)
        val = self.x[rs2] & MASK
        if op == "sb":
            self.mem_write(addr, val, 1)
        elif op == "sh":
            self.mem_write(addr, val, 2)
        elif op == "sw":
            self.mem_write(addr, val, 4)
        elif op == "sd":
            self.mem_write(addr, val, 8)
        else:
            raise ValueError(op)

# -------------------------
# Branch helper
# -------------------------
def branch_taken(flav, a, b):
    sa, sb = to_s64(a), to_s64(b)
    if flav == "beq":  return a == b
    if flav == "bne":  return a != b
    if flav == "blt":  return sa < sb
    if flav == "bge":  return sa >= sb
    if flav == "bltu": return a < b
    if flav == "bgeu": return a >= b
    raise ValueError(flav)

# -------------------------
# Program generator
# -------------------------
def build_rand_block_with_memory(seed, idx, ref: RefState, len_block=15):
    random.seed((seed << 16) ^ idx)
    regs = list(range(1, 31))  # 1..30 (exclude x0 and x31)
    random.shuffle(regs)



    interesting = [
        0, 1, -1, 2, -2, 3, -3,
        0x7FFFFFFFFFFFFFFF, 0x8000000000000000,
        0x00000000FFFFFFFF, 0xFFFFFFFF00000000
    ]
    asm = []

    # Data regs
    data_regs = regs[:8]
    for r in data_regs:
        v = random.choice(interesting + [random.getrandbits(64) for _ in range(2)])
        if v < 0:
            asm.append(f"li x{r}, {v}")
            ref.w(r, v & MASK)
        else:
            asm.append(f"li x{r}, 0x{v & MASK:016x}")
            ref.w(r, v & MASK)

    # Base regs (8B aligned) *inside data window* - these should NEVER be modified by ALU ops
    base_regs = regs[8:11]
    for base_reg in base_regs:
        base_addr = rand_base_addr(8)
        asm.append(f"li x{base_reg}, {base_addr}")
        ref.w(base_reg, base_addr)

    # Branch regs - separate from data/base regs to avoid conflicts
    branch_regs = regs[11:14]  # Fixed: no overlap, use 11:14 instead of 11:15

    # Seed a few stores so later loads have something to read
    for i in range(3):
        store_reg = data_regs[i]
        base_reg = base_regs[i % len(base_regs)]
        offset = rand_offset_within_window(ref.x[base_reg], 8)
        asm.append(f"sd x{store_reg}, {offset}(x{base_reg})")
        ref.store_op("sd", base_reg, store_reg, offset)

    bin_ops = ["add","sub","sll","srl","sra","slt","sltu","xor","or","and"]
    imm_ops = ["addi","slti","sltiu","xori","ori","andi","slli","srli","srai"]
    load_ops = ["lb","lh","lw","ld","lbu","lhu","lwu"]
    store_ops = ["sb","sh","sw","sd"]

    W_STORE = {"sb":1,"sh":2,"sw":4,"sd":8}
    W_LOAD  = {"lb":1,"lh":2,"lw":4,"ld":8,"lbu":1,"lhu":2,"lwu":4}

    for t in range(len_block):
        op_type = random.choices(
            ["alu_imm", "alu_bin", "store_load", "load_use", "branch"],
            weights=[30, 25, 20, 20, 5]
        )[0]

        if op_type == "alu_imm":
            # Don't modify base registers - they must stay in data window
            available_regs = [r for r in regs if r not in base_regs]
            rd, rs1 = random.sample(available_regs, 2)
            op = random.choice(imm_ops)
            if op in ("slli","srli","srai"):
                sh = rand_shamt64()
                asm.append(f"{op} x{rd}, x{rs1}, {sh}")
                ref.alu_imm(op, rd, rs1, sh)
            else:
                imm = rand_imm12()
                asm.append(f"{op} x{rd}, x{rs1}, {imm}")
                ref.alu_imm(op, rd, rs1, imm)

        elif op_type == "alu_bin":
            # Don't modify base registers - they must stay in data window
            available_regs = [r for r in regs if r not in base_regs]
            rd, rs1, rs2 = random.sample(available_regs, 3)
            op = random.choice(bin_ops)
            asm.append(f"{op} x{rd}, x{rs1}, x{rs2}")
            ref.alu_bin(op, rd, rs1, rs2)

        elif op_type == "store_load":
            rs1 = random.choice(base_regs)        # base
            rs2 = random.choice(data_regs)        # data to store
            rd  = random.choice([r for r in regs if r not in [rs1, rs2] and r not in base_regs])  # load dest
            store_op = random.choice(store_ops)
            load_op  = random.choice(load_ops)
            width = max(W_STORE[store_op], W_LOAD[load_op])
            offset = rand_offset_within_window(ref.x[rs1], width)

            # Store then load back from the SAME address to test forwarding/coherency
            asm.append(f"{store_op} x{rs2}, {offset}(x{rs1})")
            ref.store_op(store_op, rs1, rs2, offset)

            asm.append(f"{load_op} x{rd}, {offset}(x{rs1})")
            ref.load_op(load_op, rd, rs1, offset)

            # Use the loaded value in an ALU op
            rs3 = random.choice(data_regs)
            alu_op = random.choice(bin_ops)
            result_reg = random.choice([r for r in regs if r not in [rd, rs3] and r not in base_regs])
            asm.append(f"{alu_op} x{result_reg}, x{rd}, x{rs3}")
            ref.alu_bin(alu_op, result_reg, rd, rs3)

        elif op_type == "load_use":
            base_reg = random.choice(base_regs)
            rd = random.choice([r for r in regs if r != base_reg and r not in base_regs])
            load_op = random.choice(load_ops)
            width = W_LOAD[load_op]
            offset = rand_offset_within_window(ref.x[base_reg], width)

            asm.append(f"{load_op} x{rd}, {offset}(x{base_reg})")
            ref.load_op(load_op, rd, base_reg, offset)

            if random.random() < 0.5:
                op = random.choice(imm_ops)
                result_reg = random.choice([r for r in regs if r != rd and r not in base_regs])
                if op in ("slli","srli","srai"):
                    sh = rand_shamt64()
                    asm.append(f"{op} x{result_reg}, x{rd}, {sh}")
                    ref.alu_imm(op, result_reg, rd, sh)
                else:
                    imm = rand_imm12()
                    asm.append(f"{op} x{result_reg}, x{rd}, {imm}")
                    ref.alu_imm(op, result_reg, rd, imm)
            else:
                rs2 = random.choice(data_regs)
                result_reg = random.choice([r for r in regs if r not in [rd, rs2] and r not in base_regs])
                op = random.choice(bin_ops)
                asm.append(f"{op} x{result_reg}, x{rd}, x{rs2}")
                ref.alu_bin(op, result_reg, rd, rs2)

        elif op_type == "branch":
            # Use dedicated branch registers to avoid conflicts with data/base regs
            rsA = random.choice(data_regs)  # Compare a data register
            rsB = random.choice(branch_regs)  # Use branch register for comparison value
            flavor = random.choice(["beq","bne","blt","bge","bltu","bgeu"])
            taken = random.choice([True, False])

            # set up b so condition matches 'taken' choice
            a = ref.x[rsA] & MASK
            b = ref.x[rsB] & MASK
            if flavor == "beq":
                b = a if taken else (a+1) & MASK
            elif flavor == "bne":
                b = (a+1) & MASK if taken else a
            elif flavor == "blt":
                b = (to_s64(a) + random.randint(1, 100)) & MASK if taken else (to_s64(a) - random.randint(0, 100)) & MASK
            elif flavor == "bge":
                b = (to_s64(a) - random.randint(0, 100)) & MASK if taken else (to_s64(a) + random.randint(1, 100)) & MASK
            elif flavor == "bltu":
                if taken:
                    b = a + random.randint(1, 100) if a < MASK - 100 else a - random.randint(1, 100)
                else:
                    b = a - random.randint(0, 100) if a > 100 else a + random.randint(1, 100)
                b &= MASK
            elif flavor == "bgeu":
                if taken:
                    b = a - random.randint(0, 100) if a > 100 else a + random.randint(1, 100)
                else:
                    b = a + random.randint(1, 100) if a < MASK - 100 else a - random.randint(1, 100)
                b &= MASK

            # materialize b
            if to_s64(b) < 0:
                asm.append(f"li x{rsB}, {to_s64(b)}")
            else:
                asm.append(f"li x{rsB}, 0x{b:016x}")
            ref.w(rsB, b)

            taken_actual = branch_taken(flavor, a & MASK, b & MASK)


            Lskip = f"L_SKIP_{idx}_{t}"
            Ldone = f"L_DONE_{idx}_{t}"

            asm.append(f"{flavor} x{rsA}, x{rsB}, {Lskip}")

            # wrong-path memory ops (will be skipped if branch taken)
            remaining_regs = regs[14:]  # Use remaining registers for branch operations
            skip_store_reg = random.choice(data_regs)
            skip_load_reg  = random.choice(remaining_regs)
            skip_base      = random.choice(base_regs)
            skip_off       = rand_offset_within_window(ref.x[skip_base], 8)
            not_taken_marker_reg = random.choice(remaining_regs)
            taken_marker_reg = random.choice([r for r in remaining_regs if r != not_taken_marker_reg])

            asm.append(f"li x{skip_store_reg}, 0xCAFEBABE")
            asm.append(f"sd x{skip_store_reg}, {skip_off}(x{skip_base})")
            asm.append(f"ld x{skip_load_reg}, {skip_off}(x{skip_base})")
            asm.append(f"li x{not_taken_marker_reg}, 2")  # Not-taken marker (harmless)
            asm.append(f"jal x0, {Ldone}")

            asm.append(f"{Lskip}:")
            asm.append(f"li x{taken_marker_reg}, 1")  # Taken marker

            asm.append(f"{Ldone}:")

            # Update oracle for the actually executed path
            if taken_actual:
                # Branch taken - execute the taken path
                ref.w(taken_marker_reg, 1)  # Taken marker
            else:
                # Branch not taken - execute the fall-through path
                ref.w(skip_store_reg, 0xCAFEBABE)
                ref.store_op("sd", skip_base, skip_store_reg, skip_off)
                ref.load_op("ld", skip_load_reg,  skip_base, skip_off)
                ref.w(not_taken_marker_reg, 2)  # Not-taken marker

    return "\n".join(asm)

# -------------------------
# Fuzz test (drop-in)
# -------------------------
@cocotb.test()
async def test_randomized_memory_fuzz(dut):
    NUM_PROGRAMS = 500
    LEN_BLOCK = 25
    BASE_SEED = 0xDEADBEEF

    for i in range(NUM_PROGRAMS):
        ref = RefState(prog_end_addr=DATA_WINDOW_START)

        body = build_rand_block_with_memory(BASE_SEED, i, ref, len_block=LEN_BLOCK)
        asm = f"""
        # --- randomized memory fuzz {i} ---
        {body}
        ecall
        """

        # Assemble once, seed oracle with code bytes, then load DUT
        compiled = assemble_rv32i_bytes(asm)
        ref.seed_code(compiled)

        dut._log.info(asm)
        loadCompiledToMemory(compiled, dut)
        await resetAndPrepare(dut)

        await ReadWrite()
        clock = Clock(dut.clk, 1, unit="ns")
        cocotb.start_soon(clock.start())
        await First(RisingEdge(dut.program_complete), Timer(10000, unit="ns"))
        checkFinished(dut)
        clock.stop()
        #ref.dump_trace(40)
        # Verify only registers that were actually modified
        for r in ref.verify_regs:
            if r != 31:  # Skip x31 (scratch)
                exp = ref.x[r]
                checkRegister(r, to_s64(exp), dut, True)
