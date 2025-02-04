library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.register_types.all;

entity instruction_fetch is
    port (
        clk   : in std_logic;
        reset : in std_logic;
        
        reg_read: in register_values
       -- ram_read

    );
end entity instruction_fetch;

architecture rtl of instruction_fetch is

    signal instr: STD_LOGIC_VECTOR(31 downto 0);
begin

    process(all) begin
        if rising_edge(clk) then
            --instr <= 
        
        end if;
    end process;
    

end architecture;