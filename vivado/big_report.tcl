# --- Pass 1: RTL elaboration ---
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
read_verilog -sv ../rtl/tp_lvl.sv
set_property verilog_define {VIVADO=1} [current_fileset]

synth_design -top tp_lvl -part xc7s25csga324 -rtl
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
# Run your big-pin finder here too:
big_pin_report 25 "build/large_pin_instances_rtl.rpt"

close_design

# --- Pass 2: Real synthesis (your normal flow) ---
# (re-read the sources as you already do)
