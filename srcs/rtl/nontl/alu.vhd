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
        memory_is_write: out STD_LOGIC;
        result: out ttbit_data
        
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
                    when others => operation_var := ADD;
                end case;
                --All OP
                when ADDSUB => case funct7_in is
                    when ADD => operation_var := ADD;
                    when SUB => operation_var := SUB;
                    when others => operation_var := ADD;
                end case;
                when F_SLL => operation_var := LSHIFTL;
                when SLT => operation_var := LT;
                when SLTU => operation_var := LTU;
                when F_XOR => operation_var := A_XOR;
                when SRL_SRA => case funct7_in is
                    when F_SRL => operation_var := RSHIFTL;
                    when F_SRA => operation_var := RSHIFTA;
                    when others => operation_var := ADD;
                end case;
                when F_OR => operation_var := A_OR;
                when F_AND => operation_var := A_AND;

                --Others: U & J type. Do nothing on J type. On U type add.
                when LB | LH | LW | LBU | LHU | SB | SH | SW| UNDEFINED => operation_var := ADD;
            end case;
            operation <= operation_var;
            result <= (others => '0');
            case operation_var is
                when EQ => result(0) <= '1' when operand_1 = operand_2 else '0';
                when NE => result(0) <= '0' when operand_1 = operand_2 else '1';
                when LT => result(0) <= '1' when signed(operand_1) < signed(operand_2) else '0';
                when LTU => result(0) <= '1' when UNSIGNED(operand_1) < UNSIGNED(operand_2) else '0';
                when GE => result(0) <= '1' when signed(operand_1) >= signed(operand_2) else '0';
                when GEU => result(0) <= '1' when unsigned(operand_1) >= unsigned(operand_2) else '0';

                when ADD => result <= STD_LOGIC_VECTOR(signed(operand_1) + signed(operand_2));
                when SUB => result <= STD_LOGIC_VECTOR(signed(operand_1) - signed(operand_2));
                when A_XOR => result <= operand_1 xor operand_2;
                when A_OR => result <= operand_1 or operand_2;
                when A_AND => result <= operand_1 and operand_2;

                when LSHIFTL => result <= operand_1 sll to_integer(unsigned(operand_2));
                when RSHIFTL => result <= operand_1 srl to_integer(unsigned(operand_2));
                when RSHIFTA => result <= std_logic_vector(shift_right(signed(operand_1), to_integer(unsigned(operand_2))));
            
            
            end case;
        end if;

    end process;
end architecture;