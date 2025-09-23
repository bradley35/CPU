# Classic 5-stage pipelined RISCV CPU project
Personal project to push knowledge of computer architecture and learn SystemVerilog. Supports RV64I w/ Zifencei to allow for JIT. I have tested it with the Verilator simulator on a series of Cocotb testbenches. Next I will work on checking timing and synthesis on an FPGA, but I have not gotten to that yet.

## CPU Structure
* 5 stage pipeline: Instruction Fetch -> Instruction Decode -> Execute -> Memory Read/Write -> Writeback
  - Everything is in-order, with no branch prediction
  - Stalls when neccesary: waiting on earlier read or load/store enters memory stage while it is not ready to accept a new request
* Seperate Instruction + Data Caches
  - Caches built so that they will be inferred as BRAM
  - Access to respective caches is over AXI4-Lite
* Flexible Memory backing  
  - Communication with main RAM is over AXI so that it can easily be swapped with vendor DRAM IP to synthesize for FPGA
  - Currently built to infer BRAM for main-memory

## File Structure
```markdown
project/
├── rtl/                    — All RTL code
│   ├── pipeline_stages/    - Individual Stage Logic
│   ├── memory/             — Cache + Memory Logic
│   ├── registers/          - Register Table + Types
│   └── tp_lvl.sv
└── tests/
    ├── memory/             — Tests targettomg the cache + BRAM memory store
    └── CPU/                - Tests targetting the CPU.
                              Includes targeted assembly tests as well as randomized tests.
    
