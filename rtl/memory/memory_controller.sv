module memory_controller (
  input clk,
  input rst,

  axil_interface_if.rd_slv read,
  axil_interface_if.wr_slv write,

  axil_interface_if.rd_mst cache_read,
  axil_interface_if.wr_mst cache_write,

  axil_interface_if.rd_mst uart_read,
  axil_interface_if.wr_mst uart_write
);

  // Simple filtering. Address >= 0xFFFFFFFFF000: UART, remainder: cache

  typedef enum logic {
    CACHE,
    UART
  } connection_e;

  // ----------------
  // READ PATH
  // ----------------
  connection_e rd_current_connect;
  connection_e rd_next_connect;

  logic        read_response_accepted_d;
  logic        read_response_accepted_q;

  always_ff @(posedge clk) begin
    if (rst) begin
      read_response_accepted_q <= 1'b1;
      rd_current_connect       <= CACHE;
    end else begin
      // When we accept a new request, reset the accepted marker
      read_response_accepted_q <= read_response_accepted_d && !(read.arready && read.arvalid);
      if (read.arready && read.arvalid) rd_current_connect <= rd_next_connect;
    end
  end

  assign read_response_accepted_d = read_response_accepted_q || (read.rready && read.rvalid);
  assign rd_next_connect          = (read.araddr >= 64'hFFFFFFFFFFFFF000) ? UART : CACHE;
  always_comb begin
    // Decode next target by address


    // Ready comes from the selected target only, and only when we're allowed to issue
    unique case (rd_next_connect)
      CACHE: read.arready = cache_read.arready && read_response_accepted_d;
      UART:  read.arready = uart_read.arready && read_response_accepted_d;
    endcase

    if (!read.arvalid) begin
      cache_read.arvalid = 1'b0;
      cache_read.araddr  = '0;
      uart_read.arvalid  = 1'b0;
      uart_read.araddr   = '0;
    end else begin
      // Forward AR to selected target; deassert other
      unique case (rd_next_connect)
        CACHE: begin
          cache_read.arvalid = read.arvalid && read_response_accepted_d;
          cache_read.araddr  = read.araddr;
          uart_read.arvalid  = 1'b0;
          uart_read.araddr   = '0;
        end
        UART: begin
          cache_read.arvalid = 1'b0;
          cache_read.araddr  = '0;
          uart_read.arvalid  = read.arvalid && read_response_accepted_d;
          uart_read.araddr   = read.araddr;
        end
      endcase
    end
  end

  // Return data from the previously selected target
  always_comb begin
    //Since there is always one at a time, we can forward the rready
    cache_read.rready = read.rready;
    uart_read.rready  = read.rready;
    unique case (rd_current_connect)
      CACHE: begin
        read.rvalid = cache_read.rvalid;
        read.rdata  = cache_read.rdata;
        //cache_read.rready = read.rready;
        //uart_read.rready  = 1'b0;
      end
      UART: begin
        read.rvalid = uart_read.rvalid;
        read.rdata  = uart_read.rdata;
        //uart_read.rready  = read.rready;
        //cache_read.rready = 1'b0;
      end
    endcase
  end

  // ----------------
  // WRITE PATH
  // ----------------
  connection_e wr_current_connect;
  connection_e wr_next_connect;

  logic        write_response_accepted_d;
  logic        write_response_accepted_q;

  always_ff @(posedge clk) begin
    if (rst) begin
      write_response_accepted_q <= 1'b1;
      wr_current_connect        <= CACHE;
    end else begin
      // When we accept a new AW, reset the accepted marker
      write_response_accepted_q <= write_response_accepted_d && !(write.awready && write.awvalid);
      if (write.awready && write.awvalid) wr_current_connect <= wr_next_connect;
    end
  end

  assign write_response_accepted_d = write_response_accepted_q || (write.bready && write.bvalid);
  assign wr_next_connect           = (write.awaddr >= 64'hFFFFFFFFFFFFF000) ? UART : CACHE;

  always_comb begin
    unique case (wr_next_connect)
      CACHE: write.awready = cache_write.awready && write_response_accepted_d;
      UART:  write.awready = uart_write.awready && write_response_accepted_d;
    endcase

    unique case (wr_next_connect)
      CACHE: begin
        cache_write.awvalid = write.awvalid && write_response_accepted_d;
        cache_write.awaddr  = write.awaddr;
        uart_write.awvalid  = 1'b0;
        uart_write.awaddr   = '0;
      end
      UART: begin
        cache_write.awvalid = 1'b0;
        cache_write.awaddr  = '0;
        uart_write.awvalid  = write.awvalid && write_response_accepted_d;
        uart_write.awaddr   = write.awaddr;
      end
    endcase
  end

  always_comb begin
    // defaults
    //cache_write.wvalid = 1'b0;
    //Always say we will send a write data, so that wready can get set
    cache_write.wvalid = 1'b1;
    cache_write.wdata  = '0;
    cache_write.wstrb  = '0;
    uart_write.wvalid  = 1'b1;
    uart_write.wdata   = '0;
    uart_write.wstrb   = '0;

    unique case (wr_next_connect)
      CACHE: begin
        //cache_write.wvalid = write.wvalid;
        cache_write.wdata = write.wdata;
        cache_write.wstrb = write.wstrb;
      end
      UART: begin
        //uart_write.wvalid = write.wvalid;
        uart_write.wdata = write.wdata;
        uart_write.wstrb = write.wstrb;
      end
    endcase
  end

  assign write.wready = (wr_next_connect == CACHE) ? cache_write.wready : uart_write.wready;

  always_comb begin

    //Note that since we only accept one at a time, this should be okay
    cache_write.bready = write.bready;
    uart_write.bready  = write.bready;

    unique case (wr_current_connect)
      CACHE: begin
        write.bvalid = cache_write.bvalid;
        //cache_write.bready = write.bready;
      end
      UART: begin
        write.bvalid = uart_write.bvalid;
        //uart_write.bready = write.bready;
      end
    endcase
  end

endmodule
