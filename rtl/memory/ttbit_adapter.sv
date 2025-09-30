module ttbit_adapter (
  input logic                    clk,
  input logic                    rst,
        axil_interface_if.rd_mst sf_out,
        axil_interface_if.wr_mst sf_out_wr,
        axil_interface_if.rd_slv tt_in
);
  //64 to 32 bit memory translator
  //Remove the thirty-two bit flip
  assign sf_out.araddr = tt_in.araddr & 64'b1111111111111111111111111111111111111111111111111111111111111011;
  logic requested_bit;
  always_ff @(posedge clk) begin
    //We need to ff the mem_addr
    requested_bit <= tt_in.araddr[2];
  end
  assign tt_in.rdata       = requested_bit ? sf_out.rdata[63:32] : sf_out.rdata[31:0];
  assign tt_in.arready     = sf_out.arready;
  assign sf_out.arvalid    = tt_in.arvalid;
  assign tt_in.rvalid      = sf_out.rvalid;
  assign sf_out_wr.awvalid = 0;
  assign sf_out_wr.wvalid  = 0;
  assign sf_out.rready     = tt_in.rready;
  assign sf_out_wr.bready  = 1;
endmodule
