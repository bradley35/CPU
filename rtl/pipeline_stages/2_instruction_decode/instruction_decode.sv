`ifdef VIVADO
import instruction_decode_types::*;
import registers_types::register_holder_t;
`endif
module instruction_decode (

  input logic clk,
  input logic rst,



  /* Latched inputs from fetch */
  input logic              pc_output_valid,
  input logic       [31:0] instruction,
  input double_word        instruction_pc,

  /* For forwarding, latched inputs from future stages */
  //We can skip EX, since EX inputs are outputs from here
  input logic [4:0] mem_input_rd,
  input logic       mem_input_write_to_rd,
  input logic       mem_input_is_mem_addr,
  input logic       mem_output_valid_d,

  input logic [4:0] wb_input_rd,
  input logic       wb_input_write_to_rd,

  /* Latched Outputs */
  output logic                      output_valid,
  output double_word                ex_op_1,
  output double_word                ex_op_2,
  //Used for memory write, where we need to calculate an address (operand 1,2)
  //and send forward the data to store. Also used to pass through branch address
  output double_word                ex_misc_op,
  output logic                [4:0] rd,
  output quickreturn_t              operand_1_fwd,
  output quickreturn_t              operand_2_fwd,
  output load_store_variant_e       load_store_variant,
  output alu_op_e                   alu_op,
  output logic                      ex_is_memory_address,
  output logic                      ex_is_branch_address,
  output logic                      ex_is_branch_address_conditional,
  output logic                      memory_addr_is_write,
  output logic                      write_to_rd,
  output logic                      is_final_instruction,
  output logic                      thirty_two_bit_op,


  //Stall bit
  input  logic stall_in,
  output logic stall_out,

  //Register Access
  input register_holder_t register_access,

  //Branch reset
  input logic branch_reset
);
`ifndef VIVADO
  import instruction_decode_types::*;
  import registers_types::register_holder_t;
`endif


  instruction_type_e          op_type;
  opcode_e                    op;
  funct3_e                    funct3;
  funct7_e                    funct7;
  logic                [ 4:0] rd_imm2;
  logic                [ 4:0] rs1;
  logic                [11:0] rs2_imm1;
  logic                [19:0] big_imm;
  double_word                 branch_offset;
  double_word                 jump_offset;
  logic                [51:0] sign_extension;

  logic                       ex_is_memory_address_d;
  logic                       ex_is_branch_address_d;
  logic                       ex_is_branch_address_conditional_d;
  logic                       memory_addr_is_write_d;
  logic                       write_to_rd_d;
  logic                       is_final_instruction_d;
  load_store_variant_e        load_store_variant_d;
  alu_op_e                    alu_op_d;
  logic                       thirty_two_bit_op_d;

  logic                       waiting_for_branch_reset_q;
  logic                       waiting_for_branch_reset_d;
  /* Sequential Logic */
  always_ff @(posedge clk) begin
    if (rst) begin
      output_valid               <= 0;
      waiting_for_branch_reset_q <= 0;
    end else begin
      if (!stall_in) begin
        output_valid                     <= pc_output_valid && !waiting_for_branch_reset_q;
        ex_op_1                          <= operand_1_d;
        ex_op_2                          <= operand_2_d;
        ex_misc_op                       <= misc_op_d;
        rd                               <= rd_d;
        operand_1_fwd                    <= operand_1_fwd_d;
        operand_2_fwd                    <= operand_2_fwd_d;
        load_store_variant               <= load_store_variant_d;
        alu_op                           <= alu_op_d;
        ex_is_memory_address             <= ex_is_memory_address_d;
        ex_is_branch_address             <= ex_is_branch_address_d;
        ex_is_branch_address_conditional <= ex_is_branch_address_conditional_d;
        memory_addr_is_write             <= memory_addr_is_write_d;
        write_to_rd                      <= write_to_rd_d;
        is_final_instruction             <= is_final_instruction_d;
        thirty_two_bit_op                <= thirty_two_bit_op_d;
      end
      //Always accept the branch reset
      waiting_for_branch_reset_q <= waiting_for_branch_reset_d;

      if ((stall_a || stall_b) && !stall_in) begin
        //If we are asserting a stall but not recieving an upstrema one, we need to send dead instructions
        output_valid <= 0;
      end
      //MEM can stall, in which case a QRT pointing to mem should advance and a QRT pointing to WB should advance to a forwarding buffer
      if (stall_in) begin
        case (operand_1_fwd)
          ALU:     operand_1_fwd <= MEM;
          MEM:     operand_1_fwd <= WB;
          WB:      operand_1_fwd <= WB_BUF;
          default: ;
        endcase
        case (operand_2_fwd)
          ALU:     operand_2_fwd <= MEM;
          MEM:     operand_2_fwd <= WB;
          WB:      operand_2_fwd <= WB_BUF;
          default: ;
        endcase
      end
    end
  end
  /* Combination Logic */

  /* Decode Instruction */

  always_comb begin
    op      = opcode_e'(instruction[6:0]);
    op_type = OPCODE_TO_TYPE[op];
    unique case (op_type)
      R, I, S, B: funct3 = FUNCT3_FROM_BITS[op][instruction[14:12]];
      default:    funct3 = UNDEFINED_F;
    endcase
    unique case (funct3)
      SRLIW_SRAIW, SRL_SRA, SRLW_SRAW, ADDSUB, ADDSUBW:
      funct7 = FUNCT7_FROM_BITS[funct3][instruction[31:25]];
      SRLI_SRAI: funct7 = FUNCT7_FROM_BITS[funct3][{instruction[31:26], 1'b0}];
      default: funct7 = UNDEFINED_7;
    endcase

    rd_imm2 = instruction[11:7];
    rs1     = instruction[19:15];
    unique case (funct3)
      SRLI_SRAI, SLLI:    rs2_imm1 = 12'(unsigned'(instruction[25:20]));
      SRLIW_SRAIW, SLLIW: rs2_imm1 = 12'(unsigned'(instruction[24:20]));
      default:            rs2_imm1 = instruction[31:20];
    endcase

    big_imm = instruction[31:12];

    //Easy sign extension
    sign_extension = {52{instruction[31]}};
    branch_offset = {
      sign_extension[51:0], instruction[7], instruction[30:25], instruction[11:8], 1'b0
    };
    jump_offset = {
      sign_extension[51:8],
      instruction[19:12],
      instruction[20],
      instruction[30:25],
      instruction[24:21],
      1'b0
    };
  end


  always_comb begin

    unique case (funct3)
      // All Branches
      BEQ: alu_op_d = O_EQ;
      BNE: alu_op_d = O_NE;
      BLT: alu_op_d = O_LT;
      BGE: alu_op_d = O_GE;
      BLTU: alu_op_d = O_LTU;
      BGEU: alu_op_d = O_GEU;
      //All OP_IMM
      ADDI, ADDIW: alu_op_d = O_ADD;
      SLTI: alu_op_d = O_LT;
      SLTIU: alu_op_d = O_LTU;
      XORI: alu_op_d = O_XOR;
      ORI: alu_op_d = O_OR;
      ANDI: alu_op_d = O_AND;
      SLLI, SLLIW: alu_op_d = O_LSHIFTL;
      SRLI_SRAI, SRLIW_SRAIW:
      case (funct7)
        SRLI, SRLIW: alu_op_d = O_RSHIFTL;
        SRAI, SRAIW: alu_op_d = O_RSHIFTA;
        default:     alu_op_d = O_ADD;
      endcase
      //All OP
      ADDSUB, ADDSUBW:
      case (funct7)
        ADD, ADDW: alu_op_d = O_ADD;
        SUB, SUBW: alu_op_d = O_SUB;
        default:   alu_op_d = O_ADD;
      endcase

      F_SLL, F_SLLW: alu_op_d = O_LSHIFTL;
      SLT: alu_op_d = O_LT;
      SLTU: alu_op_d = O_LTU;
      F_XOR: alu_op_d = O_XOR;
      SRL_SRA, SRLW_SRAW:
      case (funct7)
        F_SRL, F_SRLW: alu_op_d = O_RSHIFTL;
        F_SRA, F_SRAW: alu_op_d = O_RSHIFTA;
        default:       alu_op_d = O_ADD;
      endcase
      F_OR: alu_op_d = O_OR;
      F_AND: alu_op_d = O_AND;
      SB, SH, SW, SD: alu_op_d = O_ADD_MISC_OP_2_PT;
      LB, LH, LW, LBU, LHU, UNDEFINED_F: alu_op_d = O_ADD;
      default: alu_op_d = O_ADD;
    endcase

    unique case (funct3)
      LWU:     load_store_variant_d = LS_LWU;
      LD, SD:  load_store_variant_d = LS_LD;
      LB, SB:  load_store_variant_d = LS_LB;
      LH, SH:  load_store_variant_d = LS_LH;
      LW, SW:  load_store_variant_d = LS_LW;
      LBU:     load_store_variant_d = LS_LBU;
      LHU:     load_store_variant_d = LS_LHU;
      default: load_store_variant_d = LS_LWU;
    endcase


    ex_is_branch_address_d             = 0;
    ex_is_branch_address_conditional_d = 0;
    write_to_rd_d                      = 1;
    ex_is_memory_address_d             = 0;
    memory_addr_is_write_d             = 0;
    is_final_instruction_d             = 0;

    unique case (op_type)
      //For R type, we just write the result back. This is the default
      R:         ;
      //For J type, we jump to the result
      J:         ex_is_branch_address_d = 1;
      //For branch, we jump if the result is 1
      B: begin
        ex_is_branch_address_d             = 1;
        ex_is_branch_address_conditional_d = 1;
        //DO NOT WRITE TO RD
        write_to_rd_d                      = 0;
      end
      //I can be either a register immediate, or a load
      I:
      unique case (op)
        JALR: begin
          ex_is_branch_address_d             = 1;
          ex_is_branch_address_conditional_d = 0;
        end
        //For load, the result is a memory address
        LOAD:    ex_is_memory_address_d = 1;
        //For fence, we indicate a cache flush by write = 1, result_is_address = 0
        MISC_MEM: begin
          write_to_rd_d = 0;
          //Only for fencei
          if (funct3 == FENCEI) begin
            memory_addr_is_write_d = 1;
            //Branch to PC + 4 (after the Fence)
            ex_is_branch_address_d = 1;
          end
        end
        //Otherwise, the default is fine
        default: ;
      endcase
      S: begin
        ex_is_memory_address_d = 1;
        write_to_rd_d          = 0;
        memory_addr_is_write_d = 1;
      end
      //Default is what we want
      U:         ;
      EXCEPTION: is_final_instruction_d = 1;

    endcase

    thirty_two_bit_op_d = op == OP_IMM_32 || op == OP_32;
  end

  /* Retrieve from register file */
  quickreturn_t       operand_1_fwd_d;
  quickreturn_t       operand_2_fwd_d;
  double_word         operand_1_d;
  double_word         operand_2_d;
  double_word         misc_op_d;
  logic         [4:0] rd_d;
  logic               stall_a;
  logic               stall_b;
  logic               stall_from_incoming_data;
  logic               stall_from_branch_completion;
  always_comb begin
    logic [4:0] operand_1_next_register = '0;
    logic [4:0] operand_2_next_register = '0;

    operand_1_fwd_d         = NONE;
    operand_2_fwd_d         = NONE;

    operand_1_d             = register_access.x_regs[rs1];
    operand_1_next_register = rs1;
    operand_2_d             = '0;
    rd_d                    = rd_imm2;
    unique case (op_type)
      // No Immediate
      // For B type instructions, we are comapring rs1 and rs2
      //Deal with modifying PC later
      R, B: begin
        operand_2_d             = register_access.x_regs[rs2_imm1[4:0]];
        operand_2_next_register = rs2_imm1[4:0];
        //This will manifest in an extra adder being created here. Seems worth the trade-off.
        misc_op_d               = instruction_pc + branch_offset;
      end
      // All immediate
      I: begin
        unique case (op)
          JALR:    operand_2_d = 64'(signed'(rs2_imm1));
          MISC_MEM: begin
            operand_1_d = 4;
            operand_2_d = instruction_pc;
          end
          default: operand_2_d = 64'(signed'(rs2_imm1));
        endcase
        //Also set operand 2 for load just in case
        misc_op_d = 64'(signed'(rs2_imm1));
      end
      // For store, we take base and add offset to produce operands. Need to let ALU know that these are for the address.

      S: begin
        misc_op_d               = 64'(signed'({rs2_imm1[11:5], rd_imm2}));

        operand_2_d             = register_access.x_regs[rs2_imm1[4:0]];
        operand_2_next_register = rs2_imm1[4:0];
      end
      U: begin
        operand_1_d             = 64'(signed'(big_imm) << 12);
        operand_1_next_register = '0;
        operand_2_d             = op == AUIPC ? instruction_pc : 0;
        operand_2_next_register = '0;
      end
      // Send the address through the ALU
      J: begin
        //Should store PC + 4
        operand_1_d             = jump_offset;
        operand_1_next_register = '0;
        operand_2_d             = instruction_pc;
        operand_1_next_register = '0;
      end
      default: begin
        // Do nothing
        operand_1_d             = '0;
        operand_1_next_register = '0;
        operand_2_d             = '0;
        operand_2_next_register = '0;
      end
    endcase




    if (operand_1_next_register > 0) begin
      //Check if either Rd is operand 1
      if (write_to_rd && output_valid && rd == operand_1_next_register) operand_1_fwd_d = ALU;
      else if (mem_input_write_to_rd && mem_input_rd == operand_1_next_register)
        operand_1_fwd_d = MEM;
      else if (wb_input_write_to_rd && wb_input_rd == operand_1_next_register) operand_1_fwd_d = WB;
    end
    if (operand_2_next_register > 0) begin
      //Check if either Rd is operand 1
      if (write_to_rd && output_valid && rd == operand_2_next_register) operand_2_fwd_d = ALU;
      else if (mem_input_write_to_rd && mem_input_rd == operand_2_next_register)
        operand_2_fwd_d = MEM;
      else if (wb_input_write_to_rd && wb_input_rd == operand_2_next_register) operand_2_fwd_d = WB;
    end

    stall_a = 0;
    if (pc_output_valid) begin
      unique case (operand_1_fwd_d)
        ALU:
        if (ex_is_memory_address) begin
          stall_a = 1;
        end
        MEM:
        if (mem_input_is_mem_addr) begin
          stall_a = !mem_output_valid_d;
        end
        default: ;
      endcase
    end
    stall_b = 0;
    if (pc_output_valid) begin
      unique case (operand_2_fwd_d)
        ALU:
        if (ex_is_memory_address) begin
          stall_b = 1;
        end
        MEM:
        if (mem_input_is_mem_addr) begin
          stall_b = !mem_output_valid_d;
        end
        default: ;
      endcase
    end
    stall_from_incoming_data = (stall_a || stall_b) && pc_output_valid;
    stall_from_branch_completion =  (waiting_for_branch_reset_q || ((ex_is_branch_address_d || ex_is_branch_address_conditional_d) && pc_output_valid)) && !branch_reset;
    waiting_for_branch_reset_d = stall_from_branch_completion && !stall_from_incoming_data && !stall_in;

    stall_out = (stall_in || stall_from_incoming_data || stall_from_branch_completion) && pc_output_valid;
  end

endmodule

