package registers_types;
  typedef logic [63:0] double_word;
  typedef double_word register_table[32];

  typedef struct {
    register_table x_regs;
    double_word    pc;
  } register_holder_t;
endpackage
