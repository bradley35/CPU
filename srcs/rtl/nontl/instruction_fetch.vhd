

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