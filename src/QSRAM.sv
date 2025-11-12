// Dual-banked Q-vector buffer for ping-ponging between load and compute.
//
// One bank is being filled from memory (load side) while the other bank
// presents stable Q vectors to the PEs. When a bank is full, you can
// "activate" it for compute, and switch the fill bank to the other side.
//
// Assumptions:
//  - Each Q vector is ROW_WIDTH bits (e.g. d_k * 8 for int8).
//  - You load exactly NUM_PES vectors per bank.
//  - Each vector maps to exactly one PE.
//
// Usage:
//  - Drive load_valid/load_data to fill whichever bank is currently the fill bank.
//  - When bank_full_pulse asserts, you know a bank is ready for compute.
//  - Assert compute_start when you're ready to latch that full bank as active.
//  - PEs see all Q vectors for the active bank on q_to_pes.
//
// Notes:
//  - This is fully synchronous, no explicit memory protocol here.
//  - You can treat load_* as coming from your "DRAM" adapter.

function automatic logic [NUM_ROWS*ROW_WIDTH-1:0]
    pack_bank (input logic [ROW_WIDTH-1:0] bank [NUM_ROWS]);
    for (int i = 0; i < NUM_ROWS; i++)
        pack_bank[i*ROW_WIDTH +: ROW_WIDTH] = bank[i];
endfunction

module QSRAM #(
    parameter integer NUM_ROWS  = `NUM_PES,  // number of rows per bank
    parameter integer ROW_WIDTH  = `MAX_EMBEDDING_DIM * `INTEGER_WIDTH  // bits per row
)(
    input                              clk,
    input                              rst,

    // Handshaking between memory controller and backend
    input                              load_data_valid,
    input                              backend_ready,
    output                             sram_ready,
    output                             sram_data_valid,

    // Data signals from memory controller to backend
    input  logic [ROW_WIDTH-1:0]       load_data,
    output logic [NUM_ROWS*ROW_WIDTH-1:0] output_data,
);

    // --------------------------------------------
    // Internal storage: two banks of NUM_PES Q vectors each
    // --------------------------------------------

    // Bank 0 and Bank 1: each has NUM_PES entries of Q_WIDTH bits.
    logic [ROW_WIDTH-1:0] bank0 [0:NUM_ROWS-1];
    logic [ROW_WIDTH-1:0] bank1 [0:NUM_ROWS-1];

    // Which bank is currently being filled (0 or 1)?
    logic fill_bank;

    //Which bank is currently being read by backend (0 or 1)?
    logic read_bank;

    // Write index into the current fill bank: 0 .. NUM_ROWS-1
    localparam integer WR_IDX_WIDTH = $clog2(NUM_ROWS);
    logic [WR_IDX_WIDTH-1:0] wr_idx;

    // Full flags for each bank (set when NUM_ROWS vectors written)
    logic bank0_full;
    logic bank1_full;

    // Output data valid when the read bank is full
    assign sram_data_valid = (read_bank) ? bank1_full : bank0_full;

    // SRAM ready to receive a new row when the fill bank is not full
    assign sram_ready = (fill_bank) ? !bank1_full : !bank0_full;

    // --------------------------------------------
    // Load-side: write into the current fill bank
    // --------------------------------------------

    integer i;

    // Write logic
    always @(posedge clk) begin
        if (rst) begin
            fill_bank   <= 0;
            wr_idx      <= '0;
            bank0_full  <= 0;
            bank1_full  <= 0;
        end else begin
            // Handle load
            if (load_data_valid && sram_ready) begin
                if (!fill_bank) begin
                    bank0[wr_idx] <= load_data;
                end else begin
                    bank1[wr_idx] <= load_data;
                end

                // Advance write index
                wr_idx <= wr_idx + 1'b1; //Wraps around automatically (power of 2 bits)

                if (wr_idx == NUM_ROWS-1) begin
                    // Mark this bank full
                    if (!fill_bank) begin
                        bank0_full <= 1'b1;
                    end else begin
                        bank1_full <= 1'b1;
                    end

                    // Switch fill bank if the other one is not active+full
                    // (simple ping-pong; you can refine this if you want).
                    fill_bank <= ~fill_bank;
                end
            end

            // When compute is done with the active bank, clear its full flag.
            if (compute_done && active_valid) begin
                if (!active_bank) begin
                    bank0_full <= 1'b0;
                end else begin
                    bank1_full <= 1'b0;
                end
            end
        end
    end

    // --------------------------------------------
    // Compute-side control: latch a full bank as active
    // --------------------------------------------

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_bank  <= 1'b0;
            active_valid <= 1'b0;
        end else begin
            // Start compute on a ready bank when asked.
            if (compute_start) begin
                if (bank0_ready_for_compute) begin
                    active_bank  <= 1'b0;
                    active_valid <= 1'b1;
                end else if (bank1_ready_for_compute) begin
                    active_bank  <= 1'b1;
                    active_valid <= 1'b1;
                end
                // If neither ready, compute_start is ignored.
            end

            // When compute is done, mark no active bank.
            if (compute_done) begin
                active_valid <= 1'b0;
            end
        end
    end

    // --------------------------------------------
    // Read-side: present active bank to PEs
    // --------------------------------------------
    // We simply multiplex between bank0 and bank1 based on active_bank,
    // and pack results into q_to_pes.

    genvar gi;
    generate
        for (gi = 0; gi < NUM_PES; gi = gi + 1) begin : G_PE_OUT
            wire [Q_WIDTH-1:0] q_vec =
                (!active_valid) ? {Q_WIDTH{1'b0}} : // no active bank: output zeros
                (active_bank == 1'b0 ? bank0[gi] : bank1[gi]);

            assign q_to_pes[gi*Q_WIDTH +: Q_WIDTH] = q_vec;
        end
    endgenerate

endmodule