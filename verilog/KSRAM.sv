// KSRAM FIFO

module KSRAM #(
    parameter integer NUM_ENTRIES  = `MAX_SEQ_LENGTH  // number of rows per bank
)(
    input                              clk,
    input                              rst,

    // Handshaking between memory controller and backend
    input                              write_enable,    //Asserted when memory controller is ready to write an entire row
    input                              read_enable,     //Asserted when all backend PEs are ready to read (can just check the first one)
    output                             read_data_valid,    //Assert when entire bank is ready to be read
    output                             sram_ready,        //Asserted when the fill bank can accept a new row

    // Data signals from memory controller to backend
    input  K_VECTOR_T                  write_data,
    output K_VECTOR_T                  read_data
);

    // Internal fifo of K vectors
    K_VECTOR_T fifo [NUM_ENTRIES];

    // Write index into the current fill bank: 0 .. NUM_ROWS-1
    logic [$clog2(NUM_ENTRIES):0] head, tail;

    // Full/empty flags
    logic full, empty;

    //assign full = (head ^ tail) == (NUM_ENTRIES);
    //assign empty = (head == tail);

    //New logic to allow all vectors to be read for multiple iterations
    assign full = (tail == NUM_ENTRIES);
    assign empty = (tail == 0);

    // Output data valid when the fifo has at least one valid entry
    assign read_data_valid = !empty;

    // SRAM ready to receive a new vector when the fifo is not full
    assign sram_ready = !full;

    // Output read data from the head of the fifo in the same cycle
    assign read_data = fifo[head[$clog2(NUM_ENTRIES)-1:0]];

    always_ff @(posedge clk) begin
        if (rst) begin
            //fifo  <= '0;
            for (int i = 0; i < NUM_ENTRIES; i++) begin
                fifo[i] <= '0;
            end
            head  <= '0;
            tail  <= '0;
        end else begin
            // Handle write
            if (write_enable && sram_ready) begin
                fifo[tail] <= write_data;
                tail <= tail + 1;
            end

            // Handle read
            if (read_enable && read_data_valid) begin
                head <= head + 1;
            end
        end
        `ifdef KSRAM_DEBUG
            $write("KSRAM FIFO: ");
            for(int i = 0; i < 3; i++) begin
                $write("Entry[%0d]: ", i);
                foreach (fifo[i][j]) begin
                    $write("%02x ", fifo[i][j]); //or %0d for decimal val
                end
                $write("\n");
            end
            for(int i = NUM_ENTRIES - 4; i < NUM_ENTRIES; i++) begin
                $write("Entry[%0d]: ", i);
                foreach (fifo[i][j]) begin
                    $write("%02x ", fifo[i][j]); //or %0d for decimal val
                end
                $write("\n");
            end
        `endif
    end

endmodule