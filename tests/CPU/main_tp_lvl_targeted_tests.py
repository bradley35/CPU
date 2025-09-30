import cocotb
from cocotb.clock import Clock, Timer
from cocotb.triggers import RisingEdge, ReadOnly, ReadWrite, First
import sys, os
sys.path.append(os.path.dirname(__file__))
from tests.CPU.riscv_tests_gen import *
from tests.CPU.test_helpers import *

@cocotb.test()
async def nothing_test(dut):
    clock = Clock(dut.clk, 1, unit="ns")
    await resetAndPrepare(dut)
    cocotb.start_soon(clock.start())
    await Timer(1000, unit="ns")
    clock.stop()
    
@cocotb.test()
async def test_single_add(dut):
    # Load add into memory
    asm = """
    add   x3, x1, x2
    add   x3, x1, x2
    add   x3, x1, x2
    add   x3, x1, x2
    add   x3, x1, x2
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    loadRegisters([0, 1535, 8462, 5473, 9], dut)
    clock = Clock(dut.clk, 1, unit="ns")
    cocotb.start_soon(clock.start())
    await First(RisingEdge(dut.program_complete), Timer(100, unit="ns"))
    checkRegister(3, 1535 + 8462, dut)
    checkFinished(dut)
    clock.stop()

# @cocotb.test()
# async def double_test(dut):
#     # Load add into memory
#     asm = """
#     add   x3, x1, x2
#     ecall
#     """
#     loadAsmToMemory(asm, dut)
#     await resetAndPrepare(dut)
#     loadRegisters([0, 1535, 8462, 5473, 9], dut)
#     cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
#     await First(RisingEdge(dut.program_complete), Timer(100, unit="ns"))
#     checkRegister(3, 1535 + 8462, dut)
#     checkFinished(dut)
#     loadAsmToMemory(asm, dut)

#     await resetAndPrepare(dut)
#     loadRegisters([0, 1535, 8462, 5473, 9], dut)
#     cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
#     await First(RisingEdge(dut.program_complete), Timer(100, unit="ns"))
#     checkRegister(3, 1535 + 8462, dut)
#     checkFinished(dut)

