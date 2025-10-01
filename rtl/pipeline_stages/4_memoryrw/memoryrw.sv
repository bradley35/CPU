module memoryrw (
  input logic clk,
  input logic rst,

  /* Latched Ex interface */
  input double_word                ex_result_q,
  input logic                      ex_result_valid_q,
  input logic                      ex_is_branch_addr_q,
  input logic                      ex_is_mem_addr_q,
  input logic                      ex_mem_addr_is_write_q,
  input logic                      ex_write_to_rd_q,
  input logic                [4:0] ex_rd_q,
  input load_store_variant_e       ex_load_store_variant_q,
  input logic                      ex_should_end_program_q,

  /* Unlatched interface (for quicker memory access) */
  input double_word          ex_result_d,
  input double_word          ex_op_2_pt_d,
  input logic                ex_result_valid_d,
  input logic                ex_is_mem_addr_d,
  input logic                ex_mem_addr_is_write_d,
  input load_store_variant_e ex_load_store_variant_d,

  /* Outputs to Writeback Stage */

  output double_word       result_q,
  output double_word       result_q_plus_4,
  output logic             result_valid_q,
  output logic             result_is_branch_addr_q,
  output logic             write_to_rd_q,
  output logic       [4:0] rd_q,
  output logic             should_end_program_q,

  //Used so that decode can tell if it will need to wait
  output logic result_valid_d,

  /* Branch Invalidate PT */

  input  logic should_reset_branch_in,
  output logic should_reset_branch_out,

  /* Stall Chain */
  output logic assert_stall,



  /* Memory Access */
         axil_interface_if.wr_mst mem_wr,
         axil_interface_if.rd_mst mem_rd,
  output logic                    dump_cache



);
  import instruction_decode_types::*;
  logic       accepting_alu_result;


  double_word raw_result_next;
  double_word trunc_result_next;

  logic       previous_aw_accept;

  assign assert_stall = !accepting_alu_result;
  //LOGIC: Whatever is in the ALU out flip-flop is what we are currently working on (have accepted)
  always_ff @(posedge clk) begin
    if (rst) begin
      result_valid_q          <= 0;
      should_reset_branch_out <= 0;
    end else begin
      result_q                <= ex_is_mem_addr_q ? trunc_result_next : raw_result_next;
      result_q_plus_4         <= {raw_result_next[63:1], 1'b0} + 4;
      result_valid_q          <= result_valid_d;
      result_is_branch_addr_q <= ex_is_branch_addr_q;
      write_to_rd_q           <= ex_write_to_rd_q;
      rd_q                    <= ex_rd_q;
      should_end_program_q    <= ex_should_end_program_q;
      should_reset_branch_out <= should_reset_branch_in && result_valid_d;
      //If the AW was accepted without the W, we need to remember
      previous_aw_accept      <= mem_wr.wready ? (previous_aw_accept | mem_wr.awready) : 0;
    end
  end



  always_comb begin
    logic [2:0] offset = ex_result_q[2:0];
    mem_rd.rready  = 1;
    mem_wr.bready  = 1;

    //Pass the ALU result_q directly (unflopped) to the memory controller
    //Only accept when we are ready
    mem_rd.araddr  = '0;
    mem_rd.arvalid = '0;
    mem_wr.awaddr  = '0;
    mem_wr.awvalid = '0;
    mem_wr.wvalid  = '0;
    mem_wr.wstrb   = '0;
    mem_wr.wdata   = '0;

    if (ex_is_mem_addr_d && ex_result_valid_d) begin
      automatic logic [2:0] offset_next = ex_result_d[2:0];
      mem_rd.araddr  = ex_result_d & 'b1111111111111111111111111111111111111111111111111111111111111000;
      mem_wr.awaddr  = ex_result_d & 'b1111111111111111111111111111111111111111111111111111111111111000;
      //If we are about to branch, kill the request
      mem_rd.arvalid = (!ex_mem_addr_is_write_d);
      mem_wr.awvalid = (ex_mem_addr_is_write_d);
      mem_wr.wvalid = mem_wr.awvalid;

      //Need to offset this by the offset within the 64 bit
      mem_wr.wdata = ex_op_2_pt_d << (offset_next * 8);
      case (ex_load_store_variant_d)
        LS_LB:   mem_wr.wstrb = 'b00000001 << offset_next;
        LS_LH:   mem_wr.wstrb = 'b00000011 << offset_next;
        LS_LW:   mem_wr.wstrb = 'b00001111 << offset_next;
        LS_LD:   mem_wr.wstrb = 'b11111111 << offset_next;
        default: ;
      endcase

      accepting_alu_result = ex_mem_addr_is_write_d ? ((mem_wr.awready || previous_aw_accept) && mem_wr.wready) : mem_rd.arready;//(mem_interface.req_valid && mem_interface.req_ready);
    end else begin

      mem_rd.arvalid = 0;
      mem_wr.awvalid = 0;
      accepting_alu_result = mem_rd.rvalid || !ex_is_mem_addr_q || !ex_result_valid_q
   || ex_mem_addr_is_write_q;
    end

    if (!ex_is_mem_addr_q && ex_mem_addr_is_write_q) dump_cache = 1;
    else dump_cache = 0;
    result_valid_d  = ex_is_mem_addr_q ? mem_rd.rvalid : ex_result_valid_q;
    // if (ex_is_mem_addr_q)
    //   $display(
    //       "Offset is: %d, going from %h to %h",
    //       offset,
    //       mem_interface.resp_rdata,
    //       mem_interface.resp_rdata >> (offset * 8)
    //   );
    raw_result_next = ex_is_mem_addr_q ? mem_rd.rdata >> (offset * 8) : ex_result_q;
    case (ex_load_store_variant_q)
      LS_LB:   trunc_result_next = 64'(signed'(raw_result_next[7:0]));
      LS_LH:   trunc_result_next = 64'(signed'(raw_result_next[15:0]));
      LS_LW:   trunc_result_next = 64'(signed'(raw_result_next[31:0]));
      LS_LBU:  trunc_result_next = 64'(unsigned'(raw_result_next[7:0]));
      LS_LHU:  trunc_result_next = 64'(unsigned'(raw_result_next[15:0]));
      LS_LWU:  trunc_result_next = 64'(unsigned'(raw_result_next[31:0]));
      LS_LD:   trunc_result_next = raw_result_next;
      default: trunc_result_next = raw_result_next;
    endcase

    //For stores, send the store address though in 
  end

endmodule
