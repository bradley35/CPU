module instruction_fetch (
  input logic clk,
  input logic rst,

  //Read and advance PC
  input  double_word pc,
  input  double_word pc_next,
  output logic       pc_if_write_en,
  output double_word pc_if_write,

  //Send decoded value upstream
  output logic              output_valid,
  output logic       [31:0] instruction,
  output double_word        instruction_pc,

  //Memory access (remember this only needs to be 32 bits)
  axil_interface_if.rd_mst mem_rd,

  //Stall bit
  input logic stall,

  //Branch reset
  input  logic branch_reset_in,
  output logic branch_reset_out

);

  // initial begin
  //   if (mem_rd.DATA_W != 32) $error("IF requires 32 bit memory access");
  // end

  /* Define wires */
  typedef logic [63:0] double_word;
  //Registered
  double_word        requested_mem_addr;
  logic              requested_mem_addr_matches_pc;
  //Non-registered
  logic              output_valid_d;
  logic       [31:0] instruction_d;



  /* Assignments */
  assign requested_mem_addr_matches_pc = requested_mem_addr == pc;
  assign instruction_d                 = mem_rd.rdata;

  /* Sequential Logic */
  always_ff @(posedge clk) begin
    if (rst) begin
      output_valid     <= 0;
      branch_reset_out <= 0;
    end else begin
      if (!stall) begin
        instruction    <= instruction_d;
        instruction_pc <= pc;
        output_valid   <= output_valid_d;
        //Whatever address we requested this cycle should be remembered next cycle
      end
      requested_mem_addr <= (mem_rd.arvalid && mem_rd.arready) ? mem_rd.araddr : requested_mem_addr;
      //Always forward the branch reset
      branch_reset_out <= branch_reset_in;
    end
  end


  /* Combinational Logic */
  always_comb begin
    //Output is valid if our inputs are valid
    output_valid_d = requested_mem_addr_matches_pc && mem_rd.rvalid;

    //If we have a valid output and are not stalled, advance the pc
    pc_if_write    = (output_valid_d) ? pc + 4 : pc;
    pc_if_write_en = (pc_if_write != pc) && !stall;

    //Always request the next pc. Do it here so that it gets latched in the memory controller
    //Doesn't matter if it is ready
    (* KEEP = "TRUE" *)mem_rd.araddr  = pc_next;
    //Our request is always valid, since we need a read every cycle
    mem_rd.arvalid = 1 && !rst;
    mem_rd.rready  = 1;


  end

endmodule