@cocotb.test()
async def test_single_sub(dut):
    # Load add into memory
    asm = """
    sub   x3, x1, x2
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    loadRegisters([0, 1535, 8462, 5473, 9], dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(100, unit='ns'))
    checkRegister(3, 1535 - 8462, dut, True)
    checkFinished(dut)

@cocotb.test()
async def test_single_add_imm(dut):
    # Load add into memory
    asm = """
    add x3, x1, 30
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    loadRegisters([0, 1535, 8462, 5473, 9], dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await RisingEdge(dut.program_complete)
    checkRegister(3, 1535 + 30, dut, True)

@cocotb.test()
async def test_single_shift_imm_logical(dut):
    # Load add into memory
    asm = """
    srl x3, x1, 1
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    loadRegisters([0, -10, 8462, 5473, 9], dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await RisingEdge(dut.program_complete)
    checkRegister(3, 9223372036854775803, dut, True)

@cocotb.test()
async def test_single_shift_imm_arithmetic(dut):
    # Load add into memory
    asm = """
   srai x3, x1, 1
   ecall
   """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    loadRegisters([0, -10, 8462, 5473, 9], dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await RisingEdge(dut.program_complete)
    checkRegister(3, -5, dut, True)

@cocotb.test()
async def test_multiple_instruction_no_deps(dut):
    # Load add into memory
    asm = """
    add x10, x1, x2
    add x11, x1, x3 # x3 is negative
    or x12, x3, x4
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    loadRegisters([0, 745628, 48392, -10, 10], dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await RisingEdge(dut.program_complete)
    checkRegister(10, 745628 + 48392, dut, True)
    checkRegister(11, 745628 - 10, dut, True)
    checkRegister(12, -2, dut, True)


@cocotb.test()
async def test_multiple_instruction_far_deps(dut):
    # Load add into memory
    asm = """
    add x10, x1, x2
    nop
    nop
    nop
    nop
    add x11, x10, x10
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    loadRegisters([0, 745628, 48392, -10, 10], dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await RisingEdge(dut.program_complete)
    checkRegister(10, 745628 + 48392, dut, True)
    checkRegister(11, ( 745628 + 48392) * 2, dut, True)

@cocotb.test()
async def test_multiple_instruction_close_deps(dut):
    # Load add into memory
    asm = """
    add x10, x1, x2
    nop
    add x11, x10, x10
    add x12, x11, 35
    add x13, x11, -9
    add x14, x13, 1024
    add x14, x1, 0
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    loadRegisters([0, 745628, 48392, -10, 10], dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await RisingEdge(dut.program_complete)
    reg_10 = 745628 + 48392
    reg_11 = reg_10 + reg_10
    reg_12 = reg_11 + 35
    reg_13 = reg_11 - 9
    reg_14 = reg_13 + 1024
    reg_14 = 745628 + 0

    checkRegister(10, reg_10, dut, True)
    checkRegister(11, reg_11, dut, True)
    checkRegister(12, reg_12, dut, True)
    checkRegister(13, reg_13, dut, True)
    checkRegister(14, reg_14, dut, True)



@cocotb.test()
async def test_big_immediate(dut):
    # Load add into memory
    asm = """
    .insn u 0x37, x3, 0x7FFFF
    li x4, 0b1010101010101010101010101010101010101010101010101010101010101010
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await RisingEdge(dut.program_complete)
    checkRegister(3, 0x7FFFF000, dut, False)
    checkRegister(4, 0b1010101010101010101010101010101010101010101010101010101010101010, dut)
@cocotb.test()
async def test_jump(dut):
    # Load add into memory
    asm = """
    add   x3, x1, x2
    jal x5, skip
    add   x3, x0, x0
    skip:
    add x4, x3, 5
    jal x5, skip2
    ecall
    endo:
    ecall
    skip2:
    li x10, 12345
    jal x5, endo
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    loadRegisters([0, 3, 4, 111, 111], dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(50, unit="ns"))
    checkRegister(3, 7, dut, False)
    checkRegister(4, 12, dut, False)
    checkRegister(10, 12345, dut)
    checkRegister(5, 6*4 + 4, dut, False)
    checkFinished(dut)


@cocotb.test()
async def test_auipc(dut):
    # Load add into memory
    asm = """
    nop
    nop
    nop
    nop
    nop
    nop
    auipc x3, 0x101
    nop
    nop
    nop
    nop
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(50, unit="ns"))
    checkRegister(3, 6*4+0x101000, dut, True)
    checkFinished(dut)

# @cocotb.test()
# async def double_test2(dut):
#     await test_jump(dut)
#     await test_auipc(dut)

@cocotb.test()
async def test_jump_reg(dut):
    asm = """
    li x3, 5
    jalr x1, x3, 23
    add   x3, x0, x0
    skip:
    add x4, x3, 5
    jal x1, skip2
    ecall
    endo:
    ecall
    skip2:
    li x10, 12345
    jal x5, endo
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await RisingEdge(dut.program_complete)
    checkRegister(10, 12345, dut, True)
    checkRegister(1, 32, dut, True)
    checkRegister(3, 5, dut)
    checkRegister(4, 0, dut)

@cocotb.test()
async def test_branch_beq_mixed(dut):
    asm = """
    # Setup equal / not-equal pairs
    li x3, 10
    li x4, 10          # x3 == x4  (should TAKE)
    li x5, 7
    li x6, 8           # x5 != x6  (should NOT take)
    li x7, -1
    li x8, -1          # x7 == x8  (should TAKE)
    li x9, 3           # x0 != x9  (should NOT take)

    # --- Case 1: should TAKE (x3 == x4) ---
    li x21, 99
    beq x3, x4, T1
    addi x21, x0, 2        # fail mark (should NOT execute)
    jal x0, AfterT1
T1:
    addi x21, x0, 1        # pass mark
AfterT1:

    # --- Case 2: should NOT take (x5 != x6) ---
    li x22, 99
    beq x5, x6, T2
    addi x22, x0, 1        # pass mark
    jal x0, AfterT2
T2:
    addi x22, x0, 2        # fail mark (should NOT execute)
AfterT2:

    # --- Case 3: should TAKE (x0 == x0) ---
    li x23, 99
    beq x0, x0, T3
    addi x23, x0, 2        # fail mark (should NOT execute)
    jal x0, AfterT3
T3:
    addi x23, x0, 1        # pass mark
AfterT3:

    # --- Case 4: should TAKE (x7 == x8 == -1) ---
    li x24, 99
    beq x7, x8, T4
    addi x24, x0, 2        # fail mark (should NOT execute)
    jal x0, AfterT4
T4:
    addi x24, x0, 1        # pass mark
AfterT4:

    # --- Case 5: should NOT take (x0 != x9) ---
    li x25, 99
    beq x0, x9, T5
    addi x25, x0, 1        # pass mark
    jal x0, AfterT5
T5:
    addi x25, x0, 2        # fail mark (should NOT execute)
AfterT5:

    # All done
    ecall
    """

    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(100, unit="ns"))
    checkFinished(dut)

    # Expected: x21=1 (taken), x22=1 (not taken), x23=1 (taken), x24=1 (taken), x25=1 (not taken)
    checkRegister(21, 1, dut, True)
    checkRegister(22, 1, dut, True)
    checkRegister(23, 1, dut, True)
    checkRegister(24, 1, dut, True)
    checkRegister(25, 1, dut, True)


@cocotb.test()
async def test_branches_mixed(dut):
    asm = """
    # Setup values
    li x1,  5
    li x2,  5
    li x3,  -3
    li x4,  7
    li x5,  0xFFFFFFFF     # -1 signed, 4294967295 unsigned
    li x6,  0               # 0

    # x21: BNE should NOT take (x1 == x2)
    li x21, 99
    bne x1, x2, L_bne_fail
    addi x21, x0, 1
    jal x0, L_bne_after
L_bne_fail:
    addi x21, x0, 2
L_bne_after:

    # x22: BLT (signed) should TAKE  (-3 < 7)
    li x22, 99
    blt x3, x4, L_blt_pass
    addi x22, x0, 2
    jal x0, L_blt_after
L_blt_pass:
    addi x22, x0, 1
L_blt_after:

    # x23: BGE (signed) should TAKE  (7 >= -3)
    li x23, 99
    bge x4, x3, L_bge_pass
    addi x23, x0, 2
    jal x0, L_bge_after
L_bge_pass:
    addi x23, x0, 1
L_bge_after:

    # x24: BLTU (unsigned) should TAKE (0xFFFFFFFF > 0)
    li x24, 99
    bltu x6, x5, L_bltu_pass
    addi x24, x0, 2
    jal x0, L_bltu_after
L_bltu_pass:
    addi x24, x0, 1
L_bltu_after:

    # x25: BGEU (unsigned) should NOT take (0 !>= 0xFFFFFFFF)
    li x25, 99
    bgeu x6, x5, L_bgeu_fail
    addi x25, x0, 1
    jal x0, L_bgeu_after
L_bgeu_fail:
    addi x25, x0, 2
L_bgeu_after:

    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(100, unit="ns"))

    checkRegister(21, 1, dut, True)  # BNE not taken
    checkRegister(22, 1, dut, True)  # BLT taken
    checkRegister(23, 1, dut, True)  # BGE taken
    checkRegister(24, 1, dut, True)  # BLTU taken
    checkRegister(25, 1, dut, True)  # BGEU not taken

@cocotb.test()
async def test_branch_backward_loop(dut):
    asm = """
    # x10 counts down from 4 to 0; loop uses a backward branch
    li x10, 4
    li x11, 0          # iteration counter
    li x12, 0          # will end as sum of 4+3+2+1 (10)

LoopStart:
    add  x12, x12, x10 # accumulate
    addi x11, x11, 1   # iter++
    addi x10, x10, -1  # x10--
    bge  x10, x0, LoopStart  # signed; loops while x10 >= 0

    # Post-conditions:
    # x10 == -1 (stopped after reaching 0 then decremented)
    # x11 == 5  (5 iterations: 4,3,2,1,0)
    # x12 == 10 (sum 4+3+2+1)
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(100, unit="ns"))

    checkRegister(10, -1, dut, True)  # ended at -1
    checkRegister(11, 5,  dut, True)  # 5 iterations
    checkRegister(12, 10, dut, True)  # accumulated 10

@cocotb.test()
async def test_branch_edge_cases(dut):
    asm = """
    # Hazard 1: Branch immediately using the result of prior ALU op
    li  x1,  8
    li  x2,  7
    add x3,  x1, x2     # x3 = 15
    li  x4,  15
    li  x20, 99
    beq x3, x4, H1_TAKEN    # should TAKE if bypass/scoreboard is correct
    addi x20, x0, 2         # fail path
    jal x0, H1_DONE
H1_TAKEN:
    addi x20, x0, 1
H1_DONE:

    # Hazard 2: Branch into another branch (chain)
    # First branch targets label with a second branch that SHOULD NOT take
    li  x5, 1
    li  x6, 1
    li  x7, 2
    li  x21, 99
    beq x5, x6, H2_L1       # first should TAKE (equal)
    addi x21, x0, 3         # fail (didn't take first)
    jal x0, H2_DONE
H2_L1:
    bne x5, x7, H2_L2       # 1 != 2, so SHOULD TAKE to H2_L2
    addi x21, x0, 4         # fail (second didn't take when it should)
    jal x0, H2_DONE
H2_L2:
    addi x21, x0, 1         # pass
H2_DONE:

    # Hazard 3: Zero register comparisons + tiny offsets
    # Use a near (small positive) offset and fall-through verification
    li  x22, 99
    beq x0, x0, H3_PASS     # ALWAYS take, tiny forward offset
    addi x22, x0, 2         # fail
    jal x0, H3_DONE
H3_PASS:
    addi x22, x0, 1
H3_DONE:

    # Hazard 4: Negative branch offset (small backward hop that is NOT taken)
    li  x8,  3
    li  x9,  4
    li  x23, 99
H4_POINT:
    bge x8, x9, H4_BACK     # 3 >= 4? NO => not taken
    addi x23, x0, 1         # pass
    jal x0, H4_END
H4_BACK:
    # If taken (incorrectly), jump back two instructions (negative offset region)
    addi x23, x0, 2
    jal x0, H4_END
H4_END:

    # Hazard 5: Signed vs Unsigned around boundary (0xFFFFFFFF vs 0)
    # - BLT (signed): -1 < 0 -> TAKE
    # - BLTU (unsigned): 0xFFFFFFFFFFFFFFFF < 0 -> NOT take
    li  x24, 99
    li  x25, 0xFFFFFFFFFFFFFFFF
    li  x26, 0
    blt  x25, x26, H5_SIGNED_PASS    # signed: -1 < 0 => TAKE
    addi x24, x0, 2                  # fail
    jal x0, H5_SIGNED_DONE
H5_SIGNED_PASS:
    addi x24, x0, 1
H5_SIGNED_DONE:

    li  x27, 99
    bltu x25, x26, H5_UNSIGNED_FAIL  # unsigned: 0xFFFFFFFF < 0 ? NO
    addi x27, x0, 1                  # pass (not taken)
    jal x0, H5_UNSIGNED_DONE
H5_UNSIGNED_FAIL:
    addi x27, x0, 2                  # fail
H5_UNSIGNED_DONE:

    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await RisingEdge(dut.program_complete)

    # Hazard 1
    checkRegister(20, 1, dut, True)
    # Hazard 2 (branch into branch)
    checkRegister(21, 1, dut, True)
    # Hazard 3 (x0==x0 tiny forward)
    checkRegister(22, 1, dut, True)
    # Hazard 4 (negative/backward candidate not taken)
    checkRegister(23, 1, dut, True)
    # Hazard 5 signed/unsigned boundaries
    checkRegister(24, 1, dut, True)
    checkRegister(27, 1, dut, True)


@cocotb.test()
async def test_branch_tight_dependencies(dut):
    asm = """
    # Create value via multiple dependent ALU ops, then branch on it immediately
    li  x1,  12
    li  x2,  5
    add x3,  x1, x2      # 17
    addi x3, x3, -2      # 15
    xor x3,  x3, x0      # still 15
    li  x4,  15

    li  x20, 99
    beq x3, x4, PASS1    # should TAKE immediately based on fresh result
    addi x20, x0, 2
    jal x0, AFTER1
PASS1:
    addi x20, x0, 1
AFTER1:

    # Now unsigned compare on same value vs a boundary
    li  x21, 99
    li  x5,  0xFFFFFFF0
    li  x6,  0x0000000F
    bltu x6, x5, PASS2   # 15 < 0xFFFFFFF0 (unsigned) => TAKE
    addi x21, x0, 2
    jal x0, AFTER2
PASS2:
    addi x21, x0, 1
AFTER2:

    # Backward short loop with immediate dependency on the updated counter
    li  x7, 3
    li  x22, 0
LOOP:
    addi x22, x22, 1    # ++
    addi x7,  x7,  -1   # -- (new value used immediately)
    bne  x7,  x0, LOOP  # backward branch with data hazard on x7

    # Expect x22 = 3 (ran for 3 iterations)
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await RisingEdge(dut.program_complete)

    checkRegister(20, 1, dut, True)  # PASS1
    checkRegister(21, 1, dut, True)  # PASS2
    checkRegister(22, 3, dut, True)  # loop count

@cocotb.test()
async def test_jalr_flush(dut):
    asm = """
        addi x6, x0, 0
        addi x7, x0, 0
1:
        auipc x5, %pcrel_hi(target)
        addi  x5, x5, %pcrel_lo(1b)       # pair with AUIPC above
        addi  x6, x0, 1                   # may execute before redirect (OK)
        jalr  x0, x5, 0                   # jalr imm must be 0
        addi  x7, x7, 2                   # MUST be squashed on redirect
target:
        addi  x7, x7, 3                   # executes exactly once
        ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(500, unit="ns"))
    checkFinished(dut)
    checkRegister(6, 1, dut, True)
    checkRegister(7, 3, dut, True)


@cocotb.test()
async def test_jal_flush(dut):
    """
    Same as above but using a PC-relative JAL to a forward target.
    Ensures the fall-through instruction is squashed and the target runs once.
    """
    asm = """
        addi x6, x0, 0
        addi x7, x0, 0
1:
        addi  x6, x0, 1               # may execute pre-redirect (OK)
        jal   x0, target - 1b         # jump forward to 'target'
        addi  x7, x7, 2               # MUST be squashed on redirect
target:
        addi  x7, x7, 3               # executes exactly once
        ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(500, unit="ns"))

    checkFinished(dut)
    checkRegister(6, 1, dut, True)
    checkRegister(7, 3, dut, True)

@cocotb.test()
async def test_ori(dut):
    asm = """
        li x1, 0b100
        ori x3, x1, 0b001
        ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(500, unit="ns"))
    checkFinished(dut)
    checkRegister(3, 0b101, dut, True)

@cocotb.test()
async def test_addw(dut):
    asm = """
        li x1, 0xFF
        sll x1, x1,  35
        li x2, 1
        sll x2, x2, 31
        add x3, x1, x2
        addw x4, x1, x2
        ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await RisingEdge(dut.program_complete)
    checkRegister(1, 8761733283840, dut, True)
    checkRegister(2, 0b10000000000000000000000000000000, dut, True)
    checkRegister(3, 8763880767488, dut, True)
    checkRegister(4, -2147483648, dut, True)

