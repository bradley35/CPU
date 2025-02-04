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