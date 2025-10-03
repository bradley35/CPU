package instruction_decode_types;

  typedef logic [63:0] double_word;

  typedef enum logic [2:0] {
    ALU,
    MEM,
    WB,
    WB_BUF,
    NONE
  } quickreturn_t;

  typedef enum logic [2:0] {
    LS_LB,
    LS_LH,
    LS_LW,
    LS_LBU,
    LS_LHU,
    LS_LWU,
    LS_LD
  } load_store_variant_e;

  typedef enum logic [3:0] {
    O_ADD,
    O_SUB,
    O_RSHIFTA,
    O_RSHIFTL,
    O_LSHIFTL,
    O_EQ,
    O_NE,
    O_LT,
    O_GE,
    O_LTU,
    O_GEU,
    O_XOR,
    O_OR,
    O_AND,
    O_ADD_MISC_OP_2_PT
  } alu_op_e;


  typedef enum logic [6:0] {
    UNDEFINED = 7'b0000000,
    LOAD      = 7'b0000011,
    LOAD_FP   = 7'b0000111,
    MISC_MEM  = 7'b0001111,
    OP_IMM    = 7'b0010011,
    AUIPC     = 7'b0010111,
    OP_IMM_32 = 7'b0011011,
    STORE     = 7'b0100011,
    STORE_FP  = 7'b0100111,
    AMO       = 7'b0101111,
    OP        = 7'b0110011,
    LUI       = 7'b0110111,
    OP_32     = 7'b0111011,
    MADD      = 7'b1000011,
    MSUB      = 7'b1000111,
    NMSUB     = 7'b1001111,
    NMADD     = 7'b1010011,
    OP_FP     = 7'b1010111,
    OP_V      = 7'b1011011,
    BRANCH    = 7'b1100011,
    JALR      = 7'b1100111,
    JAL       = 7'b1101111,
    SYSTEM    = 7'b1110011,
    OP_VE     = 7'b1110111,
    OPCODE_N
  } opcode_e;

  typedef enum logic [5:0] {
    BEQ,
    BNE,
    BLT,
    BGE,
    BLTU,
    BGEU,
    LB,
    LH,
    LW,
    LBU,
    LHU,
    LWU,
    LD,
    SB,
    SD,
    SH,
    SW,
    ADDI,
    ADDIW,
    SLTI,
    SLTIU,
    XORI,
    ORI,
    ANDI,
    SLLI,
    SLLIW,
    SRLI_SRAI,
    SRLIW_SRAIW,
    ADDSUB,
    ADDSUBW,
    F_SLL,
    F_SLLW,
    SLT,
    SLTU,
    F_XOR,
    SRL_SRA,
    SRLW_SRAW,
    F_OR,
    F_AND,
    FENCE,
    FENCEI,
    F_JALR,
    UNDEFINED_F,
    FUNCT3_N
  } funct3_e;

  // Row = map from bits to funct3_e
  typedef funct3_e funct3_row_t[8];

  // Table = map from opcode to a row
  typedef funct3_row_t funct3_table_t[OPCODE_N];

  localparam funct3_row_t ROW_UNDEF = funct3_row_t'{default: UNDEFINED_F};

  localparam funct3_row_t ROW_BRANCH = '{
      3'b000: BEQ,
      3'b001: BNE,
      3'b100: BLT,
      3'b101: BGE,
      3'b110: BLTU,
      3'b111: BGEU,
      default: UNDEFINED_F
  };

  localparam funct3_row_t ROW_LOAD = '{
      3'b000: LB,
      3'b001: LH,
      3'b010: LW,
      3'b100: LBU,
      3'b101: LHU,
      3'b110: LWU,
      3'b011: LD,
      default: UNDEFINED_F
  };

  localparam funct3_row_t ROW_STORE = '{
      3'b000: SB,
      3'b001: SH,
      3'b010: SW,
      3'b011: SD,
      default: UNDEFINED_F
  };

  localparam funct3_row_t ROW_OP_IMM = '{
      3'b000: ADDI,
      3'b010: SLTI,
      3'b011: SLTIU,
      3'b100: XORI,
      3'b110: ORI,
      3'b111: ANDI,
      3'b001: SLLI,
      3'b101: SRLI_SRAI,
      default: UNDEFINED_F
  };

  localparam funct3_row_t ROW_OP_IMM_32 = '{
      3'b000: ADDIW,
      3'b001: SLLIW,
      3'b101: SRLIW_SRAIW,
      default: UNDEFINED_F
  };

  localparam funct3_row_t ROW_OP = '{
      3'b000: ADDSUB,
      3'b001: F_SLL,
      3'b010: SLT,
      3'b011: SLTU,
      3'b100: F_XOR,
      3'b101: SRL_SRA,
      3'b110: F_OR,
      3'b111: F_AND,
      default: UNDEFINED_F
  };

  localparam funct3_row_t ROW_OP_32 = '{
      3'b000: ADDSUBW,
      3'b001: F_SLLW,
      3'b101: SRLW_SRAW,
      default: UNDEFINED_F
  };

  localparam funct3_row_t ROW_MISC_MEM = '{3'b001: FENCEI, 3'b000: FENCE, default: UNDEFINED_F};
  localparam funct3_row_t ROW_JALR = '{default: F_JALR};

  localparam funct3_table_t FUNCT3_FROM_BITS = '{
      BRANCH   : ROW_BRANCH,
      LOAD     : ROW_LOAD,
      STORE    : ROW_STORE,
      OP_IMM   : ROW_OP_IMM,
      OP_IMM_32: ROW_OP_IMM_32,
      OP       : ROW_OP,
      OP_32    : ROW_OP_32,
      MISC_MEM : ROW_MISC_MEM,
      JALR: ROW_JALR,
      default: ROW_UNDEF
  };

  typedef enum logic [2:0] {
    R,
    I,
    S,
    B,
    U,
    J,
    EXCEPTION
  } instruction_type_e;

  localparam instruction_type_e OPCODE_TO_TYPE[OPCODE_N] = '{
      LOAD : I,
      LOAD_FP : I,
      MISC_MEM : I,
      OP_IMM : I,
      AUIPC : U,
      OP_IMM_32 : I,
      STORE : S,
      STORE_FP : S,
      AMO : R,
      OP : R,
      LUI : U,
      OP_32 : R,
      MADD : R,
      MSUB : R,
      NMSUB : R,
      NMADD : R,
      OP_FP : R,
      OP_V : R,
      BRANCH : B,  // Changed from S to B type
      JALR : I,
      JAL : J,  // Changed from U to J type
      SYSTEM : EXCEPTION,  // These will end the program for now
      OP_VE : R,
      UNDEFINED: R,
      default: R
  };

  typedef enum logic [3:0] {
    SRLI,
    SRLIW,
    SRAI,
    SRAIW,
    ADD,
    SUB,
    ADDW,
    SUBW,
    F_SRL,
    F_SRLW,
    F_SRA,
    F_SRAW,
    UNDEFINED_7
  } funct7_e;

  typedef funct7_e funct7_row_t[128];
  typedef funct7_row_t funct7_table_t[FUNCT3_N];

  localparam funct7_row_t ROW7_UNDEF = funct7_row_t'{default: UNDEFINED_7};

  localparam funct7_row_t ROW7_SRLI_SRAI = '{
      7'b0000000: SRLI,
      7'b0100000: SRAI,
      default: UNDEFINED_7
  };

  localparam funct7_row_t ROW7_SRLIW_SRAIW = '{
      7'b0000000: SRLIW,
      7'b0100000: SRAIW,
      default: UNDEFINED_7
  };

  localparam funct7_row_t ROW7_ADDSUB = '{7'b0000000: ADD, 7'b0100000: SUB, default: UNDEFINED_7};

  localparam funct7_row_t ROW7_ADDSUBW = '{
      7'b0000000: ADDW,
      7'b0100000: SUBW,
      default: UNDEFINED_7
  };

  localparam funct7_row_t ROW7_SRL_SRA = '{
      7'b0000000: F_SRL,
      7'b0100000: F_SRA,
      default: UNDEFINED_7
  };

  localparam funct7_row_t ROW7_SRLW_SRAW = '{
      7'b0000000: F_SRLW,
      7'b0100000: F_SRAW,
      default: UNDEFINED_7
  };

  localparam funct7_table_t FUNCT7_FROM_BITS = '{
      SRLI_SRAI   : ROW7_SRLI_SRAI,
      SRLIW_SRAIW : ROW7_SRLIW_SRAIW,
      ADDSUB      : ROW7_ADDSUB,
      ADDSUBW     : ROW7_ADDSUBW,
      SRL_SRA     : ROW7_SRL_SRA,
      SRLW_SRAW   : ROW7_SRLW_SRAW,
      default: ROW7_UNDEF
  };

endpackage
