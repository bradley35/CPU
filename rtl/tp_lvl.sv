module tp_lvl (
  input  logic       clk,
  input  logic       reset_pin,
  input  logic       rx,
  output logic       tx,
  output logic [3:0] reg_10
);

  import instruction_decode_types::*;
  logic rst;
  //Board has active-low reset
`ifdef VIVADO
  assign rst = !reset_pin;
`else
  assign rst = reset_pin;
`endif
  logic                                    program_complete;

  logic                                    pc_if_write_en;
  double_word                              pc_if_write;

  logic                                    override_pc_write_en;
  double_word                              override_pc_write;

  logic                                    reg_w_enable;
  logic                              [4:0] reg_write_entry;
  double_word                              reg_write_value;

  logic                                    dump_cache;

  logic                                    branch_reset;

  // register_table outputs
  registers_types::register_holder_t       register_table_full_table;
  double_word                              register_table_pc_next;

  registers register_table (
    .clk,
    .rst,
    .w_enable            (reg_w_enable),
    .write_entry         (reg_write_entry),
    .write_value         (reg_write_value),
    .pc_if_write_en      (pc_if_write_en),
    .pc_if_write         (pc_if_write),
    .override_pc_write_en(override_pc_write_en),
    .override_pc_write   (override_pc_write),
    .full_table          (register_table_full_table),
    .pc_next             (register_table_pc_next)
  );
  //assign reg_10 = register_table.full_table.x_regs[10][3:0];
  assign reg_10 = {
    !rx, !tx, register_table.full_table.x_regs[10][1], register_table.full_table.x_regs[10][0]
  };

  axi_interface_if main_memory_axi ();
  bulk_read_interface main_memory_bulk_interface ();


  axil_interface_if #(.DATA_W(64)) data_memory_interface ();
  axil_interface_if #(.DATA_W(64)) uart_interface ();
  axil_interface_if #(.DATA_W(64)) data_controlled_interface ();
  axil_interface_if #(.DATA_W(64)) if_memory_interface ();
  axil_interface_if #(.DATA_W(32)) x32_bit_if_memory_interface ();

  bulk_read_to_axi_adapter adapter (
    .clk,
    .rst,
    .bulk_read_in (main_memory_bulk_interface.slave),
    .axi_read_out (main_memory_axi.rd_mst),
    .axi_write_out(main_memory_axi.wr_mst)
  );

  bram_over_axi main_memory (
    .clk,
    .rst,
    .read_slv (main_memory_axi.rd_slv),
    .write_slv(main_memory_axi.wr_slv)
  );

  bulk_read_interface if_bulk_handle ();
  bulk_read_interface data_bulk_handle ();
  bulk_read_multiplexer if_data_multiplexer (
    .if_access        (if_bulk_handle.slave),
    .data_access      (data_bulk_handle.slave),
    .memory_access_out(main_memory_bulk_interface.master),
    .clk,
    .rst
  );

  memory_with_bram_cache #(
    .HAS_WRITE(0)
  ) if_cache (
    .clk,
    .rst,
    .cache_rd_int     (if_memory_interface.rd_slv),
    .cache_wr_int     (if_memory_interface.wr_slv),
    .memory_access_out(if_bulk_handle.master),
    .dump_cache

  );

  memory_with_bram_cache data_cache (
    .clk,
    .rst,
    .cache_rd_int     (data_memory_interface.rd_slv),
    .cache_wr_int     (data_memory_interface.wr_slv),
    .memory_access_out(data_bulk_handle.master),
    .dump_cache
  );



  uart_over_axi4lite uart (
    .clk,
    .rst,
`ifdef VIVADO
    .rx,
