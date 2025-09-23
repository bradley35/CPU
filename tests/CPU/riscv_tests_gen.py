import os
import subprocess
import tempfile
import textwrap
import re

AS = "riscv64-unknown-elf-as"
LD = "riscv64-unknown-elf-ld"
OBJCOPY = "riscv64-unknown-elf-objcopy"
OBJDUMP = "riscv64-unknown-elf-objdump"

RED   = "\033[31m"
BLUE  = "\033[34m"
GRAY  = "\033[90m"
RESET = "\033[0m"
SEP = GRAY + "|" + RESET  # light-gray vertical bar

# ---------- assembler helpers ----------
def assemble_rv32i_bytes(asm: str) -> bytes:
    """Assemble RV32I asm -> raw little-endian bytes (no visible temp files)."""
    src = textwrap.dedent(f""".text
{asm}
""").encode()

    with tempfile.TemporaryFile() as obj_fd, tempfile.TemporaryFile() as linked_fd, tempfile.TemporaryFile() as bin_fd:
        obj_no, linked_no, bin_no = obj_fd.fileno(), linked_fd.fileno(), bin_fd.fileno()
        obj_path, linked_path, bin_path = f"/dev/fd/{obj_no}", f"/dev/fd/{linked_no}", f"/dev/fd/{bin_no}"

        # as -> ELF object into obj_fd
        p_as = subprocess.run([AS, "-march=rv64i_zifencei", "-o", obj_path, "-"],
                              input=src, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              check=False, pass_fds=(obj_no,))
        if p_as.returncode != 0:
            raise RuntimeError(f"'as' failed:\n{p_as.stderr.decode(errors='ignore')}")
        os.lseek(obj_no, 0, os.SEEK_SET)

        # ld -> linked ELF into linked_fd
        p_ld = subprocess.run([LD, "-Ttext=0x0", "--entry=0x0", "-o", linked_path, obj_path],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              check=False, pass_fds=(obj_no, linked_no))
        if p_ld.returncode != 0:
            raise RuntimeError(f"'ld' failed:\n{p_ld.stderr.decode(errors='ignore')}")
        os.lseek(linked_no, 0, os.SEEK_SET)

        # objcopy -> raw binary into bin_fd
        p_oc = subprocess.run([OBJCOPY, "-O", "binary", linked_path, bin_path],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              check=False, pass_fds=(linked_no, bin_no))
        if p_oc.returncode != 0:
            raise RuntimeError(f"'objcopy' failed:\n{p_oc.stderr.decode(errors='ignore')}")
        os.lseek(bin_no, 0, os.SEEK_SET)
        raw = bin_fd.read()

    return raw

def disassemble_rv32i(asm: str):
    """
    Return a list of 'mnemonic operands' strings for the given asm snippet.
    Uses objdump with:
      --no-show-raw-insn   (hide raw bytes so parsing is easy)
      -M numeric           (use x0..x31, not ABI names)
      -M no-aliases        (avoid pseudoinstructions)
    """
    src = textwrap.dedent(f""".text
{asm}
""").encode()

    with tempfile.TemporaryFile() as obj_fd, tempfile.TemporaryFile() as linked_fd:
        obj_no, linked_no = obj_fd.fileno(), linked_fd.fileno()
        obj_path, linked_path = f"/dev/fd/{obj_no}", f"/dev/fd/{linked_no}"

        p_as = subprocess.run(
            [AS, "-march=rv64i_zifencei", "-o", obj_path, "-"],
            input=src, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            check=False, pass_fds=(obj_no,)
        )
        if p_as.returncode != 0:
            raise RuntimeError(f"'as' failed:\n{p_as.stderr.decode(errors='ignore')}")
        os.lseek(obj_no, 0, os.SEEK_SET)

        # ld -> linked ELF into linked_fd
        p_ld = subprocess.run([LD, "-Ttext=0x0", "--entry=0x0", "-o", linked_path, obj_path],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              check=False, pass_fds=(obj_no, linked_no))
        if p_ld.returncode != 0:
            raise RuntimeError(f"'ld' failed:\n{p_ld.stderr.decode(errors='ignore')}")
        os.lseek(linked_no, 0, os.SEEK_SET)

        # IMPORTANT: numeric regs + no-aliases for exact xN names
        p_od = subprocess.run(
            [OBJDUMP, "-d", "--no-show-raw-insn", "-M", "numeric,no-aliases", linked_path],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, check=False, pass_fds=(linked_no,)
        )
        if p_od.returncode != 0:
            raise RuntimeError(f"'objdump' failed:\n{p_od.stderr}")

    mnems = []
    line_re = re.compile(r"^\s*[0-9A-Fa-f]+:\s*(.+)$")
    for line in p_od.stdout.splitlines():
        m = line_re.match(line)
        if m:
            insn = m.group(1).strip()
            if insn:
                mnems.append(insn)
    return mnems


# ---------- bit grid printing ----------
def header_rows_32():
    tens, ones = [], []
    for i in range(31, -1, -1):
        tens.append(str(i // 10) if i >= 10 else " ")
        ones.append(str(i % 10))
    return "".join(tens), "".join(ones)

def with_separators(s: str) -> str:
    return SEP.join(s)

def grid_line():
    return GRAY + "".join("-|" for _ in range(31)) + "-" + RESET

def log_bit_grid(dut, raw: bytes, mnemonics=None):
    tens, ones = header_rows_32()
    dut._log.debug("  " + with_separators(tens))
    dut._log.debug("  " + with_separators(ones))
    dut._log.debug("  " + grid_line())
    for idx in range(0, len(raw), 4):
        w = raw[idx:idx+4]
        u32 = int.from_bytes(w, "little")
        bits = f"{u32:032b}"
        mnemonic = ""
        if mnemonics and idx//4 < len(mnemonics):
            mnemonic = f"  {BLUE}{mnemonics[idx//4]}{RESET}"
        dut._log.debug("  " + with_separators(bits) + f"   {RED}inst{idx//4}{RESET}{mnemonic}")
def print_bit_grid(raw: bytes, mnemonics=None):
    tens, ones = header_rows_32()
    print("  " + with_separators(tens))
    print("  " + with_separators(ones))
    print("  " + grid_line())
    for idx in range(0, len(raw), 4):
        w = raw[idx:idx+4]
        u32 = int.from_bytes(w, "little")
        bits = f"{u32:032b}"
        mnemonic = ""
        if mnemonics and idx//4 < len(mnemonics):
            mnemonic = f"  {BLUE}{mnemonics[idx//4]}{RESET}"
        print("  " + with_separators(bits) + f"   {RED}inst{idx//4}{RESET}{mnemonic}")
# --- demo ---
if __name__ == "__main__":
    asm = """
        addi x6, x0, 0
        addi x7, x0, 0
1:
        auipc x5, %pcrel_hi(target)
        addi  x5, x5, %pcrel_lo(1b)       # pair with AUIPC above
        addi  x6, x0, 1
        jalr  x0, x5, 0                   # jalr imm must be 0
        addi  x7, x7, 2                   # should be squashed on redirect
target:
        addi  x7, x7, 3
        ecall
    """
    raw = assemble_rv32i_bytes(asm)
    mnemonics = disassemble_rv32i(asm)
    print_bit_grid(raw, mnemonics)
