
library IEEE;
library rtl_lib;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use rtl_lib.ram_types.all;
entity TOP_LEVEL_TB is
    --  Port ( );
end entity TOP_LEVEL_TB;

architecture test of TOP_LEVEL_TB is
    signal clock : std_logic := '0';
    signal rst : std_logic := '1';
    signal finished : std_logic := '0';


begin

    TOP_LEVEL_inst: entity rtl_lib.TOP_LEVEL
     port map(
        clk => clock,
        reset => rst
    );

    clk_process:
    process begin
        if finished = '1' then
            wait;
        end if;
        clock <= '0';
        wait for 0.5 ns;
        clock <= '1';
        wait for 0.5 ns;
    end process clk_process;


    stim_process:
    process begin
        wait for 10 us;
        report "Test Done";
        finished <= '1';
        wait;
    end process;

end architecture test;