@cocotb.test()
async def test_srli_64bit(dut):
    # Test SRLI (Shift Right Logical Immediate) - 64-bit operation
    asm = """
        li x1, 0xFFFFFFFFFFFFFFFF  # All 1s (64-bit)
        srli x2, x1, 4            # Shift right by 4, logical
        srli x3, x1, 63           # Shift right by 63, logical
        li x4, 0x8000000000000000  # MSB set
        srli x5, x4, 1            # Shift MSB right by 1
        ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await RisingEdge(dut.program_complete)
    checkRegister(2, 0x0FFFFFFFFFFFFFFF, dut, False)  # Logical shift fills with 0s
    checkRegister(3, 0x0000000000000001, dut, False)  # Only LSB remains
    checkRegister(5, 0x4000000000000000, dut, False)  # MSB becomes 0

@cocotb.test()
async def test_srliw_32bit_truncation(dut):
    # Test SRLIW (Shift Right Logical Immediate Word) - 32-bit operation with sign extension
    asm = """
        li x1, 0xFFFFFFFF12345678  # 64-bit value with upper bits set
        srliw x2, x1, 4           # Should operate on lower 32 bits only, then sign extend
        li x3, 0x8000000080000000  # High bit set in both upper and lower 32 bits
        srliw x4, x3, 1           # Should shift only lower 32 bits
        li x5, 0x7FFFFFFF7FFFFFFF  # Positive in both upper and lower 32 bits
        srliw x6, x5, 31          # Shift all the way to get 0 (positive MSB)
        ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await RisingEdge(dut.program_complete)
    # SRLIW operates on lower 32 bits (0x12345678), shifts right by 4 -> 0x01234567
    # Then sign extends: 0x01234567 is positive, so result is 0x0000000001234567
    checkRegister(2, 0x01234567, dut, False)
    # SRLIW operates on lower 32 bits (0x80000000), shifts right by 1 -> 0x40000000
    # Then sign extends: 0x40000000 is positive, so result is 0x0000000040000000
    checkRegister(4, 0x40000000, dut, False)
    # SRLIW operates on lower 32 bits (0x7FFFFFFF), shifts right by 31 -> 0x00000000
    # Then sign extends: 0x00000000 is positive, so result is 0x0000000000000000
    checkRegister(6, 0x00000000, dut, False)

@cocotb.test()
async def test_srai_64bit_arithmetic(dut):
    # Test SRAI (Shift Right Arithmetic Immediate) - 64-bit operation with sign extension
    asm = """
        li x1, 0xFFFFFFFFFFFFFFFF  # All 1s (64-bit negative)
        srai x2, x1, 4            # Arithmetic shift right by 4
        srai x3, x1, 63           # Arithmetic shift right by 63
        li x4, 0x8000000000000000  # Most negative 64-bit number
        srai x5, x4, 1            # Arithmetic shift right by 1
        li x6, 0x7FFFFFFFFFFFFFFF  # Most positive 64-bit number
        srai x7, x6, 1            # Arithmetic shift right by 1
        ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await RisingEdge(dut.program_complete)
    # SRAI on negative number fills with 1s
    checkRegister(2, 0xFFFFFFFFFFFFFFFF, dut, False)  # Still all 1s
    checkRegister(3, 0xFFFFFFFFFFFFFFFF, dut, False)  # Still all 1s
    # Most negative number shifted right arithmetically
    checkRegister(5, 0xC000000000000000, dut, False)  # Sign extended
    # Most positive number shifted right arithmetically
    checkRegister(7, 0x3FFFFFFFFFFFFFFF, dut, False)  # Zero fill from left

@cocotb.test()
async def test_sraiw_32bit_arithmetic_truncation(dut):
    # Test SRAIW (Shift Right Arithmetic Immediate Word) - 32-bit operation with sign extension
    asm = """
        li x1, 0xFFFFFFFF80000000  # Upper bits set, lower 32 bits = 0x80000000 (negative)
        sraiw x2, x1, 4           # Arithmetic shift on lower 32 bits, then sign extend
        li x3, 0x1234567880000000  # Different upper bits, same negative lower 32 bits
        sraiw x4, x3, 1           # Should give same result as x2 shifted by 1 less
        li x5, 0xFFFFFFFF7FFFFFFF  # Upper bits set, lower 32 bits = 0x7FFFFFFF (positive)
        sraiw x6, x5, 4           # Arithmetic shift on positive lower 32 bits
        li x7, 0x00000000FFFFFFFF  # Lower 32 bits all 1s (0xFFFFFFFF = -1 in 32-bit)
        sraiw x8, x7, 8           # Shift -1 right by 8 bits
        ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await RisingEdge(dut.program_complete)
    # SRAIW on 0x80000000 (most negative 32-bit) >> 4 = 0xF8000000, sign extended to 0xFFFFFFFFF8000000
    checkRegister(2, 0xFFFFFFFFF8000000, dut, False)
    # SRAIW on 0x80000000 >> 1 = 0xC0000000, sign extended to 0xFFFFFFFFC0000000
    checkRegister(4, 0xFFFFFFFFC0000000, dut, False)
    # SRAIW on 0x7FFFFFFF (most positive 32-bit) >> 4 = 0x07FFFFFF, sign extended to 0x0000000007FFFFFF
    checkRegister(6, 0x0000000007FFFFFF, dut, False)
    # SRAIW on 0xFFFFFFFF (-1 in 32-bit) >> 8 = 0xFFFFFFFF, sign extended to 0xFFFFFFFFFFFFFFFF
    checkRegister(8, 0xFFFFFFFFFFFFFFFF, dut, False)

@cocotb.test()
async def test_neg_one(dut):
    asm = """
        addi x13,x0,-1
        ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await RisingEdge(dut.program_complete)

    checkRegister(13, -1, dut, True)

@cocotb.test()
async def test_auipc_addi_jalr_hazard(dut):
    # Back-to-back AUIPC/ADDI → JALR on x31.
    # Should set x13=1 if bypass/stall logic works correctly.
    asm = """
    li   x13, 99
LBL:
    auipc x31, %pcrel_hi(TGT)
    addi  x31, x31, %pcrel_lo(LBL)
    jalr  x0,  x31, 0
    li   x13, 2      # must be skipped
TGT:
    li   x13, 1
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(50, unit="ns"))
    checkRegister(13, 1, dut, True)
    checkFinished(dut)


@cocotb.test()
async def test_auipc_addi_jalr_with_nop(dut):
    # Same sequence, but with a NOP between ADDI and JALR.
    # Should pass even without forwarding.
    asm = """
    li   x13, 99
LBL:
    auipc x31, %pcrel_hi(TGT)
    addi  x31, x31, %pcrel_lo(LBL)
    addi  x0, x0, 0  # NOP
    jalr  x0, x31, 0
    li   x13, 2      # must be skipped
TGT:
    li   x13, 1
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(50, unit="ns"))
    checkRegister(13, 1, dut, True)
    checkFinished(dut)



@cocotb.test()
async def test_wrong_entry(dut):
    asm = """
                              nop
                              nop
                              nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop

                                                        LBL_21_13:
                                                        auipc x31, %pcrel_hi(TARG_21_13)
                                                        addi  x31, x31, %pcrel_lo(LBL_21_13)
                                                        jalr  x0, x31, 0
                                                        li x13, 2
                                                        TARG_21_13:
                                                        li x13, 1
                                                        and x30, x22, x21

                                                                ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await RisingEdge(dut.program_complete)

    checkRegister(13, 1, dut, True)

@cocotb.test()
async def test_auipc_label_pair_stress(dut):
    # Two AUIPC/ADDI→JALR blocks using the label-pairing form, separated by filler ops.
    # Each block should land on its TGT_* label and set x13=1 (skipping the '2').
    asm = """
    li   x13, 99
LBL_A:
    auipc x31, %pcrel_hi(TGT_A)
    addi  x31, x31, %pcrel_lo(LBL_A)
    jalr  x0,  x31, 0
    li   x13, 2          # must be skipped
TGT_A:
    li   x13, 1

    # filler / unrelated ops (to mimic fuzz context)
    li   x22, 0x8000000000000000
    li   x30, 0x0000000000000001
    and  x30, x22, x30   # -> 0

    # repeat the pattern with fresh labels to catch intermittent issues
    li   x13, 99
LBL_B:
    auipc x31, %pcrel_hi(TGT_B)
    addi  x31, x31, %pcrel_lo(LBL_B)
    jalr  x0,  x31, 0
    li   x13, 2          # must be skipped
TGT_B:
    li   x13, 1
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(50, unit="ns"))
    checkRegister(13, 1, dut, True)   # final write should be 1
    checkRegister(30, 0, dut, False)  # sanity from filler ops
    checkFinished(dut)

@cocotb.test()
async def test_slli_imm_32(dut):
    asm = """
    li   x5, 1
    slli x5, x5, 32     # requires 6-bit shamt on RV64; wrong decode -> shifts by 0
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(50, unit="ns"))
    # Expect 0x0000000100000000
    checkRegister(5, 0x0000000100000000, dut, False)
    checkFinished(dut)

