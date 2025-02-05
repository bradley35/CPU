library IEEE;
library rtl_lib;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use rtl_lib.ram_types.all;
use rtl_lib.ram_handler_types.all;
use rtl_lib.register_types.all;
entity TOP_LEVEL is PORT(
    clk   : in std_logic;
    reset : in std_logic
);
end entity TOP_LEVEL;

architecture rtl of TOP_LEVEL is

    signal ram_write: ram_write_type;
    signal ram_read: ram_read_type;
    signal ram_q: ttbit_data := (others => '0');
    
    signal ram_access_requests:ram_requests;
    signal ram_access_readies:STD_LOGIC_VECTOR(0 to 1) := "00";
    signal ram_qs: ram_responses := (others => (others => '0'));

    signal reg_read: register_values;
    signal reg_write: register_write;
    


begin

    ram_write.enable <= '0';
    ram_access_requests(1).enable <= '0';
    ram_access_requests(1).addr <= (others => '0');

    register_file_inst: entity rtl_lib.register_file
     port map(
        clk => clk,
        reset => reset,
        reg_read => reg_read,
        reg_write => reg_write
    );


    MainRam_inst: entity rtl_lib.MainRam
     port map(
        clk => clk,
        ram_write => ram_write,
        ram_read => ram_read,
        ram_q => ram_q
    );


    RAMHandler_inst: entity rtl_lib.RAMHandler
     port map(
        clk => clk,
        ram_write => ram_write,
        ram_read => ram_read,
        ram_q => ram_q,
        ram_access_requests => ram_access_requests,
        ram_access_readies => ram_access_readies,
        ram_qs => ram_qs
    );

    instruction_fetch_inst: entity rtl_lib.instruction_fetch
     port map(
        clk => clk,
        reset => reset,
        reg_read => reg_read,
        ram_read => ram_access_requests(0),
        ram_ready => ram_access_readies(0),
        ram_q => ram_qs(0),
        output_valid => open,
        op_out => open,
        rd_out => open,
        rs1_out => open,
        rs2_out => open
    );
    

end architecture;