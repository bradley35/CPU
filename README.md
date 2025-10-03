# Classic 5-stage pipelined RISCV CPU project
Personal project to push knowledge of computer architecture and learn SystemVerilog. Supports RV64I w/ Zifencei to allow for JIT and self-modifying code. Successfully runs compiled C code. Tested in both simulator & on FPGA.

## CPU Structure
* 5 stage pipeline: Instruction Fetch -> Instruction Decode -> Execute -> Memory Read/Write -> Writeback
  - Everything is in-order, with no branch prediction
  - Stalls when necessary: waiting on earlier read or load/store enters memory stage while it is not ready to accept a new request
* Separate Instruction + Data Caches
  - Caches built so that they will be inferred as BRAM
  - Access to respective caches is over AXI4-Lite
* Flexible Memory backing  
  - Communication with main RAM is over AXI so that it can easily be swapped with vendor DRAM IP to synthesize for FPGA
  - Currently built to infer BRAM for main-memory
* Can communicate over UART via memory mapped io
 
Schematic (I need to redraw this manually to simplify, but I thought the image was cool nonetheless):
![my_schematic](https://github.com/user-attachments/assets/0cecf210-64c5-40ba-ab97-f537a6d20a61)
 
All CPU design code is in the `rtl/` folder

## Testing
I have tested it with the Verilator simulator on a series of Cocotb testbenches, including both targeting and randomized stimuli. Verilator tests are in the `tests/` folder.

## FPGA

After extensive refactoring (and logic redesigning) to meet timing and LUT count, I have gotten it to run on my Xilinx Spartan 7 FPGA @ 100 Mhz and successfully communicated over uart. TCL scripts & timing reports are in the `vivado/` folder. This was important to me, as it shows that the rtl code is synthesizeable.

#### Lut Usage:

The caches use a very large amount of LUTs because they read entire lines from BRAMs. Therefore, any mux on a line (currently set to 64 bytes) requires 512 single-bit LUTs. I worked hard to minimize any switching logic involving full-cache lines, but a small amount was unavoidable. Additionally, after retrieving a line, returning the correct entry from the line requires a series of MUXs to select from 512 bits down to 64 bits. The data cache is larger than the if cache, as the if cache has write disabled.

<img width="330" height="330" alt="Screenshot 2025-10-03 at 2 14 31 PM" src="https://github.com/user-attachments/assets/74e9810f-4274-47d4-bd70-2e091b0df20f" />

#### Critical Path:

The critical path is: `memory stage result (one input to a LOAD/STORE) -> Execute stage (add the immediate from the instruction to the forwarded address) -> Memory Controller (where to route the instruction) -> Check if appropriate memory device (i.e. UART or Cache) is ready to receive a request -> Assert stall -> Prevent instruction fetch/execute/decode registers from being updated`. On my FPGA, this takes almost exactly 10 ns (which meets the 100 Mhz clock of the device), and given my current design, there is little way to optimize it further. I have already replicated the input path to the execute stage (to reduce fanout) and provided a dedicated add path just to calculate memory addresses.


## Firmware
C code (`main.c`) is aligned in memory (`linker_script.ld`), compiled against the RV64I target (`Makefile`) and finally, the resulting bin is split into hex memory chunks (`bin_separator.rs`) to be loaded by the synthesizer. I wrote all of these myself. At present, the C code only sends back a simple UART response to demonstrate that it is working.
All firmware code is in the `firmware/` folder.

## File Structure
```markdown
project/
├── rtl/                    — All RTL code
│   ├── pipeline_stages/      - Individual Stage Logic
│   ├── memory/               — Cache + Memory Logic
│   ├── registers/            - Register Table + Types
│   └── tp_lvl.sv
├── tests/                  — Verilator Cocotb tests
│   ├── memory/               — Tests targeting the cache + BRAM memory store
│   └── CPU/                  - Tests targeting the CPU.
│                               Includes targeted assembly tests as well as randomized tests.
├── firmware/               — C code, linker script, and compilation tools
└── vivado/                 — TCL scripts, timing reports, and FPGA synthesis files
```
Note on AI: I did not use AI to write the RTL code. However, I found that ChatGPT is very good at writing tests and as such, I used it for:
a) writing tests based on a description (i.e. jump into a branch), modelled after ones I had already written,
b) helping to write the randomized fuzz tests and,
c) writing quick SystemVerilog tests to pinpoint discrepancies between Verilator and Vivado (as seen in the `top_lvl_tb.sv` file).
AI also helped with writing the TCL scripts (since learning TCL was not my goal).
