module uart_over_axi4lite #(
  parameter CLOCK_FREQ_OVER_BAUD_RATE = 868,
  parameter READ_BUFFER_LENGTH_BYTES  = 64,
  parameter WRITE_BUFFER_LENGTH_BYTES = 64,
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
  /* verilator lint_off UNSIGNED */
  localparam READ_BUFFER_LENGTH_BYTES_TRUNC = READ_BUFFER_LENGTH_BYTES[$clog2(
      READ_BUFFER_LENGTH_BYTES
  )-1 : 0];

  localparam WRITE_BUFFER_LENGTH_BYTES_TRUNC = WRITE_BUFFER_LENGTH_BYTES[$clog2(
      WRITE_BUFFER_LENGTH_BYTES
  )-1 : 0];

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

  logic [$clog2(
WRITE_BUFFER_LENGTH_BYTES
) : 0] debug_difference;

  reader_state_e reader_state_d;
  reader_state_e reader_state_q;

  writer_state_e writer_state_d;
  writer_state_e writer_state_q;

  send_state_e tx_output_state_d;
  send_state_e tx_output_state_q;

  recieve_state_e recieve_state_d;
  recieve_state_e recieve_state_q;

  logic [$clog2(CLOCK_FREQ_OVER_BAUD_RATE) - 1 : 0] rx_counter;
  logic [$clog2(CLOCK_FREQ_OVER_BAUD_RATE) - 1:0] tx_counter;
  logic [$clog2(UART_FRAME_BITS) - 1 : 0] rx_bit_counter;
  logic [$clog2(UART_FRAME_BITS) - 1 : 0] tx_bit_counter;

  logic [$clog2(READ_BUFFER_LENGTH_BYTES) - 1:0] read_buffer_pointer;
  logic [$clog2(READ_BUFFER_LENGTH_BYTES) - 1 : 0] read_buffer_left_pointer;
  logic [7:0] partial_read;
  logic partial_committed;
  logic [7 : 0] read_buffer[READ_BUFFER_LENGTH_BYTES];
  logic read_buffer_full;

  logic [$clog2(WRITE_BUFFER_LENGTH_BYTES) - 1 : 0] write_buffer_pointer;
  logic [$clog2(WRITE_BUFFER_LENGTH_BYTES) - 1 : 0] write_buffer_left_pointer;
  logic [7:0] partial_write;
  logic [7 : 0] write_buffer[WRITE_BUFFER_LENGTH_BYTES];
  logic write_buffer_full;


  // RX input synchronizer
  logic rx_sync_0, rx_sync_1;
  logic rx_s;
  assign rx_s = rx_sync_1;
  always_ff @(posedge clk) begin
    if (rst) begin
      recieve_state_q           <= RC_IDLE;
      reader_state_q            <= RS_IDLE;
      writer_state_q            <= WR_IDLE;
      tx_output_state_q         <= SND_IDLE;

      rx_counter                <= '0;
      tx_counter                <= '0;
      rx_bit_counter            <= '0;
      tx_bit_counter            <= '0;

      read_buffer_pointer       <= '0;
      read_buffer_left_pointer  <= '0;

      write_buffer_pointer      <= '0;
      write_buffer_left_pointer <= '0;

      read_buffer_full          <= '0;
      write_buffer_full         <= '0;
    end else begin
      reader_state_q <= reader_state_d;
      case (recieve_state_q)
        RC_IDLE: begin
          recieve_state_q <= recieve_state_d;
          //Set the rx_counter to halfway in a cycle
          rx_counter      <= CLOCK_FREQ_OVER_BAUD_RATE / 2;
          //if (recieve_state_d == RC_START_RECIEVED) $display("Recieved start bit");
        end
        RC_START_RECIEVED: begin
          rx_counter <= rx_counter + 1 == CLOCK_FREQ_OVER_BAUD_RATE ? 0 : rx_counter + 1;
          if (rx_counter == 0) begin
            recieve_state_q <= recieve_state_d;
          end
          partial_committed <= 0;
        end
        RC_RECIEVING_DATA: begin
          rx_counter <= rx_counter + 1 == CLOCK_FREQ_OVER_BAUD_RATE ? 0 : rx_counter + 1;
          if (rx_counter == 0) begin
            recieve_state_q              <= recieve_state_d;
            rx_bit_counter               <= rx_bit_counter + 1;
            partial_read[rx_bit_counter] <= rx_s;
          end
        end
        RC_STOP: begin
          recieve_state_q <= recieve_state_d;
          //Commit the partial read
          if (!read_buffer_full && !partial_committed) begin
            automatic
            logic [$clog2(
READ_BUFFER_LENGTH_BYTES
) - 1 : 0]
            plus_one = read_buffer_pointer + 1;
            read_buffer[read_buffer_pointer] <= partial_read;
            read_buffer_pointer <= (plus_one == READ_BUFFER_LENGTH_BYTES_TRUNC) ? 0 : plus_one;
            // $display("Old pointer %d, new pointer %d, left pointer %d", read_buffer_pointer,
            //          (plus_one == READ_BUFFER_LENGTH_BYTES_TRUNC) ? 0 : plus_one,
            //          read_buffer_left_pointer);
            read_buffer_full    <=  (read_buffer_left_pointer == plus_one) || (read_buffer_left_pointer == 0 && (plus_one == READ_BUFFER_LENGTH_BYTES_TRUNC));
            partial_committed <= 1'b1;
          end
        end
      endcase
      //Only update the write_buffer state on counter intervals
      tx_counter <= tx_counter + 1 == CLOCK_FREQ_OVER_BAUD_RATE ? 0 : tx_counter + 1;
      if (tx_counter == 0) begin
        tx_output_state_q <= tx_output_state_d;
        case (tx_output_state_q)
          SND_START_BIT: tx_bit_counter <= 0;
          SND_DATA:      tx_bit_counter <= tx_bit_counter + 1;
        endcase
        case (tx_output_state_q)
          SND_IDLE: tx <= 1;
          SND_START_BIT: begin
            //Grab to the partial write
            partial_write <= write_buffer[write_buffer_left_pointer];
            tx <= 0;
            //Update the pointer
            write_buffer_left_pointer <= write_buffer_left_pointer + 1 == WRITE_BUFFER_LENGTH_BYTES_TRUNC ? 0 : write_buffer_left_pointer + 1;
            //Cannot be full anymore after we have grabbed
            write_buffer_full <= 0;
          end
          SND_DATA: begin
            tx <= partial_write[tx_bit_counter];
          end
          SND_STOP: tx <= 1;
        endcase
      end


      writer_state_q <= writer_state_d;
      //Update when a new request comes in
      if (read_access.arvalid && read_access.arready) begin
        read_access.rvalid <= 1;
        case (read_access.araddr[4:3])
          2'b00: begin
            automatic
            logic signed [$clog2(
READ_BUFFER_LENGTH_BYTES
) : 0]
            difference = read_buffer_pointer - read_buffer_left_pointer;
            if (difference >= 0) read_access.rdata <= 64'(difference);
            else read_access.rdata <= (64'(READ_BUFFER_LENGTH_BYTES) + 64'(difference));
          end
          2'b01: begin
            //Pop from the buffer
            automatic
            logic [$clog2(
READ_BUFFER_LENGTH_BYTES
) : 0]
            plus_8 = {1'b0, read_buffer_left_pointer} + 8;

            //Check if we passed it
            if((plus_8 > {1'b0, read_buffer_pointer} && read_buffer_left_pointer < read_buffer_pointer) || (read_buffer_left_pointer >= read_buffer_pointer && plus_8 - READ_BUFFER_LENGTH_BYTES > {1'b0, read_buffer_pointer})) begin
              //If so, clamp
              read_buffer_left_pointer <= read_buffer_pointer;
            end else begin
              read_buffer_left_pointer <= plus_8 >= READ_BUFFER_LENGTH_BYTES ?
                  plus_8[$clog2(READ_BUFFER_LENGTH_BYTES)-1 : 0] - READ_BUFFER_LENGTH_BYTES_TRUNC :
                  plus_8[$clog2(READ_BUFFER_LENGTH_BYTES)-1 : 0];
            end
            //The difference is how many bytes after read_buffer_pointer we are setting to. If the difference is positive, we need to go to read_buffer_pointer. If it is negative, we need to check if it, after adding LENGTH_BYTES - 8, it is positive, in which case we also must clamp


            // if (plus_8 >= READ_BUFFER_LENGTH_BYTES_TRUNC) begin
            //   read_buffer_left_pointer <= plus_8 - (READ_BUFFER_LENGTH_BYTES_TRUNC) > read_buffer_pointer ? read_buffer_pointer : plus_8 - (READ_BUFFER_LENGTH_BYTES_TRUNC);
            // end else begin
            //   read_buffer_left_pointer <= plus_8 > read_buffer_pointer ? read_buffer_pointer : plus_8;
            // end
            //After pop it cannot be full
            read_buffer_full <= 0;
            for (logic [$clog2(READ_BUFFER_LENGTH_BYTES) - 1 : 0] i = 0; i < 8; i++) begin
              automatic logic [$clog2(READ_BUFFER_LENGTH_BYTES) - 1 : 0] wrapped_pointer;
              wrapped_pointer = read_buffer_left_pointer + i >= READ_BUFFER_LENGTH_BYTES_TRUNC ? read_buffer_left_pointer + i - READ_BUFFER_LENGTH_BYTES_TRUNC : read_buffer_left_pointer + i;
              read_access.rdata[i[2:0]*8+:8] <= read_buffer[wrapped_pointer];
            end

          end
          2'b10: begin
            automatic
            logic signed [$clog2(
WRITE_BUFFER_LENGTH_BYTES
) : 0]
            difference = write_buffer_pointer - write_buffer_left_pointer;
            if (difference >= 0) read_access.rdata <= 64'(difference);
            else read_access.rdata <= (64'(WRITE_BUFFER_LENGTH_BYTES) + 64'(difference));
          end
          default: read_access.rdata <= 0;
        endcase
      end else if (reader_state_d == RS_IDLE) begin
        read_access.rvalid <= 0;
      end

      if (write_access.awvalid && write_access.wready) begin
        automatic logic [$clog2(WRITE_BUFFER_LENGTH_BYTES) - 1 : 0] new_write_pointer;
        write_access.bvalid <= 1;
        for (logic [$clog2(WRITE_BUFFER_LENGTH_BYTES) - 1 : 0] i = 0; i < 8; i++) begin
          automatic logic [$clog2(WRITE_BUFFER_LENGTH_BYTES) - 1 : 0] wrapped_pointer;
          wrapped_pointer = write_buffer_pointer + i >= WRITE_BUFFER_LENGTH_BYTES_TRUNC ? write_buffer_pointer + i - WRITE_BUFFER_LENGTH_BYTES_TRUNC : write_buffer_pointer + i;
          write_buffer[wrapped_pointer] <= write_access.wdata[i[2:0]*8+:8];
        end
        new_write_pointer = write_buffer_pointer + 8  >= WRITE_BUFFER_LENGTH_BYTES_TRUNC ? write_buffer_pointer + 8 - WRITE_BUFFER_LENGTH_BYTES_TRUNC : write_buffer_pointer + 8;
        write_buffer_pointer <= new_write_pointer;
        $display("Setting write buffer full: %b", new_write_pointer == write_buffer_left_pointer);
        write_buffer_full <= new_write_pointer == write_buffer_left_pointer;
      end else if (writer_state_d == WR_IDLE) write_access.bvalid <= 0;
    end
    // Synchronize the async rx input
    rx_sync_0 <= rx;
    rx_sync_1 <= rx_sync_0;

  end

  always_comb begin
    recieve_state_d = RC_IDLE;
    case (recieve_state_q)
      RC_IDLE: begin
        //Go to RC_START_RECIEVED when we get the start bit (0)
        if (!rx_s) recieve_state_d = RC_START_RECIEVED;
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
        if (rx_s) recieve_state_d = RC_IDLE;
        else recieve_state_d = RC_STOP;
      end
    endcase
    tx_output_state_d = SND_IDLE;
    case (tx_output_state_q)
      SND_IDLE: begin
        //Initiate a send when we have a byte ready to go
        automatic
        logic signed [$clog2(
WRITE_BUFFER_LENGTH_BYTES
) : 0]
        difference = write_buffer_pointer - write_buffer_left_pointer;


        if (difference != 0 || write_buffer_full) begin
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

    read_access.arready = 0;
    reader_state_d      = RS_IDLE;
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
READ_BUFFER_LENGTH_BYTES
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
    begin
      automatic
      logic signed [$clog2(
WRITE_BUFFER_LENGTH_BYTES
) : 0]
      difference = ($clog2(
          WRITE_BUFFER_LENGTH_BYTES
      ) + 1)'(signed'(write_buffer_left_pointer)) - ($clog2(
          WRITE_BUFFER_LENGTH_BYTES
      ) + 1)'(signed'(write_buffer_pointer));
      debug_difference = difference;
      if (difference >= 0)
        can_accept_write = !write_buffer_full && (difference >= 8 || difference == 0);
      else can_accept_write = !write_buffer_full && (WRITE_BUFFER_LENGTH_BYTES + difference >= 8);

      if (writer_state_q == WR_IDLE) begin
        write_access.wready = can_accept_write;
        writer_state_d      = write_access.awvalid ? WR_WAITING_FOR_ACCEPT : WR_IDLE;
      end else begin
        //TODO: Get this to work with timing. write_access.bready is always 1 for us so it is fine
        write_access.wready = can_accept_write;  // & write_access.bready;
        writer_state_d      = write_access.bready ? WR_IDLE : WR_WAITING_FOR_ACCEPT;
      end
      write_access.awready = write_access.wready;
    end
  end



endmodule
