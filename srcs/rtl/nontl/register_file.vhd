library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.register_types.all;

entity register_file is
    port (
        clk   : in std_logic;
        reset : in std_logic;
        
        reg_read: out register_values := (x_regs => (others => (others => '0')), pc => (others => '0'));
        reg_write: in register_write
    );
end entity;

architecture rtl of register_file is
    signal registers: register_array := (others => x"00000000");
    signal pc: register_value_type := x"00000000";
begin

    reg_read.pc <= pc;

    process(all) is
        variable val: register_value_type;
    begin
        for i in register_array'range loop
            if i = 0 then
                val := x"00000000";
            else
                val := registers(i);
            end if;
            reg_read.x_regs(i) <= val;
        end loop;

    end process;


    process(all) is
    begin
        if rising_edge(clk) then
            for i in register_array'range loop
                if reg_write.x_regs_w_enable(i) then
                    registers(i) <= reg_write.x_regs(i);
                end if;
            end loop;
            if reg_write.pc_w_enable then
                pc <= reg_write.pc;
            end if;

        end if;

    end process;

    

end architecture;