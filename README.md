# Classic 5-stage pipelined RISCV CPU project
Personal project to push knowledge of computer architecture and learn SystemVerilog. Supports RV64I w/ Zifencei to allow for JIT. Tested in both simulator & on FPGA.

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
 
All CPU design code is in the `rtl/` folder.

## Testing
I have tested it with the Verilator simulator on a series of Cocotb testbenches, including both targetting and randomized stimuli. Verilator tests are in the `tests/` folder.

After extensive refactoring to meet timing and LUT count, I have gotten it to run on my Xilinx Spartan 7 FPGA @ 100 Mhz and successfully communicated over uart. TCL scripts & timing reports are in the `vivado/` folder.

## Firmware
C code (`main.c`) is aligned in memory (`linker_script.ld`), compiled against the RV64I target (`Makefile`) and finally, the resulting bin is split into hex memory chunks (`bin_seperator.rs`) to be loaded by the synthesizer. I wrote all of these myself. At present, the C code only sends back a simple UART response to demonstrate that it is working.
All firmware code is in the `firmware/` folder.

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
```
Note on AI: I did not use AI to write any of the RTL code. However, I found that ChatGPT is very good at writing tests and as such, I used it for three things:
a) writing tests based on a description (i.e. jump into a branch), modelled after ones I had already written,
b) helping to write the randomized fuzz tests and,
c) writing quick SystemVerilog tests to pinpoint discrepencies between Verilator and Vivado (as seen in the `top_lvl_tb.sv` file).
