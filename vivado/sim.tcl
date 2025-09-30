# sim.tcl — use your original file list for behavioral simulation

set PART xc7s25csga324
set TOP  tp_lvl
set TB_TOP tp_lvl_tb   ;# name of your testbench top module
set TB_FILE ../rtl/tp_lvl_tb.sv

# ---- Create a lightweight project on disk (required for launch_simulation) ----
create_project sim_proj build/sim_proj -part $PART -force
set src_fs [get_filesets sources_1]
set sim_fs [get_filesets sim_1]

# Treat as SystemVerilog and add your define
set_property verilog_define {VIVADO=1} $src_fs
set_property verilog_define {VIVADO=1} $sim_fs

# ---- Add RTL sources (your original order) ----
read_verilog -sv ../rtl/memory/lib/axi_interface_if.sv
read_verilog -sv ../rtl/memory/lib/axil_interface_if.sv
read_verilog -sv ../rtl/memory/bram_over_axi.sv
read_verilog -sv ../rtl/memory/bulk_read_interface.sv
read_verilog -sv ../rtl/memory/bulk_read_to_axi_adapter.sv
read_verilog -sv ../rtl/memory/memory_with_bram_cache.sv
read_verilog -sv ../rtl/memory/memory_controller.sv
read_verilog -sv ../rtl/memory/bulk_read_multiplexer.sv
read_verilog -sv ../rtl/uart/uart.sv
read_verilog -sv ../rtl/registers/registers.sv
read_verilog -sv ../rtl/registers/registers_types.sv
read_verilog -sv ../rtl/pipeline_stages/1_instruction_fetch/instruction_fetch.sv
read_verilog -sv ../rtl/pipeline_stages/2_instruction_decode/instruction_decode_types.sv
read_verilog -sv ../rtl/pipeline_stages/2_instruction_decode/instruction_decode.sv
read_verilog -sv ../rtl/pipeline_stages/3_execute/execute.sv
read_verilog -sv ../rtl/pipeline_stages/4_memoryrw/memoryrw.sv
read_verilog -sv ../rtl/pipeline_stages/5_writeback/writeback_stage.sv
read_verilog -sv ../rtl/tp_lvl.sv

# ---- Add testbench to sim set and set top ----
add_files -fileset $sim_fs $TB_FILE
set_property top $TB_TOP $sim_fs

# ---- Launch behavioral simulation in GUI ----
launch_simulation -simset $sim_fs -mode behavioral
