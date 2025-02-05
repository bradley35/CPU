library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.NUMERIC_STD.all;
use IEEE.std_logic_unsigned.all;


package alu_ops is

    type ALU_OP is (ADD, SUB, MULT, DIV, RSHIFTA, RSHIFTL, LSHIFTL, EQ, NE, LT, GE, LTU, GEU, A_XOR, A_OR, A_AND);

end package;