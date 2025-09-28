//For memory reads/writes, this should stall
//Otherwise, it is instant
module writeback_stage (
  input logic clk,
  input logic rst,

  input double_word       mem_result,
  input logic             mem_result_valid,
  input logic             result_is_branch_addr,
  input logic             write_to_rd,
  input logic       [4:0] rd,

  //Register Writes
  output logic       [4:0] register_to_write,
  output logic             register_write_en,
  output double_word       register_value_to_write,
  output double_word       register_value_to_write_reg,
  //Memory Writes
  //PC Writes
  output logic             pc_write_en,
  output double_word       pc_write,

  //Handling exceptions
  input  logic should_end_program,
  output logic done_executing,

  input  logic       override_buff_1,
  output double_word wb_buffer_1,
  input  logic       override_buff_2,
  output double_word wb_buffer_2
);

  typedef logic [63:0] double_word;
  always_ff @(posedge clk) begin
    if (rst) begin
      done_executing <= 0;
      wb_buffer_1    <= '0;
      wb_buffer_2    <= '0;
    end else begin
      register_value_to_write_reg <= register_value_to_write;
      done_executing              <= done_executing | (should_end_program && mem_result_valid);
      if (override_buff_1) wb_buffer_1 <= register_value_to_write_reg;
      if (override_buff_2) wb_buffer_2 <= register_value_to_write_reg;
    end
  end
  //Register writing is clocked in the register table
  always_comb begin
    register_write_en       = '0;
    register_value_to_write = '0;
    register_to_write       = '0;
    pc_write_en             = '0;
    pc_write                = '0;

    register_write_en       = write_to_rd && mem_result_valid;
    register_to_write       = rd;
    //Since there is very little logic in this step, putting in an adder does not seem like an issue
    register_value_to_write = result_is_branch_addr ? {mem_result[63:1], 1'b0} + 4 : mem_result;


    if (result_is_branch_addr) begin
      pc_write_en = 1 && mem_result_valid;
      pc_write    = {mem_result[63:1], 1'b0};
    end
  end



endmodule

