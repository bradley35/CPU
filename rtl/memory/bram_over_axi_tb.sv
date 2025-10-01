// module bram_over_axi_tb;
//   logic clk;
//   logic rst;

//   axi_interface_if #(.DATA_W(64)) bus ();
//   bram_over_axi dut (
//     .clk,
//     .rst,
//     .read_slv (bus.rd_slv),
//     .write_slv(bus.wr_slv)
//   );

//   axi_interface_if #(.DATA_W(64)) bus2 ();
//   bram_over_axi cache_memory_backing (
//     .clk,
//     .rst,
//     .read_slv (bus2.rd_slv),
//     .write_slv(bus2.wr_slv)
//   );

//   axil_interface_if #(.DATA_W(64)) cache_bus ();
//   bulk_read_interface bulk_interface ();
//   bulk_read_to_axi_adapter adapter (
//     .axi_read_out (bus2.rd_mst),
//     .axi_write_out(bus2.wr_mst),
//     .bulk_read_in (bulk_interface.slave),
//     .clk,
//     .rst
//   );

//   memory_with_bram_cache cache (
//     .clk,
//     .rst,
//     .cache_wr_int     (cache_bus.wr_slv),
//     .cache_rd_int     (cache_bus.rd_slv),
//     .memory_access_out(bulk_interface.master),
//     .dump_cache       ()
//   );

//   // Clock and Reset Generation
//   initial begin
//     clk = 0;
//     forever #5 clk = ~clk;  // 100MHz clock
//   end

//   initial begin
//     rst = 1;
//     repeat (5) @(posedge clk);
//     rst = 0;
//     @(posedge clk);
//   end

//   // AXI-Lite Master Logic
//   initial begin
//     // Wait for reset to de-assert
//     @(negedge rst);
//     @(posedge clk);

//     // Initialize AXI-Lite master signals
//     cache_bus.arvalid <= 0;
//     cache_bus.araddr  <= 0;
//     cache_bus.rready  <= 1;  // Always ready to accept read data

//     // --- First Read Request: Address 0 ---
//     $display("TB: Sending read request for address 0x0");
//     cache_bus.arvalid <= 1;
//     cache_bus.araddr  <= 64'h0;

//     // Wait for the address to be accepted
//     do @(posedge clk); while (!(cache_bus.arvalid && cache_bus.arready));
//     cache_bus.arvalid <= 0;  // De-assert valid after acceptance

//     // Wait for the read data to be valid
//     do @(posedge clk); while (!cache_bus.rvalid);
//     $display("TB: Received data for address 0x0: 0x%h", cache_bus.rdata);

//     // --- Second Read Request: Address 16 ---
//     $display("TB: Sending read request for address 0x10");
//     cache_bus.arvalid <= 1;
//     cache_bus.araddr  <= 64'h10;

//     // Wait for the address to be accepted
//     do @(posedge clk); while (!(cache_bus.arvalid && cache_bus.arready));
//     cache_bus.arvalid <= 0;

//     // Wait for the read data to be valid
//     do @(posedge clk); while (!cache_bus.rvalid);
//     $display("TB: Received data for address 0x10: 0x%h", cache_bus.rdata);

//     $display("TB: Test complete.");
//     $finish;
//   end

// endmodule
