#Synthesize. Uncomment final lines as needed to achieve needed timing

# synth.tcl
set PART xc7s25csga324     ;
set TOP  tp_lvl     ;# your desired top

# Make sure files are parsed as SystemVerilog and in correct order
read_verilog -sv ../rtl/memory/lib/axi_interface_if.sv
read_verilog -sv ../rtl/memory/lib/axil_interface_if.sv
read_verilog -sv ../rtl/memory/bram_over_axi.sv
read_verilog -sv ../rtl/memory/bulk_read_interface.sv
read_verilog -sv ../rtl/memory/bulk_read_to_axi_adapter.sv
read_verilog -sv ../rtl/memory/memory_with_bram_cache.sv
read_verilog -sv ../rtl/memory/memory_controller.sv
read_verilog -sv ../rtl/memory/bulk_read_multiplexer.sv
read_verilog -sv ../rtl/memory/ttbit_adapter.sv
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
#read_verilog -sv ../rtl/uart/uart_tb.sv

read_xdc constraints.xdc

# add_files -norecurse ../rtl/include/axi_interface_if_fwd.svh
set_property verilog_define {VIVADO=1} [current_fileset]
# set_property include_dirs [list rtl/include] [current_fileset]

# Synthesize
# CAN USE:  -flatten_hierarchy none
synth_design -top $TOP -part $PART -flatten_hierarchy none

# --- Find instances with very large logical pin counts ---
proc big_pin_report {{limit 20} {outfile "build/large_pin_instances.rpt"}} {
  file mkdir [file dirname $outfile]
  set rows {}
  # Look at all hierarchical cells (skip trivial leaf primitives to reduce noise)
  foreach c [get_cells -hierarchical] {
    # Count *logical* pins on that cell
    set n [llength [get_pins -quiet -of_objects $c]]
    if {$n > 0} {
      # Keep: count, full path, ref name
      set ref [get_property REF_NAME $c]
      lappend rows [list $n $c $ref]
    }
  }
  set rows [lsort -integer -decreasing -index 0 $rows]

  set fh [open $outfile w]
  puts $fh [format "%12s  %-60s  %s" "PinCount" "CellPath" "RefName"]
  puts $fh [string repeat "-" 100]
  set k 0
  foreach r $rows {
    puts $fh [format "%12d  %-60s  %s" [lindex $r 0] [lindex $r 1] [lindex $r 2]]
    incr k
    if {$k == $limit} { break }
  }
  close $fh

  if {$k > 0} {
    set worst [lindex $rows 0]
    set worst_cell [lindex $worst 1]
    puts "\nLargest pin-count instance: [lindex $worst 0] pins on $worst_cell ([lindex $worst 2])"
    # Tease a few pins so you can see the shape of the interface
    set some_pins [lrange [get_pins -of_objects $worst_cell] 0 49]
    puts "First ~50 pins on the worst offender:"
    foreach p $some_pins { puts "  $p" }

    # Dump properties for quick triage
    report_property [get_cells $worst_cell]
  } else {
    puts "No cells with pins found (unexpected)."
  }
}

big_pin_report 25 "build/large_pin_instances.rpt"


# Optional outputs
write_checkpoint -force build/synth.dcp
report_utilization     -file build/util.rpt
report_utilization -hierarchical -hierarchical_depth 3 -file build/util_hier.rpt
report_timing_summary  -file build/timing.rpt

# place_design
# route_design
# write_bitstream -force build/top.bit


# Place and route
#opt_design
#place_design -directive Explore
#phys_opt_design -directive Explore
#route_design  -directive Explore
#phys_opt_design -directive Explore
#place_design -directive Explore
#route_design  -directive AggressiveExplore
#phys_opt_design -directive AggressiveExplore
#route_design  -directive AggressiveExplore
#report_timing_summary  -file build/post_route_timing.rpt
# write_bitstream -force build/top.bit
# write_checkpoint -force build/heavy_optimization.dcp