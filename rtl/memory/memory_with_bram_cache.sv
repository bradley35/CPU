module memory_with_bram_cache #(
  parameter int ADDR_W = 64,
  parameter int DATA_W = 64,

  // Address breakdown: [ TAG | INDEX | OFFSET ]
  // OFFSET selects a byte within a cache line.
  parameter int OFFSET_BITS = 6,                // => LINE_BYTES = 64 = 8 WORDS
  parameter int LINE_BYTES  = 1 << OFFSET_BITS,

  parameter int WORDS_PER_LINE = LINE_BYTES / (DATA_W / 8),

  parameter int INDEX_BITS  = 6,               // => 64 lines
  parameter int CACHE_LINES = 1 << INDEX_BITS,

  parameter int TAG_BITS = ADDR_W - INDEX_BITS - OFFSET_BITS,

  parameter OFFSET_WORD_BITS = OFFSET_BITS - $clog2(DATA_W / 8),

  parameter logic HAS_WRITE = 1

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
  typedef logic [WORDS_PER_LINE - 1 : 0][DATA_W - 1 : 0] line_t;
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
  function automatic address_parts_rt address_parts(input logic [ADDR_W - 1 : 0] a);
    automatic logic [INDEX_BITS-1:0] index = a[ADDR_W-1-TAG_BITS-:INDEX_BITS];
    automatic tag_t                  tag = a[ADDR_W-1-:TAG_BITS];
    automatic logic [    ADDR_W-1:0] base;

    base = {tag, index, {OFFSET_BITS{1'b0}}};
    return '{index: index, base_address: base, tag: tag, offset: a[OFFSET_BITS-1:0]};
  endfunction

  function automatic logic address_match(input logic [ADDR_W - 1 : 0] a, input tag_t tag,
                                         input line_meta_t meta);
    automatic address_parts_rt parts = address_parts(a);
    return parts.tag == tag && meta.valid;
  endfunction

  typedef enum logic [2:0] {
    IDLE,
    READ,
    WRITE,
    WRITEBACK,
    DUMPING
  } cache_state_t;

  //NOTE: We burn a cycle on cache miss to keep the logic simpler (two step: load to cache, present cache ... it would be possible to do these at once).
  //I believe this is a fine tradeoff, so long as no cycles are burned on hits
  typedef enum logic [2:0] {
    EF_IDLE,
    EF_READ_HIT,
    EF_READ_MISS,
    EF_WRITE_HIT,
    EF_WRITE_MISS,
    EF_WRITEBACK,
    EF_DUMPING
  } effective_cache_state_t;


  typedef enum {
    RS_NONE,
    RS_RAW,
    RS_WRITE
  } retrieval_spot_t;

  cache_state_t                                    current_state;
  cache_state_t                                    next_state;
  effective_cache_state_t                          effective_state;

  line_t                                           retrieved_cache_line;
  retrieval_spot_t                                 retrieved_source;
  line_t                                           retrieved_cache_line_synth;
  tag_t                                            retrieved_tag;
  logic                                            use_address_tag_instead;
  line_meta_t                                      retrieved_meta;

  line_t                                           replaced_cache_line;
  retrieval_spot_t                                 replaced_source;
  line_t                                           replaced_cache_line_synth;
  tag_t                                            replaced_tag;
  line_meta_t                                      replaced_meta;
  logic                   [    INDEX_BITS - 1 : 0] replaced_index;



  logic                   [          ADDR_W - 1:0] address_reg;
  address_parts_rt                                 address_reg_parts;
  logic                   [        ADDR_W - 1 : 0] write_reg;
  logic                   [        DATA_W/8-1 : 0] wstrb_reg;

  logic                   [          ADDR_W - 1:0] read_addr;
  address_parts_rt                                 read_addr_parts;
  line_meta_t                                      read_addr_meta;
  logic                   [          ADDR_W - 1:0] write_addr;
  address_parts_rt                                 write_addr_parts;
  line_meta_t                                      write_addr_meta;

  line_meta_t                                      accepted_address_meta;
  address_parts_rt                                 accepted_addr_parts;


  logic                                            is_read_not_write;
  logic                                            new_request_accepted;

  logic                                            memory_req_dispatched;

  logic                                            dumping;
  logic                                            can_accept_request;
  logic unsigned          [        INDEX_BITS : 0] dump_counter;

  //These should live in BRAM and therefore be accessed behind always_ff
  (* RAM_STYLE = "block" *)tag_t                                            cache_tags                 [CACHE_LINES];
  logic unsigned          [    INDEX_BITS - 1 : 0] requested_tag;
  logic                                            tag_req_en;
  line_meta_t                                      cache_valid_dirty          [CACHE_LINES];
  logic                   [    INDEX_BITS - 1 : 0] cache_read_index;
  line_t                                           raw_read_line;
  line_t                                           cache_write_line;
  line_t                                           cache_write_line_q;
  logic                   [WORDS_PER_LINE - 1 : 0] cache_write_en;
  logic                   [    INDEX_BITS - 1 : 0] cache_write_index;
  tag_t                                            writing_tag;
  line_meta_t                                      writing_meta;

  generate
    for (genvar i = 0; i < WORDS_PER_LINE; i++) begin
      (* RAM_STYLE = "block" *) logic [DATA_W - 1 : 0] line_block[CACHE_LINES];
      always_ff @(posedge clk) begin
        raw_read_line[i] <= line_block[cache_read_index];
        if (cache_write_en[i]) line_block[cache_write_index] <= cache_write_line[i];
      end
    end
  endgenerate

  always_ff @(posedge clk) begin
    retrieved_tag <= cache_tags[requested_tag];
    if (effective_state == EF_READ_MISS || effective_state == EF_WRITE_MISS)
      cache_tags[address_reg_parts.index] <= address_reg_parts.tag;
  end


  assign memory_access_out.dumping_cache = dumping;
  logic writeback_neccesary;

  always_ff @(posedge clk) begin
    if (rst) begin
      current_state = IDLE;
      cache_valid_dirty       <= '{default: '0};
      retrieved_meta          <= '0;
      replaced_tag            <= '0;
      replaced_meta           <= '0;
      replaced_index          <= '0;
      address_reg             <= '0;
      write_reg               <= '0;
      wstrb_reg               <= '0;
      memory_req_dispatched   <= '0;
      dumping                 <= '0;
      dump_counter            <= '0;
      retrieved_source        <= RS_NONE;
      replaced_source         <= RS_NONE;
      cache_write_line_q      <= 0;
      use_address_tag_instead <= 0;
    end else begin
      current_state           <= next_state;
      cache_write_line_q      <= cache_write_line;
      //If the next state is idle, we must be done dumping.

      dumping                 <= (dumping | dump_cache) && (next_state != IDLE);

      retrieved_cache_line    <= memory_access_out.resp_rdata;
      //Set to raw as we will continue grabbing the same address anyway and it will now be correct
      retrieved_source        <= RS_RAW;
      //We can get away with this
      // replaced_cache_line <= replaced_cache_line_synth;
      // if (replaced_source != RS_NONE) begin
      //   replaced_source <= RS_NONE;
      // end

      /* Misleading naming to avoid MUXes (i.e. always store and only use value when it is valid) */
      //retrieved_cache_line <= redirect_replacing ? replacing_cache_line : cache_write_line;
      //Any time we CAN accept, assume we did for speed
      use_address_tag_instead <= 0;
      if (can_accept_request) begin
        automatic
        logic
        redirect_replacing = (cache_write_index == accepted_addr_parts.index) && writing_meta.valid;
        address_reg <= is_read_not_write ? read_addr : write_addr;
        write_reg <= cache_wr_int.wdata;
        wstrb_reg <= cache_wr_int.wstrb;
        //What is in replacing now will be in WRITE next cycle
        retrieved_source <= redirect_replacing && cache_write_en[accepted_addr_parts.offset[OFFSET_BITS-1 : $clog2(
            DATA_W/8
        )]] ? RS_WRITE : RS_RAW;
        //Tag will be unchanged, as whatever is stored at this index has the same tag as the replacement
        retrieved_meta <= redirect_replacing ? writing_meta : accepted_address_meta;

        memory_req_dispatched <= 0;
      end
      unique case (effective_state)
        EF_READ_MISS, EF_WRITE_MISS: begin
          if (memory_req_dispatched) begin
            //We already sent the memory request
            if (memory_access_out.resp_valid) begin
              //Unavoidable MUX
              //retrieved_cache_line <= memory_access_out.resp_rdata;
              retrieved_source <= RS_NONE;

              //replaced_cache_line <= retrieved_cache_line_synth;
              //Always grab the clean version from BRAM
              replaced_source <= RS_RAW;
              use_address_tag_instead <= 1;
              replaced_tag <= retrieved_tag;

              cache_valid_dirty[address_reg_parts.index] <= '{
                  valid: 1'b1,
                  dirty: effective_state == EF_WRITE_MISS
              };
              retrieved_meta <= '{valid: 1'b1, dirty: effective_state == EF_WRITE_MISS};
              replaced_meta <= retrieved_meta;

              replaced_index <= address_reg_parts.index;
            end
          end else begin  //Otherwise make sure we have dispatched the request
            memory_req_dispatched <= memory_req_dispatched || memory_access_out.req_ready;
          end
        end
        EF_WRITE_HIT: begin
          cache_valid_dirty[cache_write_index] <= writing_meta;
        end
        default: ;
      endcase
      case (effective_state)
        EF_DUMPING: begin
          //Piggy-back off of writeback logic
          if (HAS_WRITE) begin
            if (!writeback_neccesary) begin
              if (dump_counter == (INDEX_BITS + 1)'(CACHE_LINES)) begin
                //That means that the last one (CACHE_LINES-1) was accepted
                for (int i = 0; i < CACHE_LINES; i++) begin
                  cache_valid_dirty[i] <= '0;
                end
              end else begin

                replaced_source <= RS_RAW;
                replaced_meta   <= cache_valid_dirty[dump_counter[INDEX_BITS-1:0]];
                replaced_index  <= dump_counter[INDEX_BITS-1:0];
                dump_counter    <= dump_counter + 1;
              end
            end
          end else begin
            for (int i = 0; i < CACHE_LINES; i++) begin
              cache_valid_dirty[i] <= '0;
            end
          end
        end
        default: dump_counter <= 0;
      endcase
      if (writeback_neccesary && memory_access_out.req_ready) replaced_meta <= '0;

    end
  end
  always_comb begin
    cache_read_index    = effective_state == EF_DUMPING ?  dump_counter[INDEX_BITS-1:0] :  (new_request_accepted ? accepted_addr_parts.index : address_reg_parts.index);
    requested_tag =  effective_state == EF_DUMPING ?  dump_counter[INDEX_BITS-1:0] :  (new_request_accepted ? accepted_addr_parts.index : address_reg_parts.index);
  end
  always_comb begin
    case (retrieved_source)
      RS_RAW:   retrieved_cache_line_synth = raw_read_line;
      RS_WRITE: retrieved_cache_line_synth = cache_write_line_q;
      default:  retrieved_cache_line_synth = retrieved_cache_line;
    endcase
    replaced_cache_line_synth = raw_read_line;
    // case (replaced_source)
    //   RS_RAW: begin
    //     replaced_cache_line_synth = raw_read_line;
    //   end
    //   //RS_WRITE: replaced_cache_line_synth = cache_write_line_q;
    //   default: replaced_cache_line_synth = raw_read_line;
    // endcase
  end

  always_comb begin

    writeback_neccesary = (replaced_meta.valid == 1 && replaced_meta.dirty == 1);

    unique case (current_state)
      IDLE: effective_state = EF_IDLE;
      READ:
      case (address_match(
          address_reg,
          use_address_tag_instead ? address_reg_parts.tag : retrieved_tag,
          retrieved_meta
      ))
        'b1: effective_state = EF_READ_HIT;
        'b0: effective_state = EF_READ_MISS;
      endcase
      WRITE:
      case (address_match(
          address_reg,
          use_address_tag_instead ? address_reg_parts.tag : retrieved_tag,
          retrieved_meta
      ))
        'b1: effective_state = EF_WRITE_HIT;
        'b0: effective_state = EF_WRITE_MISS;
      endcase
      WRITEBACK: effective_state = EF_WRITEBACK;
      DUMPING: effective_state = EF_DUMPING;
      default: effective_state = EF_IDLE;
    endcase
  end
  always_comb begin


    next_state           = current_state;
    new_request_accepted = 0;
    can_accept_request   = 0;
    read_addr            = cache_rd_int.araddr;
    read_addr_parts      = address_parts(read_addr);
    write_addr           = cache_wr_int.awaddr;
    write_addr_parts     = address_parts(write_addr);
    read_addr_meta       = cache_valid_dirty[read_addr_parts.index];
    write_addr_meta      = cache_valid_dirty[write_addr_parts.index];

    is_read_not_write    = 0;



    unique case (effective_state)
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
          default:      ;
        endcase

        if ((dump_cache || dumping) && transaction_complete) begin
          next_state  = DUMPING;
          dump_bypass = 1;
        end

        if (writeback_neccesary && transaction_complete) next_state = WRITEBACK;
        can_accept_request = transaction_complete && !writeback_neccesary && !dump_bypass;
        cache_rd_int.arready = transaction_complete && !writeback_neccesary && !dump_bypass;
        //NOTE we cannot accept simultaneous reads/writes. However, this was causing a timing issue, so we pretend that we can
        //In the future, it would make sense to register the write and deal with it later
        cache_wr_int.awready = cache_rd_int.arready && /*!cache_rd_int.arvalid &&*/ (cache_wr_int.wvalid);
        cache_wr_int.wready = cache_wr_int.awready;


        //If we have no request, we can go to IDLE
        if (!writeback_neccesary && transaction_complete && !dump_bypass) next_state = IDLE;

        if (cache_rd_int.arready && cache_rd_int.arvalid) begin
          //Just accepted read
          next_state           = READ;
          new_request_accepted = 1;
          is_read_not_write    = 1;
        end
        if (cache_wr_int.awready && cache_wr_int.awvalid) begin
          //Just accepted write
          next_state           = WRITE;
          new_request_accepted = 1;
          is_read_not_write    = 0;
        end


      end
      EF_DUMPING: begin
        //Only transition out when we are done
        if (dump_counter == (INDEX_BITS + 1)'(CACHE_LINES)) begin
          if (memory_access_out.req_ready) next_state = IDLE;
        end
        if (!HAS_WRITE) next_state = IDLE;
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
    address_reg_parts     = address_parts(address_reg);
    accepted_addr_parts   = is_read_not_write ? read_addr_parts : write_addr_parts;
    accepted_address_meta = is_read_not_write ? read_addr_meta : write_addr_meta;
  end

  logic [             OFFSET_BITS - 1 : 0] offset_debug_out;
  logic [OFFSET_BITS-1 : $clog2(DATA_W/8)] line_offset_debug_out;
  logic [                  DATA_W - 1 : 0] new_word;

  logic [                   DATA_W -1 : 0] retrieved_word;

  always_comb begin
    memory_access_out.req_valid = 0;
    memory_access_out.req_addr = '0;
    memory_access_out.req_write = 0;
    memory_access_out.req_wstrb = '{default: '0};
    memory_access_out.req_wdata = '{default: '0};

    cache_rd_int.rvalid = 0;
    cache_rd_int.rdata = '0;

    cache_wr_int.bvalid = 0;



    new_word = '0;

    offset_debug_out = '0;
    line_offset_debug_out = '0;

    cache_write_en = '{default: '0};

    cache_write_index = '0;
    writing_tag = '0;
    writing_meta = '0;
    cache_write_line = memory_access_out.resp_rdata;
    retrieved_word =
        retrieved_cache_line_synth[address_reg_parts.offset[OFFSET_BITS-1 : $clog2(DATA_W/8)]];
    memory_access_out.req_wdata = replaced_cache_line_synth;
    unique case (effective_state)
      //When we miss, send out a request to update the cache so these can become a hit
      EF_READ_MISS, EF_WRITE_MISS: begin
        if (!memory_req_dispatched) begin
          memory_access_out.req_valid = 1;
          memory_access_out.req_addr  = address_reg_parts.base_address;
          memory_access_out.req_write = 0;
        end
        if (memory_access_out.resp_valid) begin

          cache_write_en    = '{default: 1'b1};
          cache_write_index = address_reg_parts.index;
        end
      end
      //On hit, we can present the result
      EF_READ_HIT: begin
        automatic logic [OFFSET_BITS - 1 : 0] offset;
        offset                = address_reg_parts.offset;
        cache_rd_int.rvalid   = 1;
        offset_debug_out      = offset;
        cache_rd_int.rdata    = retrieved_word;
        line_offset_debug_out = offset[OFFSET_BITS-1 : $clog2(DATA_W/8)];
      end
      // On write hit, we can tell the master we are done, but we also need to update the cache storage
      EF_WRITE_HIT: begin
        if (HAS_WRITE) begin
          for (int b = 0; b < DATA_W / 8; b++) begin
            new_word[b*8+:8] = wstrb_reg[b] ? write_reg[b*8+:8] : retrieved_word[b*8+:8];
          end
          cache_wr_int.bvalid = 1;
          //cache_write_line = retrieved_cache_line_synth;
          //cache_write_line[address_reg_parts.offset[OFFSET_BITS-1 : $clog2(DATA_W/8)]] = new_word;
          cache_write_line = '{default: new_word};
          writing_tag = use_address_tag_instead ? address_reg_parts.tag : retrieved_tag;
          writing_meta = '{valid: 1, dirty : 1};
          cache_write_en[address_reg_parts.offset[OFFSET_BITS-1 : $clog2(DATA_W/8)]] = 1'b1;
          cache_write_index = address_reg_parts.index;
        end
      end
      default: ;
    endcase

    //When we transition to writeback, we need to present our writeback request
    if (writeback_neccesary) begin

      memory_access_out.req_valid = 1;
      memory_access_out.req_addr = {
        dumping ? retrieved_tag : replaced_tag, replaced_index, (OFFSET_BITS)'('b0)
      };
      memory_access_out.req_write = 1;

      memory_access_out.req_wstrb = '{default: 8'hFF};
    end
  end


endmodule
