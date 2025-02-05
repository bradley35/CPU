library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.NUMERIC_STD.all;
use IEEE.std_logic_unsigned.all;
use work.ram_types.all;
use std.textio.all;

entity MainRam is Port (
    clk: in std_logic;
    ram_write: in ram_write_type;  
    ram_read: in ram_read_type;
    ram_q : out ttbit_data
);
end MainRam;

architecture rtl of MainRam is

    impure function InitRamFromFile(RamFileName: in string) return ram_type is
            type chat_file_t is file of CHARACTER;
            file RamFile: chat_file_t OPEN READ_MODE is RamFileName;
            variable TempByte: character;
            variable TempVector: STD_ULOGIC_VECTOR(ttbit_data'length - 1 downto 0);
            variable RAM: ram_type;
            variable BytesPerWord: integer;
    begin
        RAM := (others => (others => '0'));
        BytesPerWord := ttbit_Data'length/8;
        for I in ram_type'range loop
            if not endfile(RamFile) then
                TempVector := (others => '0');
                for B in 0 to BytesPerWord - 1 loop
                    if not endfile(RamFile) then
                        read(RamFile, TempByte);
                        TempVector((B + 1) * 8 - 1 downto B*8) := STD_LOGIC_VECTOR(to_unsigned(character'pos(TempByte), 8));
                    else
                        exit;
                    end if;
                end loop;
                RAM(I) := TempVector;
                
            else
                exit;
            end if;
        end loop;
        return RAM;
    end function;


begin

    comp: entity work.block_ram
     generic map(
        InitialValue => InitRamFromFile("/home/bradley/Desktop/Shared/DebianVMSharedDirectory/CPU/srcs/hex/program.hex")
    )
     port map(
        clk => clk,
        ram_write => ram_write,
        ram_read => ram_read,
        ram_q => ram_q
    );

end architecture rtl;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.NUMERIC_STD.all;
use IEEE.std_logic_unsigned.all;
use work.ram_types.all;
use std.textio.all;

package ram_handler_types is
    -- Requests can come from 2 places at the moment
    type ram_requests is array(0 to 1) of ram_read_type;
    type ram_responses is array(0 to 1) of ttbit_data;
end package;


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.NUMERIC_STD.all;
use IEEE.std_logic_unsigned.all;
use work.ram_types.all;
use std.textio.all;
use work.ram_handler_types.all;

entity RAMHandler is Port (
    clk: in std_logic;
    
    -- Connection to RAM instance
    
    ram_write: out ram_write_type;  
    ram_read: out ram_read_type;
    ram_q : in ttbit_data;

    -- Handler Portions

    ram_access_requests: in ram_requests;
    ram_access_readies: out STD_LOGIC_VECTOR(0 to 1);
    ram_qs: out ram_responses

);

end entity RAMHandler;


-- Currently assumes that RAM access is instant, but only 1 at a time. Will need to update architecture
-- when that is no longer the case
architecture rtl of RAMHandler is

    type adds_arr is array(0 to 1) of ram_addr;
    type vals_arr is array(0 to 1) of ttbit_data;

    signal loaded_ram_adds: adds_arr;
    signal loaded_adds_is_ready: STD_LOGIC_VECTOR(0 to 1);
    signal loaded_ram_vals: vals_arr;

    signal currently_loading: natural range 0 to 1;
    signal is_currently_loading: std_logic;

begin
    

    process(all)

        variable loaded_and_ready: STD_LOGIC_VECTOR(0 to 1);

    begin


        for i in loaded_adds_is_ready'range loop
            ram_qs(i) <= loaded_ram_vals(i);
        end loop;

        -- First check if it is ready and immediately return if so
        for i in loaded_adds_is_ready'range loop
            if loaded_adds_is_ready(i) = '1' and loaded_ram_adds(i) = ram_access_requests(i).addr then
                -- Set that it is ready
                loaded_and_ready(i) := '1';
            else
                loaded_and_ready(i) := '0';
                
            end if;
            ram_access_readies(i) <= loaded_and_ready(i);
        end loop;
 
 
        -- Find the first one that isn't ready and grab that one. DO NOT UPDATE signals until clock edge!!!!
        is_currently_loading <= '0';
        for i in loaded_adds_is_ready'range loop
            if loaded_and_ready(i) = '0' and ram_access_requests(i).enable = '1' then
                ram_access_readies(i) <= '1';
                ram_read <= ram_access_requests(i);
                ram_qs(i) <= ram_q;

                currently_loading <= i;
                is_currently_loading <= '1';
                exit;
            end if;
        end loop;


        if rising_edge(clk) then
            -- Check if anything is currently loading, and if so update the signals
            if is_currently_loading = '1' then
                loaded_ram_adds(currently_loading) <= ram_read.addr;
                loaded_adds_is_ready(currently_loading) <= '1';
                loaded_ram_vals(currently_loading) <= ram_q;
            end if;
        end if;
    end process;
end architecture;