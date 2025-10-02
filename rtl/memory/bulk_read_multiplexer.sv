module bulk_read_multiplexer #(
  parameter DATA_W    = 64,
  parameter ADDR_W    = 64,
  parameter LINE_SIZE = 8
) (
  bulk_read_interface.slave  if_access,
  bulk_read_interface.slave  data_access,
  bulk_read_interface.master memory_access_out,

  input logic clk,
  input logic rst
);

  logic [     ADDR_W - 1:0]               req_addr_buffer;
  logic                                   req_write_buffer;
  logic [LINE_SIZE - 1 : 0][  DATA_W-1:0] req_wdata_buffer;
  logic [LINE_SIZE - 1 : 0][DATA_W/8-1:0] req_wstrb_buffer;
  logic                                   buffer_valid;
  logic                                   currently_serving_if;
  logic                                   currently_serving_if_next;

  logic                                   save_data_to_buffer;
  logic                                   clear_buffer;

  logic                                   data_dumping;
  assign data_dumping = data_access.dumping_cache;


  always_ff @(posedge clk) begin
    if (rst) begin
      req_addr_buffer      <= '0;
      req_write_buffer     <= '0;
      req_wdata_buffer     <= '{default: '0};
      req_wstrb_buffer     <= '{default: '0};
      buffer_valid         <= '0;
      currently_serving_if <= '0;
    end else begin
      currently_serving_if <= currently_serving_if_next;
      if (clear_buffer) buffer_valid <= 0;
      if (save_data_to_buffer) begin
        req_addr_buffer  <= data_access.req_addr;
        req_write_buffer <= data_access.req_write;
        req_wdata_buffer <= data_access.req_wdata;
        req_wstrb_buffer <= data_access.req_wstrb;
        buffer_valid     <= '1;
      end
    end
  end

  always_comb begin

    currently_serving_if_next = currently_serving_if;
    save_data_to_buffer       = 0;
    clear_buffer              = 0;
    /* Forwarding Requests */
    if (!buffer_valid) begin
      //If there is nothing in the buffer, forward the ready state
      if_access.req_ready   = memory_access_out.req_ready && !data_dumping;
      data_access.req_ready = memory_access_out.req_ready;


      //We can accept from either
      //Forward whoever is sending a valid signal, prioritizing if
      if (if_access.req_valid && !data_dumping) begin
        memory_access_out.req_valid = 1;
        memory_access_out.req_addr  = if_access.req_addr;
        memory_access_out.req_write = if_access.req_write;
        memory_access_out.req_wdata = if_access.req_wdata;
        memory_access_out.req_wstrb = if_access.req_wstrb;
      end else if (data_access.req_valid) begin
        memory_access_out.req_valid = 1;
        memory_access_out.req_addr  = data_access.req_addr;
        memory_access_out.req_write = data_access.req_write;
        memory_access_out.req_wdata = data_access.req_wdata;
        memory_access_out.req_wstrb = data_access.req_wstrb;
      end else begin
        memory_access_out.req_valid = 0;
        memory_access_out.req_addr  = '0;
        memory_access_out.req_write = '0;
        memory_access_out.req_wdata = '{default: '0};
        memory_access_out.req_wstrb = '{default: '0};
      end
      if (memory_access_out.req_ready) begin
        //If the request was accepted, determine who
        currently_serving_if_next = if_access.req_valid;
        //If both requested, we need to store data to the buffer
        if (if_access.req_valid && data_access.req_valid) begin
          save_data_to_buffer = 1;
        end
      end



    end else begin
      //Otherwise, the next accept will be from the buffer
      if_access.req_ready         = 0;
      data_access.req_ready       = 0;

      //Therefore, we need to present the buffer
      memory_access_out.req_valid = 1;
      memory_access_out.req_addr  = req_addr_buffer;
      memory_access_out.req_write = req_write_buffer;
      memory_access_out.req_wdata = req_wdata_buffer;
      memory_access_out.req_wstrb = req_wstrb_buffer;

      //Our request has been accepted
      if (memory_access_out.req_ready) begin
        //The buffer has to be for whoever we were not serving
        currently_serving_if_next = !currently_serving_if;
        clear_buffer              = 1;
      end
    end

    //Forward the outputs
    if_access.resp_rdata   = memory_access_out.resp_rdata;
    data_access.resp_rdata = memory_access_out.resp_rdata;
    if (currently_serving_if) begin
      if_access.resp_valid   = memory_access_out.resp_valid;
      data_access.resp_valid = 0;
    end else begin
      data_access.resp_valid = memory_access_out.resp_valid;
      if_access.resp_valid   = 0;
    end


  end

endmodule
