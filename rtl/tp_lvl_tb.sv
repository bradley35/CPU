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

  // UART parameters
  localparam CLOCK_FREQ_OVER_BAUD_RATE = 868;

  // Task to send one byte over UART
  task send_uart_byte(input [7:0] data);
    // Start bit (low)
    rx = 1'b0;
    repeat (CLOCK_FREQ_OVER_BAUD_RATE) @(posedge clk);

    // 8 data bits (LSB first)
    for (int i = 0; i < 8; i++) begin
      rx = data[i];
      repeat (CLOCK_FREQ_OVER_BAUD_RATE) @(posedge clk);
    end

    // Stop bit (high)
    rx = 1'b1;
    repeat (CLOCK_FREQ_OVER_BAUD_RATE) @(posedge clk);
  endtask

  // Stimulus
  initial begin
    // Hold RX high (idle)
    rx        = 1'b1;

    // Apply reset
    reset_pin = 1'b0;  // Vivado board has active-low reset
    repeat (5) @(posedge clk);  // hold reset for 5 cycles
    reset_pin = 1'b1;

    // Wait for a short delay after reset
    repeat (20) @(posedge clk);

    // Send "Hello"
    send_uart_byte("H");
    send_uart_byte("e");
    send_uart_byte("l");
    send_uart_byte("l");
    send_uart_byte("o");
    send_uart_byte("\n");

    // Let it run for some more time
    repeat (200000) @(posedge clk);

    $display("Simulation finished after 200 cycles.");
    $finish;
  end

endmodule
