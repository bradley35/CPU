`timescale 1ns / 1ps

module tp_lvl_tb;

  // Testbench signals
  logic       clk;
  logic       reset_pin;
  logic       rx;
  logic       tx;
  logic [3:0] reg_10;

  // Instantiate DUT
  tp_lvl dut (
    .clk      (clk),
    .reset_pin(reset_pin),
    .rx       (rx),
    .tx       (tx),
    .reg_10   (reg_10)
  );

  // Clock generation: 10 ns period = 100 MHz
  initial clk = 0;
  always #5 clk = ~clk;

  // Stimulus
  initial begin
    // Hold RX high (idle)
    rx        = 1'b1;

    // Apply reset
    reset_pin = 1'b1;
    repeat (5) @(posedge clk);  // hold reset for 5 cycles
    reset_pin = 1'b0;

    // Let it run for 200 cycles
    repeat (200) @(posedge clk);

    $display("Simulation finished after 200 cycles.");
    $finish;
  end

endmodule
