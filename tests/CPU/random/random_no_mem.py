import random
import math
import cocotb
from cocotb.clock import Clock, Timer
from cocotb.triggers import RisingEdge, ReadOnly, ReadWrite, First
import sys, os
sys.path.append(os.path.dirname(__file__))
from tests.CPU.riscv_tests_gen import *
from tests.CPU.test_helpers import *



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

XLEN = 64
MASK = (1 << XLEN) - 1

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
    random.shuffle(pool)
    return pool[:k]

class RefState:
    def __init__(self):
        self.x = [0]*32
        self.x[0] = 0  # x0
        self.mark = {}  # reg->value

    def w(self, rd, val):
        if rd != 0:
            self.x[rd] = val & MASK

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
def branch_taken(flav, a, b):
    sa, sb = to_s64(a), to_s64(b)  # signed views
    if flav == "beq":  return a == b
    if flav == "bne":  return a != b
    if flav == "blt":  return sa < sb
    if flav == "bge":  return sa >= sb
    if flav == "bltu": return a < b
    if flav == "bgeu": return a >= b
    raise ValueError(flav)
def build_rand_block(seed, idx, ref: RefState, len_block=25):
    random.seed((seed << 16) ^ idx)

    # Exclude x0 and x31 from all random use; x31 is our dedicated AUIPC/JALR scratch.
    regs = list(range(1, 31))  # 1..30
    random.shuffle(regs)

    # Seed a few registers with interesting values
    interesting = [
        0, 1, -1, 2, -2, 3, -3,
        0x7FFFFFFFFFFFFFFF, 0x8000000000000000,
        0x00000000FFFFFFFF, 0xFFFFFFFF00000000
    ]
    asm = []
    for r in regs[:8]:
        v = random.choice(interesting + [random.getrandbits(64) for _ in range(2)])
        if v < 0:
            asm.append(f"li x{r}, {v}")
            ref.w(r, v & MASK)
        else:
            asm.append(f"li x{r}, 0x{v & MASK:016x}")
            ref.w(r, v & MASK)

    # Random ALU mix
    bin_ops = ["add","sub","sll","srl","sra","slt","sltu","xor","or","and"]
    imm_ops = ["addi","slti","sltiu","xori","ori","andi","slli","srli","srai"]

    for _ in range(len_block):
        if random.random() < 0.55:
            # imm op
            rd, rs1 = random.sample(regs, 2)
            op = random.choice(imm_ops)
            if op in ("slli","srli","srai"):
                sh = rand_shamt64()
                asm.append(f"{op} x{rd}, x{rs1}, {sh}")
                ref.alu_imm(op, rd, rs1, sh)
            else:
                imm = rand_imm12()
                asm.append(f"{op} x{rd}, x{rs1}, {imm}")
                ref.alu_imm(op, rd, rs1, imm)
        else:
            # bin op
            rd, rs1, rs2 = random.sample(regs, 3)
            op = random.choice(bin_ops)
            asm.append(f"{op} x{rd}, x{rs1}, x{rs2}")
            ref.alu_bin(op, rd, rs1, rs2)

        # Occasionally drop a guaranteed-taken or guaranteed-not-taken branch
        if random.random() < 0.10:
            rsA, rsB = random.sample(regs, 2)
            flavor = random.choice(["beq","bne","blt","bge","bltu","bgeu"])
            taken = random.choice([True, False])

            cands = [r for r in regs if r not in (rsA, rsB)]
            mreg = random.choice(cands) if cands else random.choice(regs)
            ref.mark[mreg] = 1
            asm.append(f"li x{mreg}, 99")
            ref.w(mreg, 99)

            a = ref.x[rsA] & MASK
            b = ref.x[rsB] & MASK
            def ensure(flav, want_taken):
                nonlocal a,b
                if flav == "beq":
                    b = a if want_taken else (a+1) & MASK
                elif flav == "bne":
                    b = (a+1) & MASK if want_taken else a
                elif flav == "blt":
                    b = (to_s64(a) + random.randint(1, 100)) & MASK if want_taken \
                        else (to_s64(a) - random.randint(0, 100)) & MASK
                elif flav == "bge":
                    b = (to_s64(a) - random.randint(0, 100)) & MASK if want_taken \
                        else (to_s64(a) + random.randint(1, 100)) & MASK
                elif flav == "bltu":
                    if want_taken:
                        b = a + random.randint(1, 100) if a < MASK - 100 else a - random.randint(1, 100)
                    else:
                        b = a - random.randint(0, 100) if a > 100 else a + random.randint(1, 100)
                    b &= MASK
                elif flav == "bgeu":
                    if want_taken:
                        b = a - random.randint(0, 100) if a > 100 else a + random.randint(1, 100)
                    else:
                        b = a + random.randint(1, 100) if a < MASK - 100 else a - random.randint(1, 100)
                    b &= MASK
            ensure(flavor, taken)

            # Materialize rsB update
            if rsB == 0:
                rsB = mreg
            if (to_s64(b) < 0):
                asm.append(f"li x{rsB}, {to_s64(b)}")
            else:
                asm.append(f"li x{rsB}, 0x{b:016x}")
            ref.w(rsB, b)
            taken_actual = branch_taken(flavor, a & MASK, b & MASK)

            Lpass = f"L_PASS_{idx}_{_}"
            Ldone = f"L_DONE_{idx}_{_}"
            asm.append(f"{flavor} x{rsA}, x{rsB}, {Lpass}")
            asm.append(f"li x{mreg}, 2")          # fail mark
            asm.append(f"jal x0, {Ldone}")        # NO LINK
            asm.append(f"{Lpass}:")
            asm.append(f"li x{mreg}, 1")          # pass mark
            asm.append(f"{Ldone}:")
            ref.w(mreg, 1 if taken_actual else 2)

        # Occasionally drop a forward JAL skip (verifies control transfer only)
        if random.random() < 0.08:
            skip = f"SKIP_{idx}_{_}"
            mr = random.choice(regs)
            asm.append(f"li x{mr}, 99")
            asm.append(f"jal x0, {skip}")        # NO LINK
            asm.append(f"li x{mr}, 2")           # must be skipped
            asm.append(f"{skip}:")
            asm.append(f"li x{mr}, 1")
            ref.w(mr, 1)

        # Occasionally drop an AUIPC-based JALR to a known label (no link, scratch x31)
        if random.random() < 0.05:
            tgt = f"TARG_{idx}_{_}"
            lbl = f"LBL_{idx}_{_}"
            mr = random.choice(regs)

            asm.append(f"li x{mr}, 99")
            asm.append(f"{lbl}:")
            asm.append(f"auipc x31, %pcrel_hi({tgt})")
            asm.append(f"addi  x31, x31, %pcrel_lo({lbl})")  # pair with AUIPC at {lbl}
            asm.append(f"jalr  x0, x31, 0")                  # NO LINK

            asm.append(f"li x{mr}, 2")       # fall-through must be skipped
            asm.append(f"{tgt}:")
            asm.append(f"li x{mr}, 1")
            ref.w(mr, 1)

    return "\n".join(asm)

@cocotb.test()
async def test_randomized_non_memory_fuzz(dut):
    NUM_PROGRAMS = 1000
    LEN_BLOCK = 200
    BASE_SEED = 0xC0FFEE  # tweak for different runs

    for i in range(NUM_PROGRAMS):
        ref = RefState()
        body = build_rand_block(BASE_SEED, i, ref, len_block=LEN_BLOCK)
        asm = f"""
        # --- randomized non-memory fuzz {i} ---
        {body}
        ecall
        """
        dut._log.info(asm)
        await resetAndPrepare(dut)
        loadAsmToMemory(asm, dut)
        await ReadWrite()
        clock = Clock(dut.clk, 1, unit="ns")
        cocotb.start_soon(clock.start())
        await First(RisingEdge(dut.program_complete), Timer(5000, unit="ns"))
        checkFinished(dut)
        clock.stop()

        # Verify all registers we actually touched; skip x31 (scratch)
        for r in range(1, 32):
            if r == 31:
                continue
            exp = ref.x[r]
            if exp != 0 or r in ref.mark:
                checkRegister(r, to_s64(exp), dut, True)
