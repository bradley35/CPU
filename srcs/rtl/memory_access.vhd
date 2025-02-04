library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.NUMERIC_STD.all;
use IEEE.std_logic_unsigned.all;


--This has 18kb of RAM

package ram_types is

    subtype ram_addr is std_logic_vector(11 downto 0);
    subtype sfbit_data is std_logic_vector(63 downto 0);

    type ram_write_type is record
        enable: std_logic;
        addr: ram_addr;
        data: sfbit_data;
    end record;
    type ram_read_type is record
        enable: std_logic;
        addr: ram_addr;
    end record;
end package;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.NUMERIC_STD.all;
use IEEE.std_logic_unsigned.all;
use work.ram_types.all;

--Read and write 64 bits
entity block_ram is Port(
    clk: in std_logic;
    ram_write: in ram_write_type;  
    ram_read: in ram_read_type;
    ram_q : out sfbit_data
);
end block_ram;

architecture syn of block_ram is
    type ram_type is array (0 to 287) of sfbit_data;

    signal RAM: ram_type := (others => x"0000000000000000");

begin
    process(all)
    begin
        if rising_edge(clk) then
            if ram_write.enable = '1' then
                RAM(conv_integer(ram_write.addr)) <= ram_write.data;
            end if;
            
            if ram_read.enable = '1' then
                ram_q <= RAM(conv_integer(ram_read.addr));
            end if;
        end if;
    end process;
end architecture syn;