`else
    .rx          (1'b1),
`endif
    .tx,
    .read_access (uart_interface.rd_slv),
    .write_access(uart_interface.wr_slv)
  );

  memory_controller memory_controller (
    .clk,
    .rst,
    .write      (data_controlled_interface.wr_slv),
    .read       (data_controlled_interface.rd_slv),
    .cache_read (data_memory_interface.rd_mst),
    .cache_write(data_memory_interface.wr_mst),
    .uart_read  (uart_interface.rd_mst),
    .uart_write (uart_interface.wr_mst)
  );

  ttbit_adapter tt_adapter (
    .clk,
    .rst,
    .sf_out   (if_memory_interface.rd_mst),
    .sf_out_wr(if_memory_interface.wr_mst),
    .tt_in    (x32_bit_if_memory_interface.rd_slv)
  );

  /* Connections */
  logic              decode_stage_stall_out;
  logic              execute_stage_stall_out;
  logic              memory_stage_stall_out;

  logic       [63:0] execute_stage_result_q;
  logic       [ 4:0] execute_stage_rd_out_q;
  logic              execute_stage_write_to_rd_out_q;
  logic              execute_stage_result_is_valid_q;
  logic              execute_stage_result_is_memory_addr_q;

  logic       [63:0] memory_stage_result_q;
  logic              memory_stage_result_valid_d;
  logic       [ 4:0] memory_stage_rd_q;
  logic              memory_stage_write_to_rd_q;
  logic              memory_stage_result_valid_q;

  logic       [63:0] writeback_register_value_to_write_reg;
  logic       [63:0] writeback_wb_buffer_1;
  logic       [63:0] writeback_wb_buffer_2;

  // fetch_stage outputs
  logic              fetch_stage_output_valid;
  logic       [31:0] fetch_stage_instruction;
  double_word        fetch_stage_instruction_pc;
  logic              fetch_stage_branch_reset_out;
  //Step 1: Fetch Instruction
  instruction_fetch fetch_stage (
    .clk,
    .rst,
    .pc              (register_table_full_table.pc),
    .pc_next         (register_table_pc_next),
    .branch_pc       (override_pc_write),
    .pc_if_write_en,
    .pc_if_write,
    .output_valid    (fetch_stage_output_valid),
    .instruction     (fetch_stage_instruction),
    .instruction_pc  (fetch_stage_instruction_pc),
    .mem_rd          (x32_bit_if_memory_interface.rd_mst),
    .stall           (decode_stage_stall_out),
    .branch_reset_in (branch_reset),
    .branch_reset_out(fetch_stage_branch_reset_out)
  );

  // //Step 2: Decode + Register Reading

  // decode_stage outputs
  logic                      decode_stage_output_valid;
  double_word                decode_stage_ex_op_1;
  double_word                decode_stage_ex_op_2;
  double_word                decode_stage_ex_misc_op;
  logic                [4:0] decode_stage_rd;
  quickreturn_t              decode_stage_operand_1_fwd;
  quickreturn_t              decode_stage_operand_2_fwd;
  load_store_variant_e       decode_stage_load_store_variant;
  alu_op_e                   decode_stage_alu_op;
  logic                      decode_stage_ex_is_memory_address;
  logic                      decode_stage_ex_is_branch_address;
  logic                      decode_stage_ex_is_branch_address_conditional;
  logic                      decode_stage_memory_addr_is_write;
  logic                      decode_stage_write_to_rd;
  logic                      decode_stage_is_final_instruction;
  logic                      decode_stage_thirty_two_bit_op;

  instruction_decode decode_stage (
    .clk,
    .rst,
    .pc_output_valid(fetch_stage_output_valid),
    .instruction    (fetch_stage_instruction),
    .instruction_pc (fetch_stage_instruction_pc),


    .mem_input_rd         (execute_stage_rd_out_q),
    .mem_input_write_to_rd(execute_stage_write_to_rd_out_q && execute_stage_result_is_valid_q),
    .mem_input_is_mem_addr(execute_stage_result_is_memory_addr_q),
    .mem_output_valid_d   (memory_stage_result_valid_d),

    .wb_input_rd         (memory_stage_rd_q),
    .wb_input_write_to_rd(memory_stage_write_to_rd_q && memory_stage_result_valid_q),

    .output_valid(decode_stage_output_valid),
    .ex_op_1     (decode_stage_ex_op_1),
    .ex_op_2     (decode_stage_ex_op_2),

    .ex_misc_op                      (decode_stage_ex_misc_op),
    .rd                              (decode_stage_rd),
    .operand_1_fwd                   (decode_stage_operand_1_fwd),
    .operand_2_fwd                   (decode_stage_operand_2_fwd),
    .load_store_variant              (decode_stage_load_store_variant),
    .alu_op                          (decode_stage_alu_op),
    .ex_is_memory_address            (decode_stage_ex_is_memory_address),
    .ex_is_branch_address            (decode_stage_ex_is_branch_address),
    .ex_is_branch_address_conditional(decode_stage_ex_is_branch_address_conditional),
    .memory_addr_is_write            (decode_stage_memory_addr_is_write),
    .write_to_rd                     (decode_stage_write_to_rd),
    .is_final_instruction            (decode_stage_is_final_instruction),
    .thirty_two_bit_op               (decode_stage_thirty_two_bit_op),


    //Stall bit
    .stall_in (execute_stage_stall_out),
    .stall_out(decode_stage_stall_out),

    //Register Access
    .register_access(register_table_full_table),

    .branch_reset(fetch_stage.branch_reset_out)
  );

  //Step3: ALU