@cocotb.test()
async def test_li_64bit_constant_build(dut):
    asm = """
                                       # --- randomized non-memory fuzz 37 ---
                                                                li x28, 0x66af0807d37d2cbb
                                                        li x25, 0x0000000000000002
                                                        li x13, 0x0000000000000000
                                                        li x2, -2
                                                        li x12, 0x0000000000000001
                                                        li x14, 0x0000000000000001
                                                        li x23, 0x0000000000000001
                                                        li x15, 0x0000000000000003
                                                        add x2, x14, x26
                                                        add x27, x3, x1
                                                        andi x21, x25, -612
                                                        srai x10, x22, 42
                                                        li x27, 99
                                                        LBL_37_3:
                                                        auipc x31, %pcrel_hi(TARG_37_3)
                                                        addi  x31, x31, %pcrel_lo(LBL_37_3)
                                                        jalr  x0, x31, 0
                                                        li x27, 2
                                                        TARG_37_3:
                                                        li x27, 1
                                                        srai x25, x2, 26
                                                        sub x16, x30, x20
                                                        sub x30, x15, x19
                                                        andi x25, x2, -586
                                                        andi x13, x26, -1598
                                                        sltiu x29, x10, -61
                                                        slti x17, x22, 587
                                                        srli x12, x23, 9
                                                        li x24, 99
                                                        li x27, 0x0000000000000004
                                                        bgeu x29, x27, L_PASS_37_11
                                                        li x24, 2
                                                        jal x0, L_DONE_37_11
                                                        L_PASS_37_11:
                                                        li x24, 1
                                                        L_DONE_37_11:
                                                        srai x13, x28, 22
                                                        add x10, x19, x2
                                                        slti x7, x6, -476
                                                        add x13, x4, x18
                                                        sll x25, x19, x3
                                                        slli x26, x11, 21
                                                        ori x29, x3, 1885
                                                        srli x3, x12, 53
                                                        li x14, 99
                                                        li x15, 0x0000000000000004
                                                        bne x27, x15, L_PASS_37_19
                                                        li x14, 2
                                                        jal x0, L_DONE_37_19
                                                        L_PASS_37_19:
                                                        li x14, 1
                                                        L_DONE_37_19:
                                                                ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(500, unit="ns"))
    checkRegister(28, 0x66af0807d37d2cbb, dut, False)
    checkFinished(dut)


@cocotb.test()
async def test_load(dut):
    asm = """
    ld   x1, 1024(x0)
    lw   x2, 1024(x0)
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)

    # Put a 64-bit value at byte address 1024.
    # 0x0000...0FF1 ensures both LD and LW read the same low value.
    await awrite_u64(dut, 1024, 0x0000000000000FF1)

    cocotb.start_soon(Clock(dut.clk, 1, units="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(50, units="ns"))

    checkRegister(1, 0x0000000000000FF1, dut, False)  # x1 from ld
    checkRegister(2, 0x0000000000000FF1, dut, False)  # x2 from lw (zero-extended)
    checkFinished(dut)

@cocotb.test()
async def test_use_after_load(dut):
    asm = """
    ld   x1, 1024(x0)
    addi x1, x1, 50
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    await awrite_u64(dut, 1024, 0x0000000000000FF1)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(50, unit="ns"))
    checkRegister(1, 0xFF1 + 50, dut, False)
    checkFinished(dut)

@cocotb.test()
async def test_multi_load(dut):
    asm = """
     li   x31, 1024

        # ---- from offset 0 ----
        lb   x1,  0(x31)
        lbu  x2,  0(x31)

    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    await awrite_u64(dut, 1024, 0x0000000000000FF1)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(50, unit="ns"))
    checkRegister(1, 0xFFFFFFFFFFFFFFF1, dut, False)
    checkRegister(2, 0xF1, dut, False)
    checkFinished(dut)


@cocotb.test()
async def test_load_variants_rv64i(dut):
    """
    Test RV64I load variants: lb, lbu, lh, lhu, lw, lwu, ld
    Using little-endian memory layout.

    Memory pattern at BASE (bytes 0..7):
      [0]=0xEF, [1]=0xBE, [2]=0xAD, [3]=0xDE, [4]=0xFE, [5]=0xCA, [6]=0xBA, [7]=0xBE
    Interpreted as 64-bit little-endian: 0xBEBA_CAFE_DEAD_BEEF
    """

    BASE = 1024  # any 8-byte aligned address is fine

    asm = f"""
        li   x31, {BASE}

        # ---- from offset 0 ----
        lb   x1,  0(x31)
        lbu  x2,  0(x31)
        lh   x3,  0(x31)
        lhu  x4,  0(x31)
        lw   x5,  0(x31)
        lwu  x6,  0(x31)
        ld   x7,  0(x31)

        # ---- from offset 4 ----
        lb   x8,  4(x31)
        lbu  x9,  4(x31)
        lh   x10, 4(x31)
        lhu  x11, 4(x31)
        lw   x12, 4(x31)
        lwu  x13, 4(x31)

        ecall
    """

    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)

    # Little-endian pattern: 0xBEBA_CAFE_DEAD_BEEF laid out from BASE upward
    bytes_at_base = [0xEF, 0xBE, 0xAD, 0xDE, 0xFE, 0xCA, 0xBA, 0xBE]
    for i, b in enumerate(bytes_at_base):
        await awrite_u8(dut, BASE+i, b)

    # Start clock & run
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(2000, unit="ns"))

    # ---- Expected values (RV64I) ----
    # From offset 0:
    #   byte   = 0xEF                -> lb  => sign-extend -> 0xFFFFFFFFFFFFFFEF
    #   byte   = 0xEF                -> lbu => zero-extend -> 0x00000000000000EF
    #   hword  = 0xBEEF              -> lh  => sign-extend -> 0xFFFFFFFFFFFFBEEF
    #   hword  = 0xBEEF              -> lhu => zero-extend -> 0x000000000000BEEF
    #   word   = 0xDEADBEEF          -> lw  => sign-extend -> 0xFFFFFFFFDEADBEEF
    #   word   = 0xDEADBEEF          -> lwu => zero-extend -> 0x00000000DEADBEEF
    #   dword  = 0xBEBACAFEDEADBEEF  -> ld  =>            -> 0xBEBACAFEDEADBEEF

    checkRegister(1,  0xFFFFFFFFFFFFFFEF, dut, False)  # lb
    checkRegister(2,  0x00000000000000EF, dut, False)  # lbu
    checkRegister(3,  0xFFFFFFFFFFFFBEEF, dut, False)  # lh
    checkRegister(4,  0x000000000000BEEF, dut, False)  # lhu
    checkRegister(5,  0xFFFFFFFFDEADBEEF, dut, False)  # lw
    checkRegister(6,  0x00000000DEADBEEF, dut, False)  # lwu
    checkRegister(7,  0xBEBACAFEDEADBEEF, dut, False)  # ld

    # From offset 4:
    #   byte   = 0xFE                -> lb  => sign-extend -> 0xFFFFFFFFFFFFFFFE
    #   byte   = 0xFE                -> lbu => zero-extend -> 0x00000000000000FE
    #   hword  = 0xCAFE              -> lh  => sign-extend -> 0xFFFFFFFFFFFFCAFE
    #   hword  = 0xCAFE              -> lhu => zero-extend -> 0x000000000000CAFE
    #   word   = 0xBEBACAFE          -> lw  => sign-extend -> 0xFFFFFFFFBEBACAFE
    #   word   = 0xBEBACAFE          -> lwu => zero-extend -> 0x00000000BEBACAFE

    checkRegister(8,  0xFFFFFFFFFFFFFFFE, dut, False)  # lb @ +4
    checkRegister(9,  0x00000000000000FE, dut, False)  # lbu @ +4
    checkRegister(10, 0xFFFFFFFFFFFFCAFE, dut, False)  # lh @ +4
    checkRegister(11, 0x000000000000CAFE, dut, False)  # lhu @ +4
    checkRegister(12, 0xFFFFFFFFBEBACAFE, dut, False)  # lw @ +4
    checkRegister(13, 0x00000000BEBACAFE, dut, False)  # lwu @ +4

    checkFinished(dut)


@cocotb.test()
async def test_store(dut):
    asm = """
     li   x31, 1024
     li x2, 12345

        # ---- from offset 0 ----
        sd   x2,  0(x31)
        ld  x3,  0(x31)

    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(500, unit="ns"))
    checkRegister(3,  12345, dut, False)
    checkFinished(dut)

@cocotb.test()
async def test_store2(dut):
    asm = """
     li   x31, 1024
     li x2, 0xBEEF
  sh  x2, 2(x31)                 # store 0xBEEF at [BASE+2..3]
        lhu  x5, 2(x31)
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(50, unit="ns"))
    checkRegister(5,  0xBEEF, dut, False)
    checkFinished(dut)




