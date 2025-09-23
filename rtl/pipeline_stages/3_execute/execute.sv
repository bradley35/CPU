module execute (
  input logic clk,
  input logic rst,

  /* Latched inputs from decode */
  input logic                      input_valid,
  input logic                      thirty_two_bit_op,
  input double_word                ex_op_1,
  input double_word                ex_op_2,
  //Used for memory write, where we need to calculate an address (operand 1,2)
  //and send forward the data to store. Also used to pass through branch address
  input double_word                ex_misc_op,
  input logic                [4:0] rd,
  input load_store_variant_e       load_store_variant,
  input alu_op_e                   alu_op,
  input logic                      ex_is_memory_address,
  input logic                      ex_is_branch_address,
  input logic                      ex_is_branch_address_conditional,
  input logic                      memory_addr_is_write,
  input logic                      write_to_rd,
  input logic                      is_final_instruction,

  /* Unlatched outputs (will be latched by memory read) */
  output                      [4:0] rd_out_d,
  output double_word                result_d,
  output logic                      write_to_rd_out_d,
  output logic                      result_is_branch_addr_d,
  output logic                      result_is_valid_d,
  output double_word                operand_2_pt_d,
  output logic                      result_is_memory_addr_d,
  output logic                      out_memory_addr_is_write_d,
  output logic                      result_is_final_instruction_d,
  output load_store_variant_e       load_store_variant_out_d,


  /* Latched outputs */
  output                      [4:0] rd_out_q,
  output double_word                result_q,
  output logic                      write_to_rd_out_q,
  output logic                      result_is_branch_addr_q,
  output logic                      result_is_valid_q,
  output double_word                operand_2_pt_q,
  output logic                      result_is_memory_addr_q,
  output logic                      out_memory_addr_is_write_q,
  output logic                      result_is_final_instruction_q,
  output load_store_variant_e       load_store_variant_out_q,


  //Stall bit
  input  logic stall_in,
  output logic stall_out
);

  typedef logic [63:0] double_word;
  import instruction_decode_types::*;
  assign stall_out                     = stall_in;
  assign write_to_rd_out_d             = write_to_rd;
  assign result_is_memory_addr_d       = ex_is_memory_address;
  assign load_store_variant_out_d      = load_store_variant;
  assign rd_out_d                      = rd;
  assign result_is_valid_d             = input_valid;
  assign operand_2_pt_d                = ex_op_2;
  assign out_memory_addr_is_write_d    = memory_addr_is_write;
  assign result_is_final_instruction_d = is_final_instruction;

  always_ff @(posedge clk, posedge rst) begin
    if (rst) begin
      result_is_valid_q <= 0;
    end else if (!stall_in) begin
      rd_out_q                      <= rd_out_d;
      result_q                      <= result_d;
      write_to_rd_out_q             <= write_to_rd_out_d;
      result_is_branch_addr_q       <= result_is_branch_addr_d;
      result_is_valid_q             <= result_is_valid_d;
      operand_2_pt_q                <= operand_2_pt_d;
      result_is_memory_addr_q       <= result_is_memory_addr_d;
      out_memory_addr_is_write_q    <= out_memory_addr_is_write_d;
      result_is_final_instruction_q <= result_is_final_instruction_d;
      load_store_variant_out_q      <= load_store_variant_out_d;
    end
  end

  always_comb begin
    automatic double_word tmp_result;
    automatic double_word truncated_ex_op_1;
    automatic double_word truncated_ex_op_2;

    unique case (thirty_two_bit_op)
      'b0: begin
        truncated_ex_op_1 = ex_op_1;
        truncated_ex_op_2 = 64'(ex_op_2[5:0]);
      end
      'b1: begin
        case (alu_op)
          O_RSHIFTL: truncated_ex_op_1 = 64'(unsigned'(ex_op_1[31:0]));
          default:   truncated_ex_op_1 = 64'(signed'(ex_op_1[31:0]));
        endcase
        truncated_ex_op_2 = 64'(ex_op_2[4:0]);
      end
    endcase
    tmp_result = '0;
    unique case (alu_op)
      O_EQ:  tmp_result[0] = truncated_ex_op_1 == ex_op_2;
      O_NE:  tmp_result[0] = truncated_ex_op_1 != ex_op_2;
      O_LT:  tmp_result[0] = signed'(truncated_ex_op_1) < signed'(ex_op_2);
      O_LTU: tmp_result[0] = unsigned'(truncated_ex_op_1) < unsigned'(ex_op_2);
      O_GE:  tmp_result[0] = signed'(truncated_ex_op_1) >= signed'(ex_op_2);
      O_GEU: tmp_result[0] = unsigned'(truncated_ex_op_1) >= unsigned'(ex_op_2);

      O_ADD: tmp_result = signed'(truncated_ex_op_1) + signed'(ex_op_2);
      O_SUB: tmp_result = signed'(truncated_ex_op_1) - signed'(ex_op_2);
      O_XOR: tmp_result = truncated_ex_op_1 ^ ex_op_2;
      O_OR:  tmp_result = truncated_ex_op_1 | ex_op_2;
      O_AND: tmp_result = truncated_ex_op_1 & ex_op_2;

      O_LSHIFTL:          tmp_result = truncated_ex_op_1 << truncated_ex_op_2;
      O_RSHIFTL:          tmp_result = truncated_ex_op_1 >> truncated_ex_op_2;
      O_RSHIFTA:          tmp_result = signed'(truncated_ex_op_1) >>> truncated_ex_op_2;
      O_ADD_MISC_OP_2_PT: tmp_result = signed'(truncated_ex_op_1) + (signed'(ex_misc_op));
    endcase
    result_d = tmp_result;
    if (thirty_two_bit_op) result_d = 64'(signed'(tmp_result[31:0]));
    result_is_branch_addr_d = ex_is_branch_address;
    if (ex_is_branch_address_conditional) begin
      //Set return to the branch address (stored in the misc_op field)
      result_d                = ex_misc_op;
      result_is_branch_addr_d = tmp_result[0];

    end


  end

endmodule
