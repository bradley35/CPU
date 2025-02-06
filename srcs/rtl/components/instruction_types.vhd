
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package inst_types is
    type opcode is (LOAD, LOAD_FP, MISC_MEM, OP_IMM, AUIPC, OP_IMM_32,
        STORE, STORE_FP, AMO, OP, LUI, OP_32,
        MADD, MSUB, NMSUB, NMADD, OP_FP, OP_V,
        BRANCH, JALR, JAL, SYSTEM, OP_VE, UNDEFINED);
    
    type opcode_to_bits_map is array (opcode) of std_logic_vector(6 downto 0);
    constant OPCODE_TO_BITS: opcode_to_bits_map := (
        LOAD => "0000011",
        LOAD_FP => "0000111",
        MISC_MEM => "0001111",
        OP_IMM => "0010011",
        AUIPC => "0010111",
        OP_IMM_32 => "0011011",
        STORE => "0100011",
        STORE_FP => "0100111",
        AMO => "0101111",
        OP => "0110011",
        LUI => "0110111",
        OP_32 => "0111011",
        MADD => "1000011",
        MSUB => "1000111",
        NMSUB => "1001111",
        NMADD => "1010011",
        OP_FP => "1010111",
        OP_V => "1011011",
        BRANCH => "1100011",
        JALR => "1100111",
        JAL => "1101111",
        SYSTEM => "1110011",
        OP_VE => "1110111",
        UNDEFINED => "0000000"
    );

    type funct3_options is (BEQ, BNE, BLT, BGE, BLTU, BGEU, LB, LH, LW, LBU, LHU, SB, SH, SW, ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI_SRAI, ADDSUB, F_SLL, SLT, SLTU, F_XOR, SRL_SRA, F_OR, F_AND, UNDEFINED);
    
    type funct3_to_bits_map is array (funct3_options) of std_logic_vector(2 downto 0);
    type opc_func3_to_bits_map is array(opcode) of funct3_to_bits_map;
    constant FUNCT3_TO_BITS: opc_func3_to_bits_map := (
        BRANCH => (
            BEQ    => "000",
            BNE    => "001",
            BLT    => "100",
            BGE    => "101",
            BLTU   => "110",
            BGEU   => "111",
            others => "UUU"
        ),
        LOAD => (
            LB     => "000",
            LH     => "001",
            LW     => "010",
            LBU    => "100",
            LHU    => "101",
            others => "UUU"
        ),
        STORE => (
            SB     => "000",
            SH     => "001",
            SW     => "010",
            others => "UUU"
        ),
        OP_IMM => (
            ADDI      => "000",
            SLTI      => "010",
            SLTIU     => "011",
            XORI      => "100",
            ORI       => "110",
            ANDI      => "111",
            SLLI      => "001",
            SRLI_SRAI => "101",
            others    => "UUU"
        ),
        OP => (
            ADDSUB    => "000",
            F_SLL     => "001",
            SLT       => "010",
            SLTU      => "011",
            F_XOR     => "100",
            SRL_SRA   => "101",
            F_OR      => "110",
            F_AND     => "111",
            others    => "UUU"
        ),
        others => (
            others => "000"
        )
    );

    type instruction_type is (R, I, S, B, U, J);  -- Added B and J types
    type instruction_type_map is array(opcode) of instruction_type;

    constant OPCODE_TO_TYPE: instruction_type_map := (
        LOAD => I,
        LOAD_FP => I,
        MISC_MEM => I,
        OP_IMM => I,
        AUIPC => U,
        OP_IMM_32 => I,
        STORE => S,
        STORE_FP => S,
        AMO => R,
        OP => R,
        LUI => U,
        OP_32 => R,
        MADD => R,
        MSUB => R,
        NMSUB => R,
        NMADD => R,
        OP_FP => R,
        OP_V => R,
        BRANCH => B,    -- Changed from S to B type
        JALR => I,
        JAL => J,       -- Changed from U to J type
        SYSTEM => I,
        OP_VE => R,
        UNDEFINED => R
    );

    type funct7_options is (SRLI, SRAI, ADD, SUB, F_SRL, F_SRA, UNDEFINED);
    type funct7_to_bits_map is array(funct7_options) of std_logic_vector(6 downto 0);
    type func3_func7_to_bits_map is array(funct3_options) of funct7_to_bits_map;

    CONSTANT FUNCT7_TO_BITS: func3_func7_to_bits_map := (
        SRLI_SRAI => (
            SRLI   => "0000000",
            SRAI   => "0100000",
            others => "UUUUUUU"
        ),
        ADDSUB => (
            ADD    => "0000000",
            SUB    => "0100000",
            others => "UUUUUUU"
        ),
        SRL_SRA => (
            F_SRL  => "0000000",
            F_SRA  => "0100000",
            others => "UUUUUUU"
        ),
        others => (
            others => "UUUUUUU"
        )
    );
end package;


