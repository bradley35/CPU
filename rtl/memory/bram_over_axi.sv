//Uses AXI interface to we can plug/play later with Xilinx AXI DRAM IP

//Has very limiting restirctions:
//Only supports fixed burst sized + aligned access
//Only supports fixed full-width beats
//Ignores ID and is fully in-order

module bram_over_axi #(
  parameter int MEMORY_SIZE_BYTES       = 4096,
  parameter int MEMORY_BLOCK_MAX_ACCESS = 72,
  parameter int FIXED_NUMBER_OF_BEATS   = 16
) (
  logic clk,
  logic rst,

  //We recieve read/writes
  axi_interface_if.wr_slv write_slv,
  axi_interface_if.rd_slv read_slv
);
  function automatic int max_div_le(int A, int B);
    int best;
    best = 1;
    for (int d = 1; d <= A; d++) begin
      if (B % d == 0) best = d;
    end
    return best;
  endfunction
  parameter int MEMORY_ADDRESS_BIT_LENGTH = $clog2(MEMORY_SIZE_BYTES / (write_slv.DATA_W / 8));
  parameter int BLOCK_SIZE = max_div_le(MEMORY_BLOCK_MAX_ACCESS, write_slv.DATA_W);
  //Supposing DATA_W is a power of 2, NUMBER_OF_BLOCKS also be a power of 2
  parameter int NUMBER_OF_BLOCKS = write_slv.DATA_W / BLOCK_SIZE;
  parameter int ENTRIES_PER_BLOCK = int'($ceil(
      MEMORY_SIZE_BYTES * 8 / NUMBER_OF_BLOCKS / BLOCK_SIZE
  ));


  typedef enum {
    READ_IDLE,
    DELIVERING_READ_RESPONSE,
    DELIVERING_LAST_READ_RESPONSE
  } bram_read_state_e;

  typedef enum {
    WRITE_IDLE,
    ACCEPTING_WRITE_BURST,
    AWAITING_DONE_ACCEPT
  } bram_write_state_e;


  bram_read_state_e                                      read_state;
  bram_read_state_e                                      read_state_next;
  bram_write_state_e                                     write_state;
  bram_write_state_e                                     write_state_next;
  logic              [           write_slv.ADDR_W-1 : 0] araddr_d;
  logic              [           write_slv.ADDR_W-1 : 0] araddr_next;
  logic              [           write_slv.ADDR_W-1 : 0] awaddr_d;
  logic              [           write_slv.ADDR_W-1 : 0] awaddr_next;
  logic              [$clog2(FIXED_NUMBER_OF_BEATS)-1:0] read_current_beat;
  logic              [$clog2(FIXED_NUMBER_OF_BEATS)-1:0] read_current_beat_next;
  logic              [$clog2(FIXED_NUMBER_OF_BEATS)-1:0] write_current_beat;
  logic              [$clog2(FIXED_NUMBER_OF_BEATS)-1:0] write_current_beat_next;


  function automatic logic [write_slv.ADDR_W-1 : 0] read_address();
    case (read_state)
      READ_IDLE:                return read_slv.araddr;
      DELIVERING_READ_RESPONSE: return araddr_d;
    endcase
  endfunction
  function automatic logic [write_slv.ADDR_W-1 : 0] write_address();
    case (write_state)
      WRITE_IDLE:            return write_slv.awaddr;
      ACCEPTING_WRITE_BURST: return awaddr_d;
    endcase
  endfunction

  always_ff @(posedge clk, posedge rst) begin
    if (rst) begin
      read_current_beat  <= 0;
      read_state         <= READ_IDLE;

      write_current_beat <= 0;
      write_state        <= WRITE_IDLE;

    end else begin
      read_state         <= read_state_next;
      araddr_d           <= araddr_next;
      read_current_beat  <= read_current_beat_next;
      write_state        <= write_state_next;
      awaddr_d           <= awaddr_next;
      write_current_beat <= write_current_beat_next;

      if (read_slv.arvalid && read_slv.rready) begin
        //We just accepted. Set the ID
        read_slv.rid <= read_slv.arid;
      end

      if (write_slv.awvalid && write_slv.wvalid) begin
        //We just accepted. Set the ID
        write_slv.bid <= write_slv.awid;
      end

    end
  end

  always_comb begin
    read_state_next = read_state;
    case (read_state)
      READ_IDLE: begin
        //We are ready to accept
        read_slv.rvalid  = 0;
        read_slv.arready = 1;
        if (read_slv.arvalid) begin
          if (read_slv.arlen + 1 != 8'(FIXED_NUMBER_OF_BEATS))
            $error(
                "Requesting burst with %d beats. Only %d is allowed.",
                read_slv.arlen + 1,
                FIXED_NUMBER_OF_BEATS
            );
          read_state_next = DELIVERING_READ_RESPONSE;
        end
        read_slv.rresp = 0;
        read_slv.rlast = 0;
      end
      DELIVERING_READ_RESPONSE: begin
        read_slv.rvalid  = 1;
        read_slv.arready = 0;
        //Currently delivering the second-to-last beat. Preparing the last beat (will be latched on the next edge)
        if (read_slv.rready && read_current_beat == ($clog2(
                FIXED_NUMBER_OF_BEATS
            ))'(FIXED_NUMBER_OF_BEATS - 1)) begin
          read_state_next = DELIVERING_LAST_READ_RESPONSE;
        end
        read_slv.rresp = 0;
        read_slv.rlast = 0;
      end
      DELIVERING_LAST_READ_RESPONSE: begin
        read_slv.rvalid  = 1;
        read_slv.arready = 0;
        //OK
        read_slv.rresp   = 2'b00;
        read_slv.rlast   = 1;
        if (read_slv.rready) read_state_next = READ_IDLE;
      end
    endcase
  end

  always_comb begin
    write_state_next = write_state;
    case (write_state)
      WRITE_IDLE: begin
        //We can accept both data and an address. Only accept when we have both
        write_slv.awready = write_slv.awvalid & write_slv.wvalid;
        write_slv.wready  = write_slv.awvalid & write_slv.wvalid;
        write_slv.bvalid  = 0;
        write_slv.bresp   = '0;
        if (write_slv.awready & write_slv.awvalid) begin
          if (write_slv.awlen + 1 != 8'(FIXED_NUMBER_OF_BEATS))
            $error(
                "Requesting burst with %d beats. Only %d is allowed.",
                write_slv.awlen + 1,
                FIXED_NUMBER_OF_BEATS
            );
          write_state_next = ACCEPTING_WRITE_BURST;
        end
      end
      ACCEPTING_WRITE_BURST: begin
        write_slv.wready  = 1;
        write_slv.awready = 0;
        write_slv.bvalid  = 0;
        write_slv.bresp   = '0;
        //We are about to write the last one
        if (write_slv.wvalid && write_current_beat == ($clog2(
                FIXED_NUMBER_OF_BEATS
            ))'(FIXED_NUMBER_OF_BEATS - 1)) begin
          //We can say we are done
          write_slv.bvalid = 1;
          //OK
          write_slv.bresp  = 2'b00;
          write_state_next = write_slv.bready ? WRITE_IDLE : AWAITING_DONE_ACCEPT;
        end
      end
      AWAITING_DONE_ACCEPT: begin
        write_slv.bvalid  = 1;
        write_slv.awready = 0;
        write_slv.wready  = 0;
        write_slv.bresp   = 2'b00;
        write_state_next  = write_slv.bready ? WRITE_IDLE : AWAITING_DONE_ACCEPT;
      end
    endcase
  end

  always_comb begin
    case (read_state_next)
      READ_IDLE: begin
        araddr_next            = '0;
        read_current_beat_next = 0;
      end
      DELIVERING_READ_RESPONSE: begin
        //Latch the address we are currently reading from
        araddr_next            = read_address();
        //Increment read_current_beat. 
        read_current_beat_next = read_slv.rready ? read_current_beat + 1 : read_current_beat;
      end
      DELIVERING_LAST_READ_RESPONSE: begin
        araddr_next            = '0;
        read_current_beat_next = 0;
      end
    endcase
  end
  always_comb begin
    case (write_state_next)
      ACCEPTING_WRITE_BURST: begin
        //Latch the address we are currently writing to
        awaddr_next             = write_address();
        //Increment the write_current_beat
        write_current_beat_next = write_slv.wvalid ? write_current_beat + 1 : write_current_beat;
      end
      AWAITING_DONE_ACCEPT, WRITE_IDLE: begin
        awaddr_next             = '0;
        write_current_beat_next = 0;
      end
    endcase
  end

  genvar i;
  generate
    for (i = 0; i < NUMBER_OF_BLOCKS; i++) begin : generate_blocks
      logic [BLOCK_SIZE-1:0] mem_blk[ENTRIES_PER_BLOCK];

      always @(posedge clk) begin
        automatic
        logic [write_slv.DATA_W-1:0]
        read_entry_offset = (read_address() >> $clog2(
            write_slv.DATA_W / 8
        )) + (write_slv.ADDR_W)'(read_current_beat);

        automatic
        logic [write_slv.DATA_W-1:0]
        write_entry_offset = (write_address() >> $clog2(
            write_slv.DATA_W / 8
        )) + (write_slv.ADDR_W)'(write_current_beat);

        //Only if our last read was accepted should we present the new one. OR we are reading the first one
        if (read_slv.rready || read_state == READ_IDLE)
          read_slv.rdata[i*BLOCK_SIZE+:BLOCK_SIZE] <= mem_blk[read_entry_offset[MEMORY_ADDRESS_BIT_LENGTH-1:0]];

        for (int j = 0; j < BLOCK_SIZE / 8; j++) begin
          if (write_slv.wstrb[i*BLOCK_SIZE/8+j] == 1 && write_slv.wvalid)
            mem_blk[write_entry_offset[MEMORY_ADDRESS_BIT_LENGTH-1:0]][j*8 +: 8] <= write_slv.wdata[i*BLOCK_SIZE+j*8+:8];
        end


      end

    end
  endgenerate




endmodule