# ============================================================
# 1) Edge-case sign/zero extension on LB/LBU, LH/LHU, LW/LWU (ALIGNED)
#    Words now at +8 and +12 (4-byte aligned), halfwords at +2 and +4.
# ============================================================
@cocotb.test()
async def test_edge_sign_zero_ext(dut):
    BASE = 0x600

    asm = f"""
        li   x31, {BASE}

        # LB/LBU: bytes at +0 and +1 (byte loads may be anywhere)
        lb   x1,  0(x31)
        lbu  x2,  0(x31)
        lb   x3,  1(x31)
        lbu  x4,  1(x31)

        # LH/LHU: halfwords at +2 and +4 (aligned)
        lh   x5,  2(x31)
        lhu  x6,  2(x31)
        lh   x7,  4(x31)
        lhu  x8,  4(x31)

        # LW/LWU: words at +8 and +12 (aligned)
        lw   x9,   8(x31)
        lwu  x10,  8(x31)
        lw   x11, 12(x31)
        lwu  x12, 12(x31)

        ecall
    """

    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)

    # Memory map (little-endian):
    # +0:  0x80  -> LB = -128, LBU = 0x80
    # +1:  0xFF  -> LB = -1,    LBU = 0xFF
    # +2..+3: 0x8000  (00 80)
    # +4..+5: 0xFFFF  (FF FF)
    # +8..+11:  0x80000000 (00 00 00 80)  <-- aligned
    # +12..+15: 0xFFFFFFFF (FF FF FF FF)  <-- aligned
    await awrite_u8(dut, BASE+0, 0x80) 
    await awrite_u8(dut, BASE+1, 0xFF) 
    await awrite_u8(dut, BASE+2, 0x00) 
    await awrite_u8(dut, BASE+3, 0x80) 
    await awrite_u8(dut, BASE+4, 0xFF) 
    await awrite_u8(dut, BASE+5, 0xFF) 
    # leave +6..+7 as don't-care bytes for this test
    await awrite_u8(dut, BASE+8, 0x00) 
    await awrite_u8(dut, BASE+9, 0x00) 
    await awrite_u8(dut, BASE+10, 0x00) 
    await awrite_u8(dut, BASE+11, 0x80) 
    await awrite_u8(dut, BASE+12, 0xFF) 
    await awrite_u8(dut, BASE+13, 0xFF) 
    await awrite_u8(dut, BASE+14, 0xFF) 
    await awrite_u8(dut, BASE+15, 0xFF) 

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(200, unit="ns"))

    # Byte 0x80
    checkRegister(1,  0xFFFFFFFFFFFFFF80, dut, False)  # lb
    checkRegister(2,  0x0000000000000080, dut, False)  # lbu
    # Byte 0xFF
    checkRegister(3,  0xFFFFFFFFFFFFFFFF, dut, False)  # lb
    checkRegister(4,  0x00000000000000FF, dut, False)  # lbu
    # Halfword 0x8000
    checkRegister(5,  0xFFFFFFFFFFFF8000, dut, False)  # lh
    checkRegister(6,  0x0000000000008000, dut, False)  # lhu
    # Halfword 0xFFFF
    checkRegister(7,  0xFFFFFFFFFFFFFFFF, dut, False)  # lh
    checkRegister(8,  0x000000000000FFFF, dut, False)  # lhu
    # Word 0x80000000
    checkRegister(9,  0xFFFFFFFF80000000, dut, False)  # lw (sign-extend)
    checkRegister(10, 0x0000000080000000, dut, False)  # lwu
    # Word 0xFFFFFFFF
    checkRegister(11, 0xFFFFFFFFFFFFFFFF, dut, False)  # lw
    checkRegister(12, 0x00000000FFFFFFFF, dut, False)  # lwu

    checkFinished(dut)

# ============================================================
# 2) REPLACEMENT for the old unaligned test:
#    Aligned mixed loads over a 16B pattern (all accesses naturally aligned)
# ============================================================
@cocotb.test()
async def test_aligned_mixed_loads(dut):
    """
    Place a 16-byte pattern and perform only NATURALLY ALIGNED loads.
    """
    BASE = 0x700

    asm = f"""
        li x31, {BASE}

        # Pattern: 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F

        # Halfwords (aligned): +2, +14
        lh   x1,  2(x31)
        lhu  x2, 14(x31)

        # Words (aligned): +4, +12
        lw   x3,  4(x31)
        lwu  x4, 12(x31)

        # Doubleword (aligned): +8
        ld   x5,  8(x31)

        ecall
    """

    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)

    for i in range(16):
        await awrite_u8(dut, BASE + i ,i)

    # Expected (little-endian):
    # lh @+2  -> 0x0302
    # lhu@+14 -> 0x0F0E
    # lw @+4  -> 0x07060504  (sign-extend; MSB=0x07 => positive)
    # lwu@+12 -> 0x0F0E0D0C
    # ld @+8  -> 0x0F0E0D0C0B0A0908
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(200, unit="ns"))

    checkRegister(1,  0x0000000000000302,     dut, False)  # lh
    checkRegister(2,  0x0000000000000F0E,     dut, False)  # lhu
    checkRegister(3,  0x0000000007060504,     dut, False)  # lw (sign-ext stays positive)
    checkRegister(4,  0x000000000F0E0D0C,     dut, False)  # lwu
    checkRegister(5,  0x0F0E0D0C0B0A0908,     dut, False)  # ld

    checkFinished(dut)


# ============================================================
# 3) Store→Load hazards (same addr, different widths/offsets)
# ============================================================
@cocotb.test()
async def test_store_then_load_width_mix(dut):
    """
    Store different widths then load them back (same cycle domain),
    ensuring forwarding or correct memory ordering works.
    """
    BASE = 0x800

    asm = f"""
        li x31, {BASE}
        li x2,  0x00000000DEADBEEF     # 32-bit interesting pattern in low bits

        # Store a byte, then load byte/half/word/dword overlapping it
        sb  x2, 0(x31)                 # store 0xEF at [BASE+0]
        lb  x3, 0(x31)
        lbu x4, 0(x31)

        # Store halfword at +2, then read back half/word
        sh  x2, 2(x31)                 # store 0xBEEF at [BASE+2..3]
        lh  x5, 2(x31)
        lhu x6, 2(x31)
        lw  x7,  0(x31)                # should now see 0xBEEF_EF?? (depends on +1 old)

        # Overwrite entire word; read lwu and lw
        sw  x2, 0(x31)                 # [BASE+0..3] = EF BE AD DE
        lwu x8,  0(x31)
        lw  x9,  0(x31)

        # 64-bit store then 64-bit load (data path end-to-end)
        sd  x2, 8(x31)                 # [BASE+8..15]
        ld  x10, 8(x31)

        ecall
    """

    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)

    # Initialize surrounding bytes (so mixed-width overlaps are deterministic)
    for i in range(0, 32):
        await awrite_u8(dut, BASE + i, 0x11)  # filler

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(200, unit="ns"))

    # After sb x2,0: byte at +0 = 0xEF
    checkRegister(3, 0xFFFFFFFFFFFFFFEF, dut, False)  # lb
    checkRegister(4, 0x00000000000000EF, dut, False)  # lbu

    # After sh x2,2: halfword at +2..+3 = 0xBEEF
    checkRegister(5, 0xFFFFFFFFFFFFBEEF, dut, False)  # lh
    checkRegister(6, 0x000000000000BEEF, dut, False)  # lhu

    # sw x2,0: word 0xDEADBEEF at +0..+3
    checkRegister(8, 0x00000000DEADBEEF, dut, False)  # lwu
    checkRegister(9, 0xFFFFFFFFDEADBEEF, dut, False)  # lw

    # sd x2,8 then ld x10,8
    # x2 = 0x00000000DEADBEEF -> sign-extend in register is still same 64-bit value
    checkRegister(10, 0x00000000DEADBEEF, dut, False)

    checkFinished(dut)


# ============================================================
# 4) Load→Store hazards (dependent address/values)
# ============================================================
@cocotb.test()
async def test_load_then_store_dep_single_program(dut):
    """
    Load a value -> store it elsewhere -> read it back (same program, no reset).
    Also: use a loaded halfword as an address to store a byte, then read that byte back.
    All accesses naturally aligned (LD/LH aligned; SB can be anywhere).
    """
    BASE = 0x900

    asm = f"""
        li  x31, {BASE}

        # memory[BASE+0..7] prefilled by TB = 0x1122334455667788 (little-endian)
        ld  x1,  0(x31)              # x1 = 0x1122334455667788   (aligned)
        sd  x1,  8(x31)              # copy to BASE+8            (aligned)
        ld  x4,  8(x31)              # read-back copy into x4

        # Use a loaded halfword (aligned) to compute an address; store LSB(x1) there, then read it back
        lh  x2,  2(x31)              # x2 = 0x3344 (sign-extended), aligned halfword
        add x3,  x31, x2             # x3 = BASE + 0x3344
        sb  x1,  0(x3)               # store 0x88 (LSB of x1) at computed address (byte can be unaligned)
        lbu x5,  0(x3)               # read back the byte we just stored

        ecall
    """

    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)

    # Place 0x1122334455667788 at BASE (little-endian)
    patt = [0x88,0x77,0x66,0x55,0x44,0x33,0x22,0x11]
    for i,b in enumerate(patt):
        await awrite_u8(dut, BASE + i, b)

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(200, unit="ns"))

    # Verify:
    # x1 = original LD
    # x4 = value reloaded from the SD @ BASE+8
    # x5 = LSB(x1) written via SB to computed address and read back via LBU
    checkRegister(1, 0x1122334455667788, dut, False)
    checkRegister(4, 0x1122334455667788, dut, False)
    checkRegister(5, 0x0000000000000088, dut, False)

    checkFinished(dut)


# ============================================================
# 5) Branch flush: taken branch must cancel following store
# ============================================================
@cocotb.test()
async def test_branch_flush_cancels_store(dut):
    """
    A taken branch should invalidate the following store in the wrong path.
    Sequence:
      addi x5,1; beq x5,x5, target  (branch always taken)
      sd x6, 0(x31)   <-- MUST be flushed (must NOT execute)
    target:
      ld x7, 0(x31)   <-- should read original memory, not x6
    """
    BASE = 0xA00

    asm = f"""
        li x31, {BASE}
        li x6,  0xCAFEBABECAFED00D  # store candidate (wrong-path op)
        # Put known old value in memory; we won't rely on Python to prefill via external load
        # but for verification we do initialize from testbench too.
        # Wrong-path store:
        addi x5, x0, 1
        beq  x5, x5, 1f           # always taken
        sd   x6, 0(x31)           # SHOULD BE FLUSHED
        nop
1:
        ld   x7, 0(x31)           # should see original content
        ecall
    """

    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)

    # Original memory value to preserve if flush works:
    orig = [0xEF,0xBE,0xAD,0xDE,0xFE,0xCA,0xBA,0xBE]  # 0xBEBACAFEDEADBEEF
    for i,b in enumerate(orig):
        await awrite_u8(dut, BASE + i, b)

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(200, unit="ns"))

    checkRegister(7, 0xBEBACAFEDEADBEEF, dut, False)  # unchanged after flushed store
    checkFinished(dut)


