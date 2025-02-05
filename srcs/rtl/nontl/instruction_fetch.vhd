
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.register_types.all;
use work.ram_types.all;

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

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.register_types.all;
use work.ram_types.all;
use work.inst_types.all;




-- PC points to the instructions that we are grabbing right now.
-- We will always guess that PC -> PC + 1
-- Branch prediction comes later
entity instruction_fetch is
    port (
        clk   : in std_logic;
        reset : in std_logic;
        
        reg_read: in register_values;
        ram_read: out ram_read_type;
        ram_ready: in STD_LOGIC;
        ram_q: in ttbit_data;

        --If RAM read is not ready, output is not valid
        --Will not update input to next if output is not valid
        output_valid: out STD_LOGIC := '0';


        --Things to send forward
        op_out: out opcode;
        rd_imm2_out: out STD_LOGIC_VECTOR(4 downto 0);
        rs1_out: out STD_LOGIC_VECTOR(4 downto 0);
        rs2_imm1_out: out STD_LOGIC_VECTOR(11 downto 0);
        funct3_out : out funct3_options;
        funct7_out : out funct7_options;
        big_imm_out : out STD_LOGIC_VECTOR(19 downto 0)
        --immediate: out std_logic_vector(20 downto 0);
        --immediate_type: 

    );
end entity instruction_fetch;

architecture rtl of instruction_fetch is

    signal instr: STD_LOGIC_VECTOR(31 downto 0);

begin
    ram_read.enable <= '1';
    ram_read.addr <=  reg_read.pc(9 downto 0);
    process(all)
        variable instruction_temp: STD_LOGIC_VECTOR(31 downto 0);
        variable op: opcode;
        variable funct3: funct3_options;
        variable op_type: instruction_type;
        variable funct7: funct7_options;
    begin
        if rising_edge(clk) then
            if ram_ready = '1' then
                output_valid <= '1';
                instruction_temp := ram_q;
                instr <= instruction_temp;

                -- Partially decode instruction
                op:= UNDEFINED;
                for opc in opcode loop
                    if opc = UNDEFINED then
                        next;
                    end if;
                    if OPCODE_TO_BITS(opc) = instruction_temp(6 downto 0) then
                    op := opc;
                    end if;
                end loop;
                op_type := OPCODE_TO_TYPE(op);
                funct3 := UNDEFINED;
                case op_type is
                    when R | I | S | B =>
                        for f3 in funct3_options loop
                            if f3 = UNDEFINED then
                                next;
                            end if;
                            if FUNCT3_TO_BITS(op)(f3) = instruction_temp(14 downto 12) then
                                funct3 := f3;
                            end if;
                        end loop;
                    when others =>
                end case;
                funct7 := UNDEFINED;
                case funct3 is
                    when SRLI_SRAI | SRL_SRA | ADDSUB =>
                        for f7 in funct7_options loop
                            if f7 = UNDEFINED then
                                next;
                            end if;
                            if FUNCT7_TO_BITS(funct3)(f7) = instruction_temp(31 downto 24) then
                                funct7 := f7;
                            end if;
                        end loop;
                    when others =>
                end case;


                op_out <= op;
                rd_imm2_out <= instruction_temp(11 downto 7);
                rs1_out <= instruction_temp(19 downto 15);
                rs2_imm1_out <= instruction_temp(31 downto 20);
                big_imm_out <= instruction_temp(31 downto 12);
                funct3_out <= funct3;
                funct7_out <= funct7;

            else
                output_valid <= '0';
            end if;

        end if;
    end process;
    

end architecture;