`ifndef VIVADO
  typedef logic [63:0] double_word;
`endif
  (* DONT_TOUCH = "TRUE" *)double_word operand_1_fast;
  (* DONT_TOUCH = "TRUE" *)double_word operand_1;
  double_word operand_2;
  always_comb begin
    case (decode_stage_operand_1_fwd)
      ALU:     operand_1 = execute_stage_result_q;
      MEM:     operand_1 = memory_stage_result_q;
      WB:      operand_1 = writeback_register_value_to_write_reg;
      WB_BUF:  operand_1 = writeback_wb_buffer_1;
      default: operand_1 = decode_stage_ex_op_1;
    endcase
    case (decode_stage_operand_1_fwd)
      ALU:     operand_1_fast = execute_stage_result_q;
      MEM:     operand_1_fast = memory_stage_result_q;
      WB:      operand_1_fast = writeback_register_value_to_write_reg;
      WB_BUF:  operand_1_fast = writeback_wb_buffer_1;
      default: operand_1_fast = decode_stage_ex_op_1;
    endcase
    case (decode_stage_operand_2_fwd)
      ALU:     operand_2 = execute_stage_result_q;
      MEM:     operand_2 = memory_stage_result_q;
      WB:      operand_2 = writeback_register_value_to_write_reg;
      WB_BUF:  operand_2 = writeback_wb_buffer_2;
      default: operand_2 = decode_stage_ex_op_2;
    endcase
  end


  // execute_stage outputs
  logic                      execute_stage_result_is_branch_addr_q;
  logic                      execute_stage_should_reset_branch;
  logic                      execute_stage_result_is_final_instruction_q;
  load_store_variant_e       execute_stage_load_store_variant_out_q;
  logic                      execute_stage_out_memory_addr_is_write_q;
  double_word                execute_stage_operand_2_pt_q;
  logic                      execute_stage_result_is_final_instruction_d;
  logic                      execute_stage_out_memory_addr_is_write_d;
  double_word                execute_stage_operand_2_pt_d;
  logic                      execute_stage_result_is_valid_d;
  logic                      execute_stage_result_is_branch_addr_d;
  logic                      execute_stage_write_to_rd_out_d;
  double_word                execute_stage_result_d;
  double_word                execute_stage_add_result;
  logic                [4:0] execute_stage_rd_out_d;
  load_store_variant_e       execute_stage_load_store_variant_out_d;
  logic                      execute_stage_result_is_memory_addr_d;



  execute execute_stage (

    .clk,
    .rst,

    /* Latched inputs from decode */
    .input_valid                     (decode_stage_output_valid),
    .thirty_two_bit_op               (decode_stage_thirty_two_bit_op),
    .ex_op_1                         (operand_1),
    .ex_op_1_fast                    (operand_1_fast),
    .ex_op_2                         (operand_2),
    //Used for memory write, where we need to calculate an address (operand 1,2)
    //and send forward the data to store. Also used to pass through branch address
    .ex_misc_op                      (decode_stage_ex_misc_op),
    .rd                              (decode_stage_rd),
    .load_store_variant              (decode_stage_load_store_variant),
    .alu_op                          (decode_stage_alu_op),
    .ex_is_memory_address            (decode_stage_ex_is_memory_address),
    .ex_is_branch_address            (decode_stage_ex_is_branch_address),
    .ex_is_branch_address_conditional(decode_stage_ex_is_branch_address_conditional),
    .memory_addr_is_write            (decode_stage_memory_addr_is_write),
    .write_to_rd                     (decode_stage_write_to_rd),
    .is_final_instruction            (decode_stage_is_final_instruction),

    /* Unlatched outputs (will be latched by memory read) */
    .rd_out_d                     (execute_stage_rd_out_d),
    .add_result                   (execute_stage_add_result),
    .result_d                     (execute_stage_result_d),
    .write_to_rd_out_d            (execute_stage_write_to_rd_out_d),
    .result_is_branch_addr_d      (execute_stage_result_is_branch_addr_d),
    .result_is_valid_d            (execute_stage_result_is_valid_d),
    .operand_2_pt_d               (execute_stage_operand_2_pt_d),
    .result_is_memory_addr_d      (execute_stage_result_is_memory_addr_d),
    .out_memory_addr_is_write_d   (execute_stage_out_memory_addr_is_write_d),
    .result_is_final_instruction_d(execute_stage_result_is_final_instruction_d),
    .load_store_variant_out_d     (execute_stage_load_store_variant_out_d),


    /* Latched outputs */
    .rd_out_q                     (execute_stage_rd_out_q),
    .result_q                     (execute_stage_result_q),
    .write_to_rd_out_q            (execute_stage_write_to_rd_out_q),
    .result_is_branch_addr_q      (execute_stage_result_is_branch_addr_q),
    .result_is_valid_q            (execute_stage_result_is_valid_q),
    .operand_2_pt_q               (execute_stage_operand_2_pt_q),
    .result_is_memory_addr_q      (execute_stage_result_is_memory_addr_q),
    .out_memory_addr_is_write_q   (execute_stage_out_memory_addr_is_write_q),
    .result_is_final_instruction_q(execute_stage_result_is_final_instruction_q),
    .load_store_variant_out_q     (execute_stage_load_store_variant_out_q),

    .should_reset_branch(execute_stage_should_reset_branch),


    //Stall bit
    .stall_in (memory_stage_stall_out),
    .stall_out(execute_stage_stall_out)

  );

  // memory_stage outputs
  logic       memory_stage_result_is_branch_addr_q;
  logic       memory_stage_should_end_program_q;
  double_word memory_stage_result_q_plus_4;
  logic       memory_stage_should_reset_branch_out;

  memoryrw memory_stage (
    .clk,
    .rst,

    //Memory addresses always come from an ADD
    .ex_result_d(execute_stage_add_result),
    .ex_result_q(execute_stage_result_q),

    .ex_op_2_pt_d(execute_stage_operand_2_pt_d),
    .ex_op_2_pt_q(execute_stage_operand_2_pt_q),

    .ex_result_valid_q(execute_stage_result_is_valid_q && !program_complete),
    .ex_result_valid_d(execute_stage_result_is_valid_d && !program_complete),

    .ex_is_branch_addr_q(execute_stage_result_is_branch_addr_q),

    .ex_is_mem_addr_q(execute_stage_result_is_memory_addr_q),
    .ex_is_mem_addr_d(execute_stage_result_is_memory_addr_d),

    .ex_mem_addr_is_write_q(execute_stage_out_memory_addr_is_write_q),
    .ex_mem_addr_is_write_d(execute_stage_out_memory_addr_is_write_d),

    .ex_write_to_rd_q       (execute_stage_write_to_rd_out_q),
    .ex_rd_q                (execute_stage_rd_out_q),
    .ex_should_end_program_q(execute_stage_result_is_final_instruction_q),

    .ex_load_store_variant_q(execute_stage_load_store_variant_out_q),
    .ex_load_store_variant_d(execute_stage_load_store_variant_out_d),

    .assert_stall(memory_stage_stall_out),
    .mem_rd      (data_controlled_interface.rd_mst),
    .mem_wr      (data_controlled_interface.wr_mst),

    .result_q(memory_stage_result_q),

    .result_q_plus_4(memory_stage_result_q_plus_4),

    .result_valid_q(memory_stage_result_valid_q),
    .result_valid_d(memory_stage_result_valid_d),

    .should_reset_branch_in (execute_stage_should_reset_branch),
    .should_reset_branch_out(memory_stage_should_reset_branch_out),

    .result_is_branch_addr_q(memory_stage_result_is_branch_addr_q),
    .write_to_rd_q          (memory_stage_write_to_rd_q),
    .rd_q                   (memory_stage_rd_q),
    .should_end_program_q   (memory_stage_should_end_program_q),
    .dump_cache
  );
  assign branch_reset = memory_stage_should_reset_branch_out && memory_stage_result_valid_q;

  writeback_stage writeback (
    .clk,
    .rst,


    .mem_result           (memory_stage_result_q),
    .mem_result_plus_4    (memory_stage_result_q_plus_4),
    .mem_result_valid     (memory_stage_result_valid_q && !program_complete),
    .result_is_branch_addr(memory_stage_result_is_branch_addr_q),
    .write_to_rd          (memory_stage_write_to_rd_q),
    .rd                   (memory_stage_rd_q),


    .register_write_en          (reg_w_enable),
    .register_to_write          (reg_write_entry),
    .register_value_to_write    (reg_write_value),
    .register_value_to_write_reg(writeback_register_value_to_write_reg),

    .pc_write_en       (override_pc_write_en),
    .pc_write          (override_pc_write),
    .should_end_program(memory_stage_should_end_program_q),
    .done_executing    (program_complete),
    .wb_buffer_1       (writeback_wb_buffer_1),
    .wb_buffer_2       (writeback_wb_buffer_2),
    .override_buff_1   (decode_stage.operand_1_fwd == WB),
    .override_buff_2   (decode_stage.operand_2_fwd == WB)
  );

endmodule