# ============================================================
# 6) Branch not taken: store must commit
# ============================================================
@cocotb.test()
async def test_branch_not_taken_store_commits(dut):
    """
    Ensure not-taken branch does NOT flush the store.
    """
    BASE = 0xA40

    asm = f"""
        li x31, {BASE}
        li x6,  0x0123456789ABCDEF
        addi x5, x0, 0
        beq  x5, x6, 1f       # not taken
        sd   x6, 0(x31)       # must commit
1:
        ld   x7, 0(x31)
        ecall
    """

    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)

    # Initialize to something else
    for i,b in enumerate([0x00]*8):
        await awrite_u8(dut, BASE + i, b)

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(200, unit="ns"))

    checkRegister(7, 0x0123456789ABCDEF, dut, False)
    checkFinished(dut)


# ============================================================
# 7) Branch depends on just-loaded value (stall + correct flush)
# ============================================================
@cocotb.test()
async def test_branch_depends_on_load(dut):
    """
    Load sets branch condition; branch should be resolved correctly even if
    the load introduces a stall. Ensure wrong-path store is flushed.
    """
    BASE = 0xA80

    asm = f"""
        li  x31, {BASE}

        # Load a byte that determines the branch
        lbu x1, 0(x31)          # x1 = 0x01 -> branch taken
        beq x1, x0, 1f          # NOT equal to zero -> not taken, so fall-through
        # Fall-through path (branch not taken): commit store
        li  x2, 0xAABBCCDDEEFF0011
        sd  x2, 8(x31)
        j   2f

1:      # Taken path (if x1==0): would write a different value
        li  x3, 0x1122334455667788
        sd  x3, 8(x31)

2:      ld  x4, 8(x31)
        ecall
    """

    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)

    # Set selector byte so that branch is NOT taken (x1 != 0)
    await awrite_u8(dut, BASE + 0, 0x01)

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(300, unit="ns"))

    # We expect the fall-through store (x2) to commit
    checkRegister(4, 0xAABBCCDDEEFF0011, dut, False)
    checkFinished(dut)


# ============================================================
# 8) Load-after-store to same addr with branch misdirection in-between
# ============================================================
@cocotb.test()
async def test_load_after_store_with_branch_misdir(dut):
    """
    Store to memory, then a branch that is TAKEN should not disturb the
    already-committed store; load afterward must see the stored value.
    Also ensures that any wrong-path memory ops after the taken branch
    don't corrupt the committed state.
    """
    BASE = 0xAC0

    asm = f"""
        li x31, {BASE}
        li x2,  0xFEEDFACECAFED00D

        sd  x2, 0(x31)          # store first

        # force a taken branch to a block that tries to clobber memory
        addi x5, x0, 1
        beq  x5, x5, 1f         # taken
        sd  x0, 0(x31)          # wrong-path: SHOULD BE FLUSHED
        nop
1:
        ld  x6, 0(x31)          # must read original x2
        ecall
    """

    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)

    # Initialize to something else before the store
    for i,b in enumerate([0x00]*8):
        await awrite_u8(dut, BASE + i, b)

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(200, unit="ns"))

    checkRegister(6, 0xFEEDFACECAFED00D, dut, False)
    checkFinished(dut)


# ============================================================
# 9) Byte-enable + endianness on SW @ aligned offset (0xF68)
# ============================================================
@cocotb.test()
async def test_sw_lbu_endianness_and_strobes(dut):
    """
    Minimal repro of the fuzz failure:
    - Store word 0xDEADBEEF at BASE+0x68 (i.e., 0xF68 when BASE=0xF00)
    - Read back the four bytes individually with LBU
    Confirms little-endian ordering and that all 4 byte-enables asserted.
    """
    BASE = 0xF00
    OFFS = 0x68  # => absolute addr 0xF68

    asm = f"""
        li x31, {BASE}
        li x5,  0xDEADBEEF

        # SW should write bytes at F68..F6B as: EF, BE, AD, DE (little-endian)
        sw  x5, {OFFS}(x31)

        # Read back each byte independently
        lbu x10, {OFFS + 0}(x31)    # expect 0xEF (LSB)
        lbu x11, {OFFS + 1}(x31)    # expect 0xBE
        lbu x12, {OFFS + 2}(x31)    # expect 0xAD
        lbu x13, {OFFS + 3}(x31)    # expect 0xDE
        ecall
    """

    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)

    # Pre-fill the 4 target bytes with a known nonzero pattern to catch missing strobes.
    for i, b in enumerate([0x11, 0x22, 0x33, 0x44]):
        await awrite_u8(dut, BASE + OFFS + i, b)

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(200, unit="ns"))

    # Verify per-byte results
    checkRegister(10, 0xEF, dut, False)
    checkRegister(11, 0xBE, dut, False)
    checkRegister(12, 0xAD, dut, False)
    checkRegister(13, 0xDE, dut, False)
    checkFinished(dut)


# ============================================================
# 10) Same, with a not-taken branch before SW (matches fuzz flow)
# ============================================================
@cocotb.test()
async def test_sw_pre_branch_not_taken(dut):
    """
    Mirrors the fuzz control-flow nuance: a branch that is NOT taken precedes the SW.
    Ensures the store issues (i.e., no false squash) and the bytes land correctly.
    """
    BASE = 0xF00
    OFFS = 0x68

    asm = f"""
        li  x31, {BASE}
        li  x29, 0x11
        li  x30, 0x00          # x30 < x29 (unsigned), so bgeu is NOT taken

        bgeu x30, x29, 1f      # not taken -> fall through to the store
        li   x5,  0xDEADBEEF
        sw   x5,  {OFFS}(x31)
1:
        lbu x10, {OFFS + 0}(x31)
        lbu x11, {OFFS + 1}(x31)
        lbu x12, {OFFS + 2}(x31)
        lbu x13, {OFFS + 3}(x31)
        ecall
    """

    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)

    # Pre-fill bytes so a missing store shows up clearly.
    for i, b in enumerate([0xAA, 0xBB, 0xCC, 0xDD]):
        await awrite_u8(dut, BASE + OFFS + i, b)

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(200, unit="ns"))

    checkRegister(10, 0xEF, dut, False)
    checkRegister(11, 0xBE, dut, False)
    checkRegister(12, 0xAD, dut, False)
    checkRegister(13, 0xDE, dut, False)
    checkFinished(dut)


# ============================================================
# 11) SB lane sweep (sanity for byte-enables & endianness)
# ============================================================
@cocotb.test()
async def test_sb_lane_sweep(dut):
    """
    Writes 8 distinct bytes with SB across one 8-byte region and reads them back.
    Catches swapped lanes / wrong byte-enable wiring early.
    """
    BASE = 0x800  # 8-byte aligned, well within 4KB

    asm = f"""
        li x31, {BASE}
        li x1,  0x11
        li x2,  0x22
        li x3,  0x33
        li x4,  0x44
        li x5,  0x55
        li x6,  0x66
        li x7,  0x77
        li x8,  0x88

        sb x1, 0(x31)
        sb x2, 1(x31)
        sb x3, 2(x31)
        sb x4, 3(x31)
        sb x5, 4(x31)
        sb x6, 5(x31)
        sb x7, 6(x31)
        sb x8, 7(x31)

        lbu x10, 0(x31)
        lbu x11, 1(x31)
        lbu x12, 2(x31)
        lbu x13, 3(x31)
        lbu x14, 4(x31)
        lbu x15, 5(x31)
        lbu x16, 6(x31)
        lbu x17, 7(x31)
        ecall
    """

    await resetAndPrepare(dut)
    loadAsmToMemory(asm, dut)

    # Pre-fill target bytes with a pattern to detect missed writes
    for i, b in enumerate([0xA0,0xB0,0xC0,0xD0,0xE0,0xF0,0xAB,0xCD]):
        await awrite_u8(dut, BASE + i, b)

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(200, unit="ns"))

    for reg, val in zip([10,11,12,13,14,15,16,17],[0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88]):
        checkRegister(reg, val, dut, False)
    checkFinished(dut)


# ============================================================
# 12) SW offset sweep within a 64b beat (0..4)
# ============================================================
@cocotb.test()
async def test_sw_across_beat_offsets(dut):
    """
    Writes a 32-bit pattern at offsets 0..4 within an 8-byte-aligned region.
    Verifies the byte placement for each offset to catch byte-enable grouping bugs.
    """
    BASE = 0x8C0  # 8-byte aligned
    PAT  = 0xA1B2C3D4  # LSB first in memory: D4 C3 B2 A1

    await resetAndPrepare(dut)

    for offs in range(0, 5):  # 0..4 (SW spans 4 bytes)
        asm = f"""
            li x31, {BASE}
            li x5,  {PAT}
            sw x5, {offs}(x31)

            lbu x10, {offs+0}(x31)
            lbu x11, {offs+1}(x31)
            lbu x12, {offs+2}(x31)
            lbu x13, {offs+3}(x31)
            ecall
        """
        loadAsmToMemory(asm, dut)

        # Pre-fill the 8-byte beat so missing strobes show
        beat_base = (BASE // 8) * 8
        for i in range(8):
            await awrite_u8(dut, beat_base + i, 0x00)

        cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
        await First(RisingEdge(dut.program_complete), Timer(200, unit="ns"))

        # Expect D4 C3 B2 A1 at offs..offs+3
        checkRegister(10, 0xD4, dut, False)
        checkRegister(11, 0xC3, dut, False)
        checkRegister(12, 0xB2, dut, False)
        checkRegister(13, 0xA1, dut, False)
        checkFinished(dut)


# ============================================================
# 13) SD + byte readback (full 8B path and endianness)
# ============================================================
@cocotb.test()
async def test_sd_lbu_readback(dut):
    """
    Store 64-bit value, then read back each byte with LBU.
    Validates 8B write path and little-endian ordering.
    """
    BASE = 0x900
    VAL  = 0x0123456789ABCDEF  # LSB first in memory: EF CD AB 89 67 45 23 01

    asm = f"""
        li x31, {BASE}
        li x2,  {VAL}

        sd x2, 0(x31)

        lbu x10, 0(x31)
        lbu x11, 1(x31)
        lbu x12, 2(x31)
        lbu x13, 3(x31)
        lbu x14, 4(x31)
        lbu x15, 5(x31)
        lbu x16, 6(x31)
        lbu x17, 7(x31)
        ecall
    """

    await resetAndPrepare(dut)
    loadAsmToMemory(asm, dut)

    # Pre-fill 8 bytes to catch missing byte-enables on SD
    preset = [0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77]
    for i, b in enumerate(preset):
        await awrite_u8(dut, BASE + i, b)

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(200, unit="ns"))

    expected = [0xEF,0xCD,0xAB,0x89,0x67,0x45,0x23,0x01]
    for reg, val in zip(range(10,18), expected):
        checkRegister(reg, val, dut, False)
    checkFinished(dut)

