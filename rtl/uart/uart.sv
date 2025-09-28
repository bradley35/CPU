module uart_over_axi4lite #(
  parameter CLOCK_FREQ_OVER_BAUD_RATE = 16,
  parameter READ_BUFFER_LENGTH_BYTES  = 128,
  parameter WRITE_BUFFER_LENGTH_BYTES = 128,
  parameter UART_FRAME_BITS           = 8
) (
  input  logic                    clk,
  input  logic                    rst,
  /* UART Pins */
  input  logic                    rx,
  output logic                    tx,
  /* Access */
         axil_interface_if.rd_slv read_access,
         axil_interface_if.wr_slv write_access
);

  typedef enum {
    RC_IDLE,
    RC_START_RECIEVED,
    RC_RECIEVING_DATA,
    RC_STOP
  } recieve_state_e;


  typedef enum {
    SND_IDLE,
    SND_START_BIT,
    SND_DATA,
    SND_STOP
  } send_state_e;

  typedef enum {
    RS_IDLE,
    RS_WAITING_FOR_ACCEPT
  } reader_state_e;

  typedef enum {
    WR_IDLE,
    WR_WAITING_FOR_ACCEPT
  } writer_state_e;

  /*
Outline:
1) Read from rx into read buffer
2) Write from write-buffer into tx and pop
3) Read/Write Access:
 - Memory Address 0: Read-only, # of bytes in read_buffer
 - Memory Address 8: Read-only, pop 64 bits from read_buffer
 - Memory Address 16: Read-only, # of bytes in write_buffer
 - Memory Address 24: Write-only, put in write buffer, don't accept unless we can

*/

  logic can_accept_write;


  function automatic logic [63:0] read_response(logic [1:0] address);
    case (address)
      2'b00: begin
        //return 64'(read_buffer_pointer >> 3);
        automatic
        logic signed [$clog2(
READ_BUFFER_LENGTH_BYTES * 8
) : 0]
        difference = read_buffer_pointer - read_buffer_left_pointer;
        if (difference >= 0) return 64'(difference >>> 3);
        else return (READ_BUFFER_LENGTH_BYTES * 8 + 64'(difference)) >>> 3;
      end
      2'b01: begin
        //Pop from the buffer
        automatic
        logic [$clog2(
READ_BUFFER_LENGTH_BYTES * 8
) - 1 : 0]
        lp64 = read_buffer_left_pointer + 64;
        if (lp64 >= READ_BUFFER_LENGTH_BYTES * 8) begin
          read_buffer_left_pointer <= lp64 - (READ_BUFFER_LENGTH_BYTES * 8) > read_buffer_pointer ? read_buffer_pointer : lp64 - (READ_BUFFER_LENGTH_BYTES * 8);
        end else begin
          read_buffer_left_pointer <= lp64 > read_buffer_pointer ? read_buffer_pointer : lp64;
        end

        return read_buffer[read_buffer_left_pointer+:64];
      end
      2'b10: begin
        automatic
        logic signed [$clog2(
WRITE_BUFFER_LENGTH_BYTES * 8
) : 0]
        difference = write_buffer_pointer - write_buffer_left_pointer;
        if (difference >= 0) return 64'(difference >>> 3);
        else return (WRITE_BUFFER_LENGTH_BYTES * 8 + 64'(difference)) >>> 3;
      end
      default: return 0;
    endcase
  endfunction

  reader_state_e                                                  reader_state_d;
  reader_state_e                                                  reader_state_q;

  writer_state_e                                                  writer_state_d;
  writer_state_e                                                  writer_state_q;

  send_state_e                                                    tx_output_state_d;
  send_state_e                                                    tx_output_state_q;

  recieve_state_e                                                 recieve_state_d;
  recieve_state_e                                                 recieve_state_q;

  logic           [        $clog2(CLOCK_FREQ_OVER_BAUD_RATE) : 0] rx_counter;
  logic           [        $clog2(CLOCK_FREQ_OVER_BAUD_RATE) : 0] tx_counter;
  logic           [              $clog2(UART_FRAME_BITS) - 1 : 0] rx_bit_counter;
  logic           [              $clog2(UART_FRAME_BITS) - 1 : 0] tx_bit_counter;

  logic           [   $clog2(READ_BUFFER_LENGTH_BYTES * 8) - 1:0] read_buffer_pointer;
  logic           [ $clog2(READ_BUFFER_LENGTH_BYTES * 8) - 1 : 0] read_buffer_left_pointer;
  logic           [         READ_BUFFER_LENGTH_BYTES * 8 - 1 : 0] read_buffer;

  logic           [  $clog2(WRITE_BUFFER_LENGTH_BYTES * 8) - 1:0] write_buffer_pointer;
  logic           [$clog2(WRITE_BUFFER_LENGTH_BYTES * 8) - 1 : 0] write_buffer_left_pointer;
  logic           [        WRITE_BUFFER_LENGTH_BYTES * 8 - 1 : 0] write_buffer;


  always_ff @(posedge clk) begin
    if (rst) begin
      recieve_state_q <= RC_IDLE;
    end else begin
      reader_state_q <= reader_state_d;
      case (recieve_state_q)
        RC_IDLE: begin
          recieve_state_q <= recieve_state_d;
          //Set the rx_counter to halfway in a cycle
          rx_counter      <= 0;  //CLOCK_FREQ_OVER_BAUD_RATE / 2;
          //if (recieve_state_d == RC_START_RECIEVED) $display("Recieved start bit");
        end
        RC_START_RECIEVED: begin
          rx_counter <= rx_counter + 1 == CLOCK_FREQ_OVER_BAUD_RATE ? 0 : rx_counter + 1;
          if (rx_counter == 0) begin
            recieve_state_q <= recieve_state_d;
          end
        end
        RC_RECIEVING_DATA: begin
          rx_counter <= rx_counter + 1 == CLOCK_FREQ_OVER_BAUD_RATE ? 0 : rx_counter + 1;
          if (rx_counter == 0) begin
            recieve_state_q <= recieve_state_d;
            rx_bit_counter  <= rx_bit_counter + 1;
            //Store the recieved bit
            //$display("Reading bit: %b", rx);
            //$display("Counter is: %d", read_buffer_pointer);
            if (read_buffer_pointer != read_buffer_left_pointer - 1) begin
              read_buffer[read_buffer_pointer[$clog2(READ_BUFFER_LENGTH_BYTES*8)-1 : 0]] <= rx;
              read_buffer_pointer <= read_buffer_pointer + 1 == READ_BUFFER_LENGTH_BYTES*8 ? 0 : read_buffer_pointer + 1;
            end

          end  //else $display("Skipping this cycle");
        end
        RC_STOP: recieve_state_q <= recieve_state_d;
      endcase
      //Only update the write_buffer state on counter intervals
      tx_counter <= tx_counter + 1 == CLOCK_FREQ_OVER_BAUD_RATE ? 0 : tx_counter + 1;
      if (tx_counter == 0) begin
        tx_output_state_q <= tx_output_state_d;
        case (tx_output_state_q)
          SND_START_BIT: tx_bit_counter <= 0;
          SND_DATA:      tx_bit_counter <= tx_bit_counter + 1;
        endcase
        case (tx_output_state_d)
          SND_IDLE:      tx <= 1;
          SND_START_BIT: tx <= 0;
          SND_DATA: begin
            write_buffer_left_pointer <= write_buffer_left_pointer + 1 == WRITE_BUFFER_LENGTH_BYTES*8 ? 0 : write_buffer_left_pointer + 1;
            tx <= write_buffer[write_buffer_left_pointer];
          end
          SND_STOP:      tx <= 1;
        endcase
      end



      //Update when a new request comes in
      if (read_access.arvalid && read_access.arready) begin
        read_access.rvalid <= 1;
        read_access.rdata  <= read_response(read_access.araddr[4:3]);
      end else if (reader_state_d == RS_IDLE) begin
        read_access.rvalid <= 0;
      end

      if (write_access.wvalid && write_access.wready) begin
        write_access.bvalid <= 1;
        //TODO: Add to write buffer
        for (logic [$clog2(READ_BUFFER_LENGTH_BYTES * 8) - 1 : 0] i = 0; i < 64; i++) begin
          automatic logic [$clog2(READ_BUFFER_LENGTH_BYTES * 8) - 1 : 0] wrapped_pointer;
          wrapped_pointer = write_buffer_pointer + i >= WRITE_BUFFER_LENGTH_BYTES * 8 ? write_buffer_pointer + i - WRITE_BUFFER_LENGTH_BYTES * 8 : write_buffer_pointer + i;
          write_buffer[wrapped_pointer] <= write_access.wdata[i[5:0]];
        end
        write_buffer_pointer <= write_buffer_pointer + 64  >= WRITE_BUFFER_LENGTH_BYTES * 8 ? write_buffer_pointer + 64 - WRITE_BUFFER_LENGTH_BYTES * 8 : write_buffer_pointer + 64;
      end else if (writer_state_d == WR_IDLE) write_access.bvalid <= 0;

    end
  end

  always_comb begin
    case (recieve_state_q)
      RC_IDLE: begin
        //Go to RC_START_RECIEVED when we get the start bit (0)
        if (!rx) recieve_state_d = RC_START_RECIEVED;
        else recieve_state_d = RC_IDLE;
      end
      RC_START_RECIEVED: recieve_state_d = RC_RECIEVING_DATA;
      RC_RECIEVING_DATA: begin
        //Go to idle after we have recieved the number of bits
        localparam int unsigned minus_one = UART_FRAME_BITS - 1;
        if (rx_bit_counter == minus_one[$clog2(UART_FRAME_BITS)-1 : 0]) recieve_state_d = RC_STOP;
        else recieve_state_d = RC_RECIEVING_DATA;
      end
      RC_STOP: begin
        if (rx) recieve_state_d = RC_IDLE;
        else recieve_state_d = RC_STOP;
      end
    endcase

    case (tx_output_state_q)
      SND_IDLE: begin
        //Initiate a send when we have 8 bits ready to go
        automatic
        logic signed [$clog2(
WRITE_BUFFER_LENGTH_BYTES * 8
) : 0]
        difference = write_buffer_pointer - write_buffer_left_pointer;

        automatic logic signed [$clog2(
WRITE_BUFFER_LENGTH_BYTES * 8
) : 0] corrected_difference;
        if (difference >= 0) corrected_difference = difference;
        else corrected_difference = WRITE_BUFFER_LENGTH_BYTES * 8 + difference;

        if (corrected_difference >= 8) begin
          //We are ready
          tx_output_state_d = SND_START_BIT;
        end else tx_output_state_d = SND_IDLE;
      end
      SND_START_BIT: tx_output_state_d = SND_DATA;
      SND_DATA: begin
        localparam int unsigned minus_one = UART_FRAME_BITS - 1;
        if (tx_bit_counter == minus_one[$clog2(UART_FRAME_BITS)-1 : 0])
          tx_output_state_d = SND_STOP;
        else tx_output_state_d = SND_DATA;
      end
      SND_STOP:      tx_output_state_d = SND_IDLE;
    endcase


    case (reader_state_q)
      RS_IDLE: begin
        //We can accept a read
        read_access.arready = 1;
      end
      RS_WAITING_FOR_ACCEPT: begin
        //We cannot accept a read unless we will be accepted right now
        read_access.arready = read_access.rready;
      end
    endcase

    if (read_access.arvalid && read_access.arready) begin
      automatic
      logic [$clog2(
READ_BUFFER_LENGTH_BYTES * 8
) : 0]
      subtracted = (read_buffer_pointer - 64);
      reader_state_d = RS_WAITING_FOR_ACCEPT;
    end else begin
      if (reader_state_q == RS_IDLE) reader_state_d = RS_IDLE;
      else if (reader_state_q == RS_WAITING_FOR_ACCEPT)
        reader_state_d = read_access.rready ? RS_IDLE : RS_WAITING_FOR_ACCEPT;
    end

    //We are already ready to recieve a write, unless we never got onconfrimation of the last one being valid
    //There is only one valid write address, so we actually don't care about this one
    write_access.awready = 1;
    can_accept_write     = (write_buffer_left_pointer != write_buffer_pointer - 64) && (write_buffer_left_pointer != write_buffer_pointer + WRITE_BUFFER_LENGTH_BYTES*8 - 64);
    if (writer_state_q == WR_IDLE) begin
      write_access.wready = can_accept_write;
      writer_state_d      = write_access.wvalid ? WR_WAITING_FOR_ACCEPT : WR_IDLE;
    end else begin
      write_access.wready = can_accept_write & write_access.bready;
      writer_state_d      = write_access.bready ? WR_IDLE : WR_WAITING_FOR_ACCEPT;
    end
  end



endmodule

