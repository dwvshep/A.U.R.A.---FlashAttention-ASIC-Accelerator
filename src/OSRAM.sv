// Dual-banked O-vector buffer for ping-ponging between writes from backend and draining to memory.
//
// One bank is being filled from PEs (load side) while the other bank
// writes stable O vectors back to memory. When a bank is full, you can
// "activate" it for drain, and switch the fill bank to the other side.
//
// Assumptions:
//  - Each row is an O vector
//  - You load exactly NUM_PES vectors per bank.
//  - Each vector maps to exactly one PE.
//
// Usage:
//  - Drive write_enable/write_data to fill whichever bank is currently the fill bank.
//  - When read_data_valid asserts, you know a bank is ready for compute.
//  - Assert drain_enable when you're ready to write a vector back to memory.
//  - PEs see all Q vectors for the active bank on read_data.
//
// Notes:
//  - This is fully synchronous, no explicit memory protocol here.
//  - You can treat load_* as coming from your "DRAM" adapter.

module OSRAM #(
    parameter integer NUM_ROWS  = `NUM_PES,  // number of rows per bank
)(
    input                              clk,
    input                              rst,

    // Handshaking between memory controller and backend
    input                              write_enable,    //Asserted when PEs are ready to write an entire bank (can just check the first one)
    input                              drain_enable,     //Asserted when all backend PEs are ready to read
    output                             drain_data_valid,  //Assert when any data in the drain bank is ready to be sent to memory
    output                             sram_ready,        //Asserted when the fill bank can accept a new row

    // Data signals from memory controller to backend
    input  O_VECTOR_T                  write_data [NUM_ROWS],
    output O_VECTOR_T                  drain_data
);

    // Bank 0 and Bank 1: each has NUM_ROWS entries of O Vectors.
    O_VECTOR_T bank0 [NUM_ROWS];
    O_VECTOR_T bank0 [NUM_ROWS];

    // Which bank is currently being filled (0 or 1)?
    logic write_bank;

    //Which bank is currently being read by backend (0 or 1)?
    logic drain_bank;

    // Write index into the current fill bank: 0 .. NUM_ROWS-1
    logic [$clog2(NUM_ROWS)-1:0] drain_idx;

    // Empty flags for each bank (set when all NUM_ROWS vectors are drained)
    logic bank0_empty;
    logic bank1_empty;

    // Output data valid when the read bank is full
    assign drain_data_valid = (drain_bank) ? !bank1_empty : !bank0_empty;

    // SRAM ready to receive lockstep PE write_data when the fill bank is empty
    assign sram_ready = (write_bank) ? bank1_empty : bank0_empty;

    // Output drain data from the active drain bank the same cycle
    assign drain_data = (drain_bank == 0) ? bank0[drain_idx] : bank1[drain_idx];

    always_ff @(posedge clk) begin
        if (rst) begin
            drain_bank  <= 0;
            write_bank  <= 0;
            drain_idx   <= '0;
            bank0_empty <= 1;
            bank1_empty <= 1;
        end else begin
            // Handle write
            if (write_enable && sram_ready) begin
                if (write_bank == 0) begin
                    bank0 <= write_data;
                end else begin
                    bank1 <= write_data;
                end

                if (write_bank == 0) begin
                    bank0_empty <= 1'b0;
                end else begin
                    bank1_empty <= 1'b0;
                end

                write_bank <= ~write_bank;
            end

            // Handle drain
            // When memory drains the entire drain bank, assert its empty flag.
            if (drain_enable && drain_data_valid) begin
                if (drain_idx == NUM_ROWS-1) begin
                    drain_bank <= ~drain_bank;
                    if (drain_bank == 0) begin
                        bank0_empty <= 1'b1;
                    end else begin
                        bank1_empty <= 1'b1;
                    end
                end 

                // Increment drain index (wraps around automatically when bits are a power)
                drain_idx <= drain_idx + 1'b1;
            end
        end
    end

endmodule