# ============================================================
# 14) Dirty eviction write-back (conflict line via +0x800 tag flip)
# ============================================================
@cocotb.test()
async def test_dirty_eviction_writeback(dut):
    """
    Cache: OFFSET_BITS=7 (128B lines), INDEX_BITS=4 (16 lines), 4 KiB memory.
    Two addresses separated by 0x800 share the same INDEX but differ in TAG.
    We dirty line A, then touch conflicting line B to force eviction.
    On reload of A, we must see the dirty bytes (i.e., eviction wrote back).
    """
    BASE = 0x100              # index = 0x100 >> 7 = 2
    CONFLICT = BASE + 0x800   # flips TAG bit within 4KiB

    asm = f"""
        li x31, {BASE}
        # Dirty the line at BASE with distinct bytes
        li x5, 0xAA
        li x6, 0xBB
        li x7, 0xCC
        li x8, 0xDD
        sb x5, 0(x31)
        sb x6, 1(x31)
        sb x7, 2(x31)
        sb x8, 3(x31)

        # Access conflicting line to force eviction of BASE's line
        li x30, {CONFLICT}
        lbu x9, 0(x30)     # miss at CONFLICT -> evict BASE (dirty) -> write-back

        # Now read back from BASE; should see AA BB CC DD after refill from memory
        lbu x10, 0(x31)
        lbu x11, 1(x31)
        lbu x12, 2(x31)
        lbu x13, 3(x31)
        ecall
    """

    await resetAndPrepare(dut)
    loadAsmToMemory(asm, dut)

    # Pre-fill backing memory so we can detect if write-back happened:
    # Set old contents to something else; after eviction+refill, we expect the new dirty bytes.
    for i, b in enumerate([0x00, 0x11, 0x22, 0x33]):
        await awrite_u8(dut, BASE + i, b)
    # Also ensure CONFLICT line exists in memory (avoid OOB)
    await awrite_u8(dut, CONFLICT + 0, 0x5A)

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(400, unit="ns"))

    checkRegister(10, 0xAA, dut, False)
    checkRegister(11, 0xBB, dut, False)
    checkRegister(12, 0xCC, dut, False)
    checkRegister(13, 0xDD, dut, False)
    checkFinished(dut)


# ============================================================
# 15) Dirty eviction at end-of-line offsets (near 127)
# ============================================================
@cocotb.test()
async def test_dirty_eviction_near_eol(dut):
    """
    Dirty bytes near the end of a 128B cache line, then evict via conflicting TAG.
    Verifies write-back handles high offsets correctly.
    """
    BASE = 0x300             # pick another index
    CONFLICT = BASE + 0x800  # same index, different tag
    OFFS0 = 124
    OFFS1 = 127

    asm = f"""
        li x31, {BASE}
        li x5, 0xE1
        li x6, 0xE2
        sb x5, {OFFS0}(x31)
        sb x6, {OFFS1}(x31)

        # Evict by touching conflicting line
        li x30, {CONFLICT}
        lbu x7, 0(x30)

        # Read back tail bytes from BASE (must reflect dirty data after eviction/refill)
        lbu x10, {OFFS0}(x31)
        lbu x11, {OFFS1}(x31)
        ecall
    """

    await resetAndPrepare(dut)
    loadAsmToMemory(asm, dut)

    # Pre-fill backing memory with different values so we can detect correct write-back.
    await awrite_u8(dut, BASE + OFFS0, 0x55)
    await awrite_u8(dut, BASE + OFFS1, 0x66)
    await awrite_u8(dut, CONFLICT + 0, 0x99)

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(400, unit="ns"))

    checkRegister(10, 0xE1, dut, False)
    checkRegister(11, 0xE2, dut, False)
    checkFinished(dut)


# ============================================================
# 16) SW makes line dirty -> evict -> reload word intact
# ============================================================
@cocotb.test()
async def test_sw_dirty_eviction_then_reload(dut):
    BASE = 0x180
    CONFLICT = BASE + 0x800
    OFFS = 0x40

    asm = f"""
        li x31, {BASE}
        li x5,  0xDEADBEEF
        sw x5, {OFFS}(x31)
        li x30, {CONFLICT}
        lbu x6, 0(x30)           # force eviction
        lw  x10, {OFFS}(x31)     # LW sign-extends in RV64
        ecall
    """

    await resetAndPrepare(dut)
    loadAsmToMemory(asm, dut)
    for i, b in enumerate([0x01,0x23,0x45,0x67]):  # different preset
        await awrite_u8(dut, BASE + OFFS + i, b)
    await awrite_u8(dut, CONFLICT + 0, 0xAB)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(400, unit="ns"))

    checkRegister(10, 0xFFFFFFFFDEADBEEF, dut, False)  # sign-extended
    checkFinished(dut)



# ============================================================
# 17) Clean eviction (no prior writes) should NOT corrupt memory
# ============================================================
@cocotb.test()
async def test_clean_eviction_no_spurious_write(dut):
    """
    Touch line A with loads only (keeps it clean), evict it by loading conflict line B,
    then reload A and ensure contents still match the original backing memory preset.
    If a clean line gets written back, backing memory would be corrupted and this fails.
    """
    BASE = 0x280
    CONFLICT = BASE + 0x800  # same index (OFFSET_BITS=7, INDEX_BITS=4), different tag

    asm = f"""
        li x31, {BASE}

        # Clean fill: only reads from BASE
        lbu x5, 0(x31)
        lbu x6, 7(x31)

        # Evict with conflicting tag
        li x30, {CONFLICT}
        lbu x7, 0(x30)

        # Reload multiple bytes from BASE; must still match original backing
        lbu x10, 0(x31)
        lbu x11, 1(x31)
        lbu x12, 7(x31)
        lbu x13, 15(x31)
        ecall
    """

    await resetAndPrepare(dut)
    loadAsmToMemory(asm, dut)

    # IMPORTANT: prime backing memory AFTER reset + program load,
    # or your reset/program write will wipe/overwrite the preset.
    preset = [0x10,0x20,0x30,0x40,0x50,0x60,0x70,0x80,0x90,0xA0,0xB0,0xC0,0xD0,0xE0,0xF0,0x00]
    for i, b in enumerate(preset):
        await awrite_u8(dut, BASE + i, b)
    # Ensure conflict line exists in memory (not required for correctness, but explicit)
    await awrite_u8(dut, CONFLICT + 0, 0x77)

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(400, unit="ns"))

    # Expect original memory contents (no writeback should have occurred for a clean line)
    expect = {0:0x10, 1:0x20, 7:0x80, 15:0x00}
    checkRegister(10, expect[0],  dut, False)
    checkRegister(11, expect[1],  dut, False)
    checkRegister(12, expect[7],  dut, False)
    checkRegister(13, expect[15], dut, False)
    checkFinished(dut)


@cocotb.test()
async def test_load_store_negative_offset(dut):
    """
    Simple negative-offset load/store:
    Store a value at BASE+0, then load it back using a negative offset
    relative to BASE+8.
    """
    BASE = 0x300  # keep within 4KB

    asm = f"""
        li   x31, {BASE}
        li   x2,  0x123456789ABCDEF   # test value

        sd   x2, 0(x31)              # store at BASE+0
        ld   x3, 8(x31)              # load from BASE+8 (garbage)
        ld   x4, -8(x31)             # load from BASE-8 (should trap if <0)
        ld   x5, -8(x31)             # load using negative offset

        # Better variant: add 8 to base, then use -8 offset to get back value
        addi x6, x31, 8
        ld   x7, -8(x6)              # should load the original x2

        ecall
    """

    await resetAndPrepare(dut)
    loadAsmToMemory(asm, dut)

    # Initialize memory with known pattern at BASE
    patt = [0xEF,0xBE,0xAD,0xDE,0xFE,0xCA,0xBA,0xBE]  # 0xBEBACAFEDEADBEEF
    for i,b in enumerate(patt):
        await awrite_u8(dut, BASE + i, b)

    # Overwrite with test value (simulates sd)
    val = 0x0123456789ABCDEF
    for i in range(8):
        await awrite_u8(dut, BASE + i, (val >> (8*i)) & 0xFF)

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(200, unit="ns"))

    # Check the load via negative offset worked
    checkRegister(7, 0x0123456789ABCDEF, dut, False)

    checkFinished(dut)

