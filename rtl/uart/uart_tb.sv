module uart_tb (
  input clk,
  input rst
);

  axi_interface_if #(.DATA_W(64)) bus ();
  bram_over_axi dut (
    .clk,
    .rst,
    .read_slv (bus.rd_slv),
    .write_slv(bus.wr_slv)
  );

  axi_interface_if #(.DATA_W(64)) bus2 ();
  bram_over_axi cache_memory_backing (
    .clk,
    .rst,
    .read_slv (bus2.rd_slv),
    .write_slv(bus2.wr_slv)
  );

  axil_interface_if #(.DATA_W(64)) cache_bus ();
  bulk_read_interface bulk_interface ();
  bulk_read_to_axi_adapter adapter (
    .axi_read_out (bus2.rd_mst),
    .axi_write_out(bus2.wr_mst),
    .bulk_read_in (bulk_interface.slave),
    .clk,
    .rst
  );

  memory_with_bram_cache cache (
    .clk,
    .rst,
    .cache_wr_int     (cache_bus.wr_slv),
    .cache_rd_int     (cache_bus.rd_slv),
    .memory_access_out(bulk_interface.master),
    .dump_cache       ()
  );


  axil_interface_if combus ();
  axil_interface_if uartbus ();
  uart_over_axi4lite uart (
    .clk,
    .rst,
    .rx          (),
    .tx          (),
    .read_access (uartbus.rd_slv),
    .write_access(uartbus.wr_slv)
  );

  memory_controller mem_ctrl (
    .clk,
    .rst,
    .read       (combus.rd_slv),
    .write      (combus.wr_slv),
    .cache_read (cache_bus.rd_mst),
    .cache_write(cache_bus.wr_mst),
    .uart_read  (uartbus.rd_mst),
    .uart_write (uartbus.wr_mst)

  );

endmodule

