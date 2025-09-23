module registers (
  input logic             clk,
  input logic             rst,
  input logic             w_enable,
  input             [4:0] write_entry,
  input double_word       write_value,
  input logic             pc_if_write_en,
  input double_word       pc_if_write,
  input logic             override_pc_write_en,
  input double_word       override_pc_write,

  output register_holder_t full_table,
  output double_word       pc_next

);

  import registers_types::*;


  double_word register_storage[32];
  double_word pc_storage;

  assign full_table = '{x_regs: register_storage, pc: pc_storage};

  always_ff @(posedge clk, posedge rst) begin : reg_loop
    if (rst) begin
      register_storage <= '{default: '0};
      pc_storage       <= '0;
    end else begin
      if (w_enable) begin
        if (write_entry > 0) register_storage[write_entry] <= write_value;
      end
      pc_storage <= pc_next;
    end
  end

  always_comb begin
    case ({
      pc_if_write_en, override_pc_write_en
    })
      'b10:       pc_next = pc_if_write;
      'b01, 'b11: pc_next = override_pc_write;
      default:    pc_next = pc_storage;
    endcase
  end

endmodule