@cocotb.test()
async def test_store_pos_load_neg(dut):
    """
    Store a value using a positive offset, then load it back from the same
    address using a negative offset. Effective addresses must match.
    """
    BASE = 0x200

    asm = f"""
        li   x31, {BASE}
        li   x2,  0x1122334455667788

        # Store at BASE+16
        sd   x2, 16(x31)

        # Form base+24, then use -8 offset to reach BASE+16 again
        addi x3, x31, 24
        ld   x4, -8(x3)

        ecall
    """

    await resetAndPrepare(dut)
    loadAsmToMemory(asm, dut)

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(100, unit="ns"))

    checkRegister(4, 0x1122334455667788, dut, False)
    checkFinished(dut)

@cocotb.test()
async def test_store_neg_load_pos(dut):
    """
    Store a value using a negative offset, then load it back with a positive
    offset that reaches the same effective address.
    """
    BASE = 0x240

    asm = f"""
        li   x31, {BASE}
        li   x2,  0xAABBCCDDEEFF0011

        # Form base+16
        addi x3, x31, 16

        # Store at (base+16 - 8) = BASE+8 using negative offset
        sd   x2, -8(x3)

        # Load at BASE+8 using a positive offset
        ld   x4, 8(x31)

        ecall
    """

    await resetAndPrepare(dut)
    loadAsmToMemory(asm, dut)

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(100, unit="ns"))

    checkRegister(4, 0xAABBCCDDEEFF0011, dut, False)
    checkFinished(dut)



@cocotb.test()
async def crazy_test(dut):
    asm = """
                                                                # --- randomized memory fuzz 12 ---
                                                                li x10, 0x7fffffffffffffff
                                                        li x12, 0x0000000000000002
                                                        li x7, 0x0000000000000003
                                                        li x16, 0x00000000ffffffff
                                                        li x25, 0xffffffff00000000
                                                        li x8, 0x0000000000000000
                                                        li x13, 0x0000000000000003
                                                        li x15, -2
                                                        li x23, 4056
                                                        li x30, 3816
                                                        li x27, 3912
                                                        sd x10, -464(x23)
                                                        sd x12, -8(x30)
                                                        sd x7, -448(x27)
                                                        slt x18, x6, x14
                                                        li x19, 0x0000000000000004
                                                        bltu x13, x19, L_SKIP_12_1
                                                        li x15, 0xCAFEBABE
                                                        sd x15, -56(x23)
                                                        ld x18, -56(x23)
                                                        li x3, 2
                                                        jal x0, L_DONE_12_1
                                                        L_SKIP_12_1:
                                                        li x11, 1
                                                        L_DONE_12_1:
                                                        srai x14, x29, 22
                                                        sd x13, -400(x27)
                                                        lw x3, -400(x27)
                                                        and x29, x3, x13
                                                        sh x12, 112(x27)
                                                        lhu x3, 112(x27)
                                                        sltu x13, x3, x16
                                                    
                                                                ecall
                                                                """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(1000, unit="ns"))
    # Final-state checks in calculation order
        # Set-by-immediates that never change afterward
       # Set by immediates and never changed later
    checkRegister(10, 0x7FFFFFFFFFFFFFFF, dut, False)  # x10
    checkRegister(12, 0x0000000000000002, dut, False)  # x12
    checkRegister(7,  0x0000000000000003, dut, False)  # x7
    checkRegister(16, 0x00000000FFFFFFFF, dut, False)  # x16
    checkRegister(25, 0xFFFFFFFF00000000, dut, False)  # x25
    checkRegister(8,  0x0000000000000000, dut, False)  # x8
    checkRegister(15, 0xFFFFFFFFFFFFFFFE, dut, False)  # x15 = -2
    checkRegister(23, 0x0000000000000FD8, dut, False)  # x23 = 4056
    checkRegister(30, 0x0000000000000EE8, dut, False)  # x30 = 3816
    checkRegister(27, 0x0000000000000F48, dut, False)  # x27 = 3912

    # First computed values
    checkRegister(18, 0x0000000000000000, dut, False)  # x18 = slt(x6=0, x14=0) -> 0
    checkRegister(19, 0x0000000000000004, dut, False)  # x19 = 4

    # Taken branch path (bltu x13=3, x19=4 => true)
    checkRegister(11, 0x0000000000000001, dut, False)  # x11 = 1

    # Post-branch computations
    checkRegister(14, 0x0000000000000000, dut, False)  # x14 = srai(x29=0, 22) -> 0
    checkRegister(29, 0x0000000000000003, dut, False)  # x29 = (lw x3=3) & x13(=3) -> 3
    checkRegister(3,  0x0000000000000002, dut, False)  # x3  = lhu 2

    # Final (must be last)
    checkRegister(13, 0x0000000000000001, dut, False)  # x13 = sltu(x3=2, x16=0xFFFF_FFFF) -> 1



    checkFinished(dut)




# ============================================================
# A) Patch the instruction two after the current one
#     - Overwrite "addi x6, x6, 2" with "addi x6, x6, 1"
#     - Issue fence.i and then execute the patched instruction
# ============================================================
@cocotb.test()
async def test_patch_two_after_current_with_fence(dut):
    """
    Overwrite an instruction two after the current one:
      - TARGET initially: addi x6, x6, 2
      - We store encoding for: addi x6, x6, 1
      - fence.i ensures I$ sees the update.
      - Then we execute through to TARGET and verify x6 increments by 1, not 2.
    """
    # Encodings (RV32I 32-bit words):
    # addi x6,x6,1  -> 0x00130313
    # addi x6,x6,2  -> 0x00230313
    asm = f"""
        .option norvc

        li   x6, 0

    cur:
        # Compute address of TARGET (two after current) and store new instruction word
        la    x5, TARGET
        li    x4, 0x00130313            # addi x6,x6,1
        sw    x4, 0(x5)
        fence.i

        addi  x6, x6, 4                 # current+1 (just a spacer)
        nop                              # current+2

    TARGET:
        addi  x6, x6, 2                 # will be overwritten to +1 by the SW above
        ecall
    """

    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())

    await First(RisingEdge(dut.program_complete), Timer(200, unit="ns"))

    # Expected: x6 = 4 (spacer add) + 1 (patched TARGET) = 5
    checkRegister(6, 5, dut, False)
    checkFinished(dut)


# ============================================================
# B) Write code at a different location, fence, and jump to it
#     - Patch a remote snippet to do (addi x18, x18, 7; ecall)
#     - fence.i, then jalr to it
# ============================================================
@cocotb.test()
async def test_write_elsewhere_fence_and_jump(dut):
    """
    Self-modify code at a remote label PATCH:
      - Write: addi x18, x18, 7 ; ecall
      - Issue fence.i
      - jalr to PATCH and terminate there
    Validates patch-at-distance + fence.i + control transfer.
    """
    # Encodings:
    # addi x18,x18,7 -> 0x00790913
    # ecall          -> 0x00000073
    asm = f"""
        .option norvc

        li   x18, 0

        # Get address of PATCH and write two instructions there
        la    x5, PATCH
        li    x4, 0x00790913            # addi x18,x18,7
        sw    x4, 0(x5)
        li    x4, 0x00000073            # ecall
        sw    x4, 4(x5)
        fence.i

        # Jump to the freshly-patched code
        jalr  x0, x5, 0

        # (Should never reach here; program ends at PATCH via ecall)
        nop

    . = 1024
    PATCH:
        # Initially NOPs; will be overwritten above.
        .word 0x00000013                # addi x0, x0, 0 (nop)
        .word 0x00000013                # addi x0, x0, 0 (nop)
    """

    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())

    await First(RisingEdge(dut.program_complete), Timer(200, unit="ns"))

    # Expected: x18 = 7 from the patched code
    checkRegister(18, 7, dut, False)
    checkFinished(dut)


# ============================================================
# C) Write BEFORE current, fence, and jump back safely
#     - Patch an earlier instruction to "addi x5,x5,3"
#     - Ensure we don't loop forever by having the next static
#       instruction jump forward to POST.
# ============================================================
@cocotb.test()
async def test_write_before_current_fence_and_jump_back(dut):
    """
    Patch an earlier instruction and jump back to it:
      - PREV initially contains a jump forward (to avoid loop by default)
      - We overwrite PREV with addi x5,x5,3
      - fence.i
      - jalr back to PREV
      - The instruction AFTER PREV is an unconditional jump to POST, ensuring forward progress.
    """
    # Encoding: addi x5,x5,3 -> 0x00328293
    asm = f"""
           .option norvc

ENTRY:
    jal   x0, CUR                   # start by jumping to CUR (do the patch first)

PREV:
    jal   x0, AFTER_PREV            # placeholder; will be overwritten by CUR

AFTER_PREV:
    jal   x0, POST                  # ensures forward progress after the patched PREV

CUR:
    li    x5, 0
    # Compute address of PREV and patch it with "addi x5,x5,3" (0x00328293)
    la    x6, PREV
    li    x7, 0x00328293
    sw    x7, 0(x6)
    fence.i
    jalr  x0, x6, 0                 # jump back to the now-patched instruction at PREV

POST:
    ecall

    """

    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())

    await First(RisingEdge(dut.program_complete), Timer(200, unit="ns"))

    # Expected: PREV now does addi x5,x5,3, then falls through to AFTER_PREV which jumps to POST -> ecall
    checkRegister(5, 3, dut, False)
    checkFinished(dut)

@cocotb.test()
async def test_fence(dut):
    # Load add into memory
    asm = """
    add   x3, x1, x2
    fence.i
    add   x3, x1, x2
    ecall
    """
    loadAsmToMemory(asm, dut)
    await resetAndPrepare(dut)
    loadRegisters([0, 1535, 8462, 5473, 9], dut)
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    await First(RisingEdge(dut.program_complete), Timer(100, unit="ns"))
    checkRegister(3, 1535 + 8462, dut)
    checkFinished(dut)