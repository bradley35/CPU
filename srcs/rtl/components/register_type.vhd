library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.NUMERIC_STD.all;
use IEEE.std_logic_unsigned.all;

package register_types is

    subtype register_value_type is std_logic_vector(31 downto 0);

    type register_en_array is array (0 to 31) of std_logic;
    type register_array is array (0 to 31) of register_value_type;

    type register_values is record
        x_regs: register_array;
        pc: register_value_type;
    end record;

    type register_write is record
        x_regs_w_enable: register_en_array;
        x_regs: register_array;

        pc_w_enable: std_logic;
        pc: register_value_type;
    end record;

end package;
