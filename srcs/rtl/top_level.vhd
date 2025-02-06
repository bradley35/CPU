library IEEE;
library rtl_lib;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use rtl_lib.ram_types.all;
use rtl_lib.ram_handler_types.all;
use rtl_lib.register_types.all;
use rtl_lib.inst_types.all;
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
    
    signal fetch_valid: STD_LOGIC;
    signal fetch_op_out: opcode;
    signal fetch_rd_imm2_out: STD_LOGIC_VECTOR(4 downto 0);
    signal fetch_rs1_out: STD_LOGIC_VECTOR(4 downto 0);
    signal fetch_rs2_imm1_out: STD_LOGIC_VECTOR(11 downto 0);
    signal fetch_big_imm_out: STD_LOGIC_VECTOR(19 downto 0);
    signal fetch_func3_out: funct3_options;
    signal fetch_func7_out: funct7_options;

    signal reg_out_operand_1: ttbit_data;
    signal reg_out_operand_2: ttbit_data;
    signal reg_rd_out:  STD_LOGIC_VECTOR(4 downto 0);
    signal reg_opcode_out: opcode;
    signal reg_funct3_out : funct3_options;
    signal reg_funct7_out: funct7_options;

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

    -- STEP 1 in pipeline: Grab instruction

    instruction_fetch_inst: entity rtl_lib.instruction_fetch
     port map(
        clk => clk,
        reset => reset,
        reg_read => reg_read,
        ram_read => ram_access_requests(0),
        ram_ready => ram_access_readies(0),
        ram_q => ram_qs(0),
        output_valid => fetch_valid,
        op_out => fetch_op_out,
        rd_imm2_out => fetch_rd_imm2_out,
        rs1_out => fetch_rs1_out,
        rs2_imm1_out => fetch_rs2_imm1_out,
        big_imm_out => fetch_big_imm_out,
        funct3_out => fetch_func3_out,
        funct7_out => fetch_func7_out
    );

    -- STEP 2 in pipeline: Registers
    
    register_read_imm_inst: entity work.register_read_imm
        port map(
        clk => clk,
        input_is_valid => fetch_valid,
        reset => reset,
        opcd => fetch_op_out,
        reg_read => reg_read,
        rd_imm2_in => fetch_rd_imm2_out,
        rs1_in => fetch_rs1_out,
        rs2_imm1_in => fetch_rs2_imm1_out,
        funct3_in => fetch_func3_out,
        funct7_in => fetch_func7_out,
        big_imm_in => fetch_big_imm_out,
        operand_1 => reg_out_operand_1,
        operand_2 => reg_out_operand_2,
        rd_out => reg_rd_out,
        opcode_out => reg_opcode_out,
        funct3_out => reg_funct3_out,
        funct7_out => reg_funct7_out
    );


    -- STEP 3 in pipeline: ALU


    ALU_inst: entity work.ALU
     port map(
        clk => clk,
        reset => reset,
        operand_1 => reg_out_operand_1,
        operand_2 => reg_out_operand_2,
        rd_in => reg_rd_out,
        opcode_in => reg_opcode_out,
        funct3_in => reg_funct3_out,
        funct7_in => reg_funct7_out,
        result_is_branch => open,
        result_is_memory_address => open,
        memory_is_write => open,
        result => open
    );

end architecture;