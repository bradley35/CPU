library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.register_types.all;
use work.inst_types.all;
use work.ram_types.all;

entity register_read_imm is
    port (
        clk   : in std_logic;
        reset : in std_logic;
        opcode: in opcode;
        reg_red: in register_values;
        rd_imm2_in: in STD_LOGIC_VECTOR(4 downto 0);
        rs1_in: in STD_LOGIC_VECTOR(4 downto 0);
        rs2_imm1_in: in STD_LOGIC_VECTOR(11 downto 0);
        funct3_in : in funct3_options;
        funct7_in : in funct7_options;
        big_imm_in : in STD_LOGIC_VECTOR(19 downto 0);




        operand_1: out ttbit_data;
        operand_2: out ttbit_data
    );
end entity register_read_imm;

architecture rtl of register_read_imm is
   
begin

    process(all)
        variable temporary_cat: STD_LOGIC_VECTOR(11 downto 0);
    begin
    -- GRAB rs1
    if rising_edge(clk) then
        -- GRAB rs1    
        operand_1 <= reg_red.x_regs(to_integer(unsigned(rs1_in)));

        case OPCODE_TO_TYPE(opcode) is
            when R | B => 
                -- No Immediate
                -- For B type instructions, we are comapring rs1 and rs2

                --Deal with modifying PC later
                operand_2 <= reg_red.x_regs(to_integer(unsigned(rs2_imm1_in(4 downto 0))));
            when I =>
                -- All immediate
                operand_2 <= STD_ULOGIC_VECTOR(resize(signed(rs2_imm1_in), 32));
            when S =>
                -- For store, we take base and add offset to produce operands. Need to let ALU know that these are for the address.
                temporary_cat := rs2_imm1_in(11 downto 5) & rd_imm2_in;
                operand_2 <= STD_ULOGIC_VECTOR(resize(signed(temporary_cat), 32));
            when U =>
                -- Take 0 into operand 2. Add 0 to it.
                operand_1 <= STD_ULOGIC_VECTOR(resize(signed(big_imm_in), 32));
                operand_2 <= STD_ULOGIC_VECTOR(to_signed(0, 32));
            when J =>
                -- No need to use ALU
                -- Just make sure to write back the result of the jump
                
        end case;

    end if;

    end process;



    -- Check if rs2 is immediate, if so sign extend, if not grab rs2

    -- hand results to ALU
    

end architecture;