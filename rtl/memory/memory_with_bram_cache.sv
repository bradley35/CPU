module memory_with_bram_cache #(
  parameter int ADDR_W = 64,
  parameter int DATA_W = 64,

  // Address breakdown: [ TAG | INDEX | OFFSET ]
  // OFFSET selects a byte within a cache line.
  parameter int OFFSET_BITS = 7,                // => LINE_BYTES = 128
  parameter int LINE_BYTES  = 1 << OFFSET_BITS,

  parameter int WORDS_PER_LINE = LINE_BYTES / (DATA_W / 8),

  parameter int INDEX_BITS  = 4,               // => 16 lines (toy example)
  parameter int CACHE_LINES = 1 << INDEX_BITS,

  parameter int TAG_BITS = ADDR_W - INDEX_BITS - OFFSET_BITS,

  parameter OFFSET_WORD_BITS = OFFSET_BITS - $clog2(DATA_W / 8)

) (

  //Interface into cache

  axil_interface_if.wr_slv cache_wr_int,
  axil_interface_if.rd_slv cache_rd_int,

  //Interface out of cache
  bulk_read_interface.master memory_access_out,

  //Command to dump
  //After the current instruction is done, will
  //proceed to dump the cache
  input logic dump_cache,

  logic clk,
  logic rst
);

  initial begin
    if (TAG_BITS <= 0)
      g_param_check : begin
        $error("TAG_BITS must be positive");
      end
  end
  typedef logic [7:0] byte_t;
  typedef logic [DATA_W - 1 : 0] line_t[WORDS_PER_LINE];
  typedef line_t cache_t[CACHE_LINES];
  typedef logic [TAG_BITS - 1:0] tag_t;
  typedef struct packed {
    logic valid;
    logic dirty;
  } line_meta_t;
  typedef struct {
    tag_t                   tag;
    logic [INDEX_BITS-1:0]  index;
    logic [OFFSET_BITS-1:0] offset;

    logic [ADDR_W-1:0] base_address;
  } address_parts_rt;
  function automatic address_parts_rt address_parts(logic [ADDR_W - 1 : 0] a);
    automatic logic [INDEX_BITS-1:0] index = a[ADDR_W-1-TAG_BITS-:INDEX_BITS];
    automatic tag_t                  tag = a[ADDR_W-1-:TAG_BITS];
    automatic logic [    ADDR_W-1:0] base;

    base = {tag, index, {OFFSET_BITS{1'b0}}};

    return '{index: index, base_address: base, tag: tag, offset: a[OFFSET_BITS-1:0]};
  endfunction

  function automatic logic address_match(logic [ADDR_W - 1 : 0] a, tag_t tag, line_meta_t meta);
    automatic address_parts_rt parts = address_parts(a);
    return parts.tag == tag && meta.valid;
  endfunction

  //These should live in BRAM and therefore be accessed behind always_ff
  cache_t     cache_memory;
  tag_t       cache_tags       [CACHE_LINES];
  line_meta_t cache_valid_dirty[CACHE_LINES];

  typedef enum {
    IDLE,
    READ,
    WRITE,
    WRITEBACK,
    DUMPING
  } cache_state_t;

  //NOTE: We burn a cycle on cache miss to keep the logic simpler (two step: load to cache, present cache ... it would be possible to do these at once).
  //I believe this is a fine tradeoff, so long as no cycles are burned on hits
  typedef enum {
    EF_IDLE,
    EF_READ_HIT,
    EF_READ_MISS,
    EF_WRITE_HIT,
    EF_WRITE_MISS,
    EF_WRITEBACK,
    EF_DUMPING
  } effective_cache_state_t;

  cache_state_t                                current_state;
  cache_state_t                                next_state;
  effective_cache_state_t                      effective_state;

  line_t                                       retrieved_cache_line;
  tag_t                                        retrieved_tag;
  line_meta_t                                  retrieved_meta;

  line_t                                       replaced_cache_line;
  tag_t                                        replaced_tag;
  line_meta_t                                  replaced_meta;
  logic                   [INDEX_BITS - 1 : 0] replaced_index;

  line_t                                       replacing_cache_line;
  tag_t                                        replacing_tag;
  logic                   [    INDEX_BITS-1:0] replacing_index;
  line_meta_t                                  replacing_meta;

  logic                   [      ADDR_W - 1:0] address_reg;
  logic                   [    ADDR_W - 1 : 0] write_reg;
  logic                   [    DATA_W/8-1 : 0] wstrb_reg;

  logic                   [      ADDR_W - 1:0] accepted_addr;
  logic                                        new_request_accepted;

  logic                                        memory_req_dispatched;

  logic                                        dumping;
  logic unsigned          [    INDEX_BITS : 0] dump_counter;

  assign memory_access_out.dumping_cache = dumping;


  always_ff @(posedge clk, posedge rst) begin
    if (rst) begin
      current_state = IDLE;
      cache_memory          <= '{default: '{default: '0}};
      cache_tags            <= '{default: '0};
      cache_valid_dirty     <= '{default: '0};
      retrieved_cache_line  <= '{default: '0};
      retrieved_tag         <= '0;
      retrieved_meta        <= '0;
      replaced_cache_line   <= '{default: '0};
      replaced_tag          <= '0;
      replaced_meta         <= '0;
      replaced_index        <= '0;
      address_reg           <= '0;
      write_reg             <= '0;
      wstrb_reg             <= '0;
      memory_req_dispatched <= '0;
      dumping               <= '0;
      dump_counter          <= 0;
    end else begin
      current_state <= next_state;
      //If the next state is idle, we must be done dumping.
      dumping       <= (dumping | dump_cache) && (next_state != IDLE);


      if (new_request_accepted) begin
        automatic
        logic
        redirect_replacing = (replacing_index == address_parts(
            accepted_addr
        ).index) && replacing_meta.valid;
        address_reg <= accepted_addr;
        write_reg <= cache_wr_int.wdata;
        wstrb_reg <= cache_wr_int.wstrb;

        //Set the cache bits
        retrieved_cache_line  <= redirect_replacing ? replacing_cache_line : cache_memory[address_parts(
            accepted_addr
        ).index];
        //Tag will be unchanged, as whatever is stored at this index has the same tag as the replacement
        retrieved_tag <= cache_tags[address_parts(accepted_addr).index];
        retrieved_meta <= redirect_replacing ? replacing_meta : cache_valid_dirty[address_parts(
            accepted_addr
        ).index];

        memory_req_dispatched <= 0;
      end
      case (effective_state)
        EF_READ_MISS, EF_WRITE_MISS: begin
          if (memory_req_dispatched) begin
            //We already sent the memory request
            if (memory_access_out.resp_valid) begin
              cache_memory[address_parts(address_reg).index] <= memory_access_out.resp_rdata;
              retrieved_cache_line <= memory_access_out.resp_rdata;
              replaced_cache_line <= retrieved_cache_line;

              cache_tags[address_parts(address_reg).index] <= address_parts(address_reg).tag;
              retrieved_tag <= address_parts(address_reg).tag;
              replaced_tag <= retrieved_tag;

              cache_valid_dirty[address_parts(
                  address_reg
              ).index] <=
              '{valid: 1, dirty: effective_state == EF_WRITE_MISS};
              retrieved_meta <= '{valid: 1, dirty: effective_state == EF_WRITE_MISS};
              replaced_meta <= retrieved_meta;

              replaced_index <= address_parts(address_reg).index;
            end
          end else begin  //Otherwise make sure we have dispatched the request
            memory_req_dispatched <= memory_req_dispatched || memory_access_out.req_ready;
          end
        end
        EF_WRITE_HIT: begin
          //Do the replacement
          //We need to save writes
          cache_memory[replacing_index]      <= replacing_cache_line;
          //Tag should be unchanged
          cache_tags[replacing_index]        <= replacing_tag;
          cache_valid_dirty[replacing_index] <= replacing_meta;

        end
      endcase
      case (effective_state)
        EF_DUMPING: begin
          //Piggy-back off of writeback logic
          if (!writeback_neccesary) begin
            if (dump_counter == (INDEX_BITS + 1)'(CACHE_LINES)) begin
              //That means that the last one (CACHE_LINES-1) was accepted
              for (int i = 0; i < CACHE_LINES; i++) begin
                cache_valid_dirty[i] = '0;
              end
            end else begin

              replaced_cache_line <= cache_memory[dump_counter[INDEX_BITS-1:0]];
              replaced_tag        <= cache_tags[dump_counter[INDEX_BITS-1:0]];
              replaced_meta       <= cache_valid_dirty[dump_counter[INDEX_BITS-1:0]];
              replaced_index      <= dump_counter[INDEX_BITS-1:0];
              dump_counter        <= dump_counter + 1;
            end
          end
        end
        default: dump_counter <= 0;
      endcase
      if (writeback_neccesary && memory_access_out.req_ready) replaced_meta <= '0;

    end


  end

  logic writeback_neccesary;
  always_comb begin

    writeback_neccesary = (replaced_meta.valid == 1 && replaced_meta.dirty == 1);

    case (current_state)
      IDLE: effective_state = EF_IDLE;
      READ:
      case (address_match(
          address_reg, retrieved_tag, retrieved_meta
      ))
        'b1: effective_state = EF_READ_HIT;
        'b0: effective_state = EF_READ_MISS;
      endcase
      WRITE:
      case (address_match(
          address_reg, retrieved_tag, retrieved_meta
      ))
        'b1: effective_state = EF_WRITE_HIT;
        'b0: effective_state = EF_WRITE_MISS;
      endcase
      WRITEBACK: effective_state = EF_WRITEBACK;
      DUMPING: effective_state = EF_DUMPING;
    endcase
  end
  always_comb begin


    next_state           = current_state;
    new_request_accepted = 0;
    accepted_addr        = '0;

    case (effective_state)
      //We can accept a new request in all these cases so long as our response was accepted
      IDLE, EF_READ_HIT, EF_WRITE_HIT, EF_WRITEBACK: begin
        automatic logic transaction_complete;
        automatic logic dump_bypass;
        dump_bypass          = 0;
        transaction_complete = 1;
        case (effective_state)
          IDLE:         transaction_complete = 1;
          EF_READ_HIT:  transaction_complete = cache_rd_int.rready;
          EF_WRITE_HIT: transaction_complete = cache_wr_int.bready;
        endcase

        if ((dump_cache || dumping) && transaction_complete) begin
          next_state  = DUMPING;
          dump_bypass = 1;
        end

        if (writeback_neccesary && transaction_complete) next_state = WRITEBACK;

        cache_rd_int.arready = transaction_complete && !writeback_neccesary && !dump_bypass;
        //Only accept all at once
        cache_wr_int.awready = cache_rd_int.arready && !cache_rd_int.arvalid && (cache_wr_int.awvalid && cache_wr_int.wvalid);
        cache_wr_int.wready = cache_wr_int.awready;


        //If we have no request, we can go to IDLE
        if (!writeback_neccesary && transaction_complete && !dump_bypass) next_state = IDLE;

        if (cache_rd_int.arready && cache_rd_int.arvalid) begin
          //Just accepted read
          next_state           = READ;
          new_request_accepted = 1;
          accepted_addr        = cache_rd_int.araddr;
        end
        if (cache_wr_int.awready && cache_wr_int.awvalid) begin
          //Just accepted write
          next_state           = WRITE;
          new_request_accepted = 1;
          accepted_addr        = cache_wr_int.awaddr;
        end


      end
      EF_DUMPING: begin
        //Only transition out when we are done
        if (dump_counter == (INDEX_BITS + 1)'(CACHE_LINES)) begin
          if (memory_access_out.req_ready) next_state = IDLE;

        end
        cache_rd_int.arready = 0;
        cache_wr_int.awready = 0;
        cache_wr_int.wready  = cache_wr_int.awready;
      end
      default: begin
        cache_rd_int.arready = 0;
        cache_wr_int.awready = 0;
        cache_wr_int.wready  = cache_wr_int.awready;
      end
    endcase

  end

  always_comb begin
    memory_access_out.req_valid = 0;
    memory_access_out.req_addr  = '0;
    memory_access_out.req_write = 0;
    memory_access_out.req_wstrb = '{default: '0};
    memory_access_out.req_wdata = '{default: '0};

    cache_rd_int.rvalid         = 0;
    cache_rd_int.rdata          = '0;

    cache_wr_int.bvalid         = 0;

    replacing_cache_line        = '{default: '0};
    replacing_index             = '0;
    replacing_tag               = '0;
    replacing_meta              = '0;

    case (effective_state)
      //When we miss, send out a request to update the cache so these can become a hit
      EF_READ_MISS, EF_WRITE_MISS: begin
        if (!memory_req_dispatched) begin
          memory_access_out.req_valid = 1;
          memory_access_out.req_addr  = address_parts(address_reg).base_address;
          memory_access_out.req_write = 0;
        end
      end
      //On hit, we can present the result
      EF_READ_HIT: begin
        automatic logic [OFFSET_BITS - 1 : 0] offset = address_parts(address_reg).offset;
        cache_rd_int.rvalid = 1;
        cache_rd_int.rdata  = retrieved_cache_line[offset[OFFSET_BITS-1 : $clog2(DATA_W/8)]];
      end
      // On write hit, we can tell the master we are done, but we also need to update the cache storage
      EF_WRITE_HIT: begin
        automatic logic [OFFSET_BITS - 1 : 0] offset = address_parts(address_reg).offset;
        logic           [     DATA_W - 1 : 0] new_word;
        for (int b = 0; b < DATA_W / 8; b++) begin
          new_word[b*8+:8] = wstrb_reg[b] ? write_reg[b*8+:8] : retrieved_cache_line[offset[OFFSET_BITS-1 : $clog2(
              DATA_W/8)]][b*8+:8];
        end
        cache_wr_int.bvalid = 1;
        replacing_cache_line = retrieved_cache_line;
        replacing_cache_line[offset[OFFSET_BITS-1 : $clog2(DATA_W/8)]] = new_word;
        replacing_index = address_parts(address_reg).index;
        replacing_tag = retrieved_tag;
        replacing_meta = '{valid: 1, dirty : 1};
      end
    endcase

    //When we transition to writeback, we need to present our writeback request
    if (writeback_neccesary) begin

      memory_access_out.req_valid = 1;
      memory_access_out.req_addr  = {replaced_tag, replaced_index, (OFFSET_BITS)'('b0)};
      memory_access_out.req_write = 1;
      memory_access_out.req_wdata = replaced_cache_line;
      memory_access_out.req_wstrb = '{default: '{default: 1}};
    end
  end


endmodule
