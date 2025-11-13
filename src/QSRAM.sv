// Dual-banked Q-vector buffer for ping-ponging between loading and sending to backend.
//
// One bank is being filled from memory (load side) while the other bank
// presents stable Q vectors to the PEs. When a bank is full, you can
// "activate" it for compute, and switch the fill bank to the other side.
//
// Assumptions:
//  - Each row is a Q vector
//  - You load exactly NUM_PES vectors per bank.
//  - Each vector maps to exactly one PE.
//
// Usage:
//  - Drive write_enable/write_data to fill whichever bank is currently the fill bank.
//  - When read_data_valid asserts, you know a bank is ready for compute.
//  - Assert read_enable when you're ready to latch that full bank as active.
//  - PEs see all Q vectors for the active bank on read_data.
//
// Notes:
//  - This is fully synchronous, no explicit memory protocol here.
//  - You can treat load_* as coming from your "DRAM" adapter.

module QSRAM #(
    parameter integer NUM_ROWS  = `NUM_PES,  // number of rows per bank
)(
    input                              clk,
    input                              rst,

    // Handshaking between memory controller and backend
    input                              write_enable,    //Asserted when memory controller is ready to write an entire row
    input                              read_enable,     //Asserted when all backend PEs are ready to read (can just check the first one)
    output                             read_data_valid,    //Assert when entire bank is ready to be read
    output                             sram_ready,        //Asserted when the fill bank can accept a new row

    // Data signals from memory controller to backend
    input  Q_VECTOR_T                  write_data,
    output Q_VECTOR_T                  read_data [NUM_ROWS]
);

    // Bank 0 and Bank 1: each has NUM_ROWS entries of Q Vectors.
    Q_VECTOR_T bank0 [NUM_ROWS];
    Q_VECTOR_T bank0 [NUM_ROWS];

    // Which bank is currently being filled (0 or 1)?
    logic fill_bank;

    //Which bank is currently being read by backend (0 or 1)?
    logic read_bank;

    // Write index into the current fill bank: 0 .. NUM_ROWS-1
    logic [$clog2(NUM_ROWS)-1:0] wr_idx;

    // Full flags for each bank (set when NUM_ROWS vectors written)
    logic bank0_full;
    logic bank1_full;

    // Output data valid when the read bank is full
    assign read_data_valid = (read_bank) ? bank1_full : bank0_full;

    // SRAM ready to receive a new row when the fill bank is not full
    assign sram_ready = (fill_bank) ? !bank1_full : !bank0_full;

    // Output read data from the active read bank the same cycle
    assign read_data = (read_bank == 0) ? bank0 : bank1;

    always_ff @(posedge clk) begin
        if (rst) begin
            read_bank  <= 0;
            fill_bank  <= 0;
            wr_idx     <= '0;
            bank0_full <= 0;
            bank1_full <= 0;
        end else begin
            // Handle write
            if (write_enable && sram_ready) begin
                if (fill_bank == 0) begin
                    bank0[wr_idx] <= write_data;
                end else begin
                    bank1[wr_idx] <= write_data;
                end

                if (wr_idx == NUM_ROWS-1) begin
                    // Mark this bank full
                    if (fill_bank == 0) begin
                        bank0_full <= 1'b1;
                    end else begin
                        bank1_full <= 1'b1;
                    end

                    // Switch fill bank if the other one is not active+full
                    // (simple ping-pong; you can refine this if you want).
                    fill_bank <= ~fill_bank;
                end

                // Increment write index (wraps around automatically when bits are a power)
                wr_idx <= wr_idx + 1'b1;
            end

            // Handle read
            // When the backend reads the active bank, clear its full flag.
            if (read_enable && read_data_valid) begin
                read_bank <= ~read_bank;
                if (read_bank == 0) begin
                    bank0_full <= 1'b0;
                end else begin
                    bank1_full <= 1'b0;
                end
            end
        end
    end

endmodule