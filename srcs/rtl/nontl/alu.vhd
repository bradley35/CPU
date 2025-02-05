



library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.register_types.all;
use work.inst_types.all;
use work.ram_types.all;
use work.alu_ops.all;

entity ALU is
    port (
        clk   : in std_logic;
        reset : in std_logic;

        -- What are we operating on, and where to put result
        operand_1: in ttbit_data;
        operand_2: in ttbit_data;

        rd_in : in STD_LOGIC_VECTOR(4 downto 0);

        -- Need to figure out what the operation is
        opcode_in : in opcode;
        funct3_in : funct3_options;
        funct7_in : funct7_options;

        -- Spit out result and what to do with it
        result_is_branch: out STD_LOGIC;
        result_is_memory_address: out STD_LOGIC;
        memory_is_write: out STD_LOGIC
        
    );
end entity ALU;

architecture rtl of ALU is
    signal operation: ALU_OP;
begin

    process(all)
        variable operation_var: ALU_OP;
    begin
        if rising_edge(clk) then
            case funct3_in is
                -- All Branches
                when BEQ  => operation_var := EQ;
                when BNE  => operation_var := NE;
                when BLT  => operation_var := LT;
                when BGE  => operation_var := GE;
                when BLTU => operation_var := LTU;
                when BGEU => operation_var := GEU;
                --All OP_IMM
                when ADDI => operation_var := ADD;
                when SLTI => operation_var := LT;
                when SLTIU => operation_var := LTU;
                when XORI => operation_var := A_XOR;
                when ORI => operation_var := A_OR;
                when ANDI => operation_var := A_AND;
                when SLLI => operation_var := LSHIFTL;
                when SRLI_SRAI => case funct7_in is
                    when SRLI => operation_var := RSHIFTL;
                    when SRAI => operation_var := RSHIFTA;
                end case;
                --All OP
                when ADDSUB => case funct7_in is
                    when ADD => operation_var := ADD;
                    when SUB => operation_var := SUB;
                end case;
                when F_SLL => operation_var := LSHIFTL;
                when SLT => operation_var := LT;
                when SLTU => operation_var := LTU;
                when F_XOR => operation_var := A_XOR;
                when SRL_SRA => case funct7_in is
                    when F_SRL => operation_var := RSHIFTL;
                    when F_SRA => operation_var := RSHIFTA;
                end case;
                when F_OR => operation_var := A_OR;
                when F_AND => operation_var := A_AND;

            end case;
        end if;

    end process;
end architecture;