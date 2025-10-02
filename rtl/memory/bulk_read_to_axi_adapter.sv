module bulk_read_to_axi_adapter #(
  parameter logic [7:0] LINE_SIZE = 8,
  parameter int         DATA_W    = 64
) (
        bulk_read_interface.slave bulk_read_in,
        axi_interface_if.rd_mst   axi_read_out,
        axi_interface_if.wr_mst   axi_write_out,
  input logic                     clk,
  input logic                     rst

);

  typedef enum {
    AD_IDLE,
    AD_READ,
    AD_WRITE
  } state_t;

  state_t                                         current_state;
  state_t                                         next_state;

  logic   [$clog2(LINE_SIZE)-1 : 0]               current_beat;
  logic   [$clog2(LINE_SIZE)-1 : 0]               next_beat;

  logic   [      LINE_SIZE - 1 : 0][  DATA_W-1:0] read_write_buffer;
  logic   [      LINE_SIZE - 1 : 0][DATA_W/8-1:0] wstrb_buffer;


  assign bulk_read_in.resp_rdata = read_write_buffer;
  always_ff @(posedge clk) begin
    if (rst) begin
      current_state     <= AD_IDLE;
      current_beat      <= 0;
      read_write_buffer <= '{default: '0};
      wstrb_buffer      <= '{default: '0};
    end else begin

      current_state           <= next_state;
      current_beat            <= next_beat;
      bulk_read_in.resp_valid <= 0;
      //If we just accepted a request, store it in the buffer
      if (bulk_read_in.req_ready && bulk_read_in.req_valid && bulk_read_in.req_write) begin
        read_write_buffer <= bulk_read_in.req_wdata;
        wstrb_buffer      <= bulk_read_in.req_wstrb;
      end

      if (current_state == AD_READ) begin
        //Store to the read buffer
        read_write_buffer[current_beat] <= axi_read_out.rdata;
        if (next_state == AD_IDLE) begin
          //We just read the last one :)
          bulk_read_in.resp_valid <= 1;
        end
      end


    end
  end

  always_comb begin

    //We are always ready to recieve
    axi_read_out.rready    = 1;
    axi_write_out.bready   = 1;
    next_beat              = current_beat;

    axi_read_out.arvalid   = '0;
    axi_read_out.arid      = '0;
    axi_read_out.araddr    = '0;
    axi_read_out.arlen     = '0;
    axi_read_out.arsize    = '0;
    axi_read_out.arburst   = '0;
    axi_read_out.arlock    = '0;
    axi_read_out.arcache   = '0;
    axi_read_out.arprot    = '0;
    axi_read_out.arqos     = '0;
    axi_read_out.arregion  = '0;
    axi_read_out.aruser    = '0;

    axi_write_out.awvalid  = 0;
    axi_write_out.awid     = 0;
    axi_write_out.awaddr   = '0;
    axi_write_out.awlen    = 0;
    axi_write_out.awsize   = 0;
    axi_write_out.awburst  = '0;
    axi_write_out.awlock   = '0;
    axi_write_out.awcache  = '0;
    axi_write_out.awprot   = '0;
    axi_write_out.awqos    = '0;
    axi_write_out.awregion = '0;
    axi_write_out.awuser   = '0;

    axi_write_out.wvalid   = 0;
    axi_write_out.wdata    = '0;
    axi_write_out.wstrb    = '0;

    bulk_read_in.req_ready = 0;
    next_state             = AD_IDLE;
    case (current_state)
      AD_IDLE: begin
        //Present ready to master
        bulk_read_in.req_ready = !bulk_read_in.req_write ? axi_read_out.arready : axi_write_out.awready;
        if (bulk_read_in.req_valid) begin
          next_beat  = 0;
          next_state = bulk_read_in.req_write ? AD_WRITE : AD_READ;
          //Present the request to the interface
          if (!bulk_read_in.req_write) begin
            axi_read_out.arvalid  = 1;
            axi_read_out.arid     = 1;
            axi_read_out.araddr   = bulk_read_in.req_addr;
            axi_read_out.arlen    = LINE_SIZE - 1;
            axi_read_out.arsize   = 3;
            //INCR
            axi_read_out.arburst  = 'b11;
            axi_read_out.arlock   = '0;
            axi_read_out.arcache  = '0;
            axi_read_out.arprot   = '0;
            axi_read_out.arqos    = '0;
            axi_read_out.arregion = '0;
            axi_read_out.aruser   = '0;
          end else begin
            axi_write_out.awvalid  = 1;
            axi_write_out.awid     = 1;
            axi_write_out.awaddr   = bulk_read_in.req_addr;
            axi_write_out.awlen    = LINE_SIZE - 1;
            axi_write_out.awsize   = 3;
            axi_write_out.awburst  = 'b11;
            axi_write_out.awlock   = '0;
            axi_write_out.awcache  = '0;
            axi_write_out.awprot   = '0;
            axi_write_out.awqos    = '0;
            axi_write_out.awregion = '0;
            axi_write_out.awuser   = '0;

            axi_write_out.wvalid   = 1;
            axi_write_out.wdata    = bulk_read_in.req_wdata[0];
            axi_write_out.wstrb    = bulk_read_in.req_wstrb[0];

            next_beat              = axi_write_out.wready ? 1 : 0;
          end
        end else next_state = AD_IDLE;
      end
      AD_READ: begin
        bulk_read_in.req_ready = 0;
        next_beat              = axi_read_out.rvalid ? current_beat + 1 : current_beat;
        //Same here
        if (axi_read_out.rlast) next_state = AD_IDLE;
        else next_state = AD_READ;
      end
      AD_WRITE: begin
        bulk_read_in.req_ready = 0;
        next_beat              = axi_write_out.wready ? current_beat + 1 : current_beat;
        axi_write_out.wvalid   = 1;
        axi_write_out.wdata    = read_write_buffer[current_beat];
        axi_write_out.wstrb    = wstrb_buffer[current_beat];
        //Note that we could theoretically accept a request here (when the next_state would be idle), but that adds complexity
        if (next_beat == ($clog2(LINE_SIZE))'(LINE_SIZE)) next_state = AD_IDLE;
        else next_state = AD_WRITE;
      end
    endcase
  end



endmodule
