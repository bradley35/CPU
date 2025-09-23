interface bulk_read_interface #(
  parameter DATA_W    = 64,
  parameter ADDR_W    = 64,
  parameter LINE_SIZE = 16

) ();


  logic                req_ready;
  logic                req_valid;
  logic [ADDR_W - 1:0] req_addr;
  logic                req_write;
  logic [  DATA_W-1:0] req_wdata     [LINE_SIZE];
  logic [DATA_W/8-1:0] req_wstrb     [LINE_SIZE];
  logic                resp_valid;
  logic [  DATA_W-1:0] resp_rdata    [LINE_SIZE];
  logic                dumping_cache;

  modport master(
      input req_ready,
      output req_valid,
      output req_addr,
      output req_write,
      output req_wdata,
      output req_wstrb,
      input resp_valid,
      input resp_rdata,

      output dumping_cache
  );

  modport slave(
      output req_ready,
      input req_valid,
      input req_addr,
      input req_write,
      input req_wdata,
      input req_wstrb,
      output resp_valid,
      output resp_rdata,

      input dumping_cache
  );



endinterface
