// Dual-banked Q-vector buffer for ping-ponging between load and compute.
//
// One bank is being filled from memory (load side) while the other bank
// presents stable Q vectors to the PEs. When a bank is full, you can
// "activate" it for compute, and switch the fill bank to the other side.
//
// Assumptions:
//  - Each Q vector is Q_WIDTH bits (e.g. d_k * 8 for int8).
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

module SRAM_DB #(
    parameter integer NUM_PES  = `NUM_PES,  // number of PEs (and Q vectors per bank)
    parameter integer Q_WIDTH  = `MAX_EMBEDDING_DIM * `INTEGER_WIDTH  // bits per Q vector (e.g. d_k * 8 for int8)
)(
    input  clk,
    input  rst,

    // Load-side interface: one Q vector per cycle when load_valid & load_ready.
    input  wire                       load_valid,
    input  wire [Q_WIDTH-1:0]         load_data,
    output wire                       load_ready,

    // Control from scheduler / top-level:
    // compute_start: pulse high when you want to latch a full bank as active.
    input  wire                       compute_start,
    // compute_done: pulse high when PEs are done consuming current active bank.
    input  wire                       compute_done,

    // Status back to scheduler:
    output wire                       bank_full,    // at least one bank is full & idle
    output wire                       bank_active,  // there is an active bank in use
    output wire                       active_bank_id, // 0 or 1, for debug/visibility

    // Outputs to PEs:
    // Packed bus: PE i gets slice q_to_pes[i*Q_WIDTH +: Q_WIDTH]
    output wire [NUM_PES*Q_WIDTH-1:0] q_to_pes
);

    // --------------------------------------------
    // Internal storage: two banks of NUM_PES Q vectors
    // --------------------------------------------

    // Bank 0 and Bank 1: each has NUM_PES entries of Q_WIDTH bits.
    reg [Q_WIDTH-1:0] bank0 [0:NUM_PES-1];
    reg [Q_WIDTH-1:0] bank1 [0:NUM_PES-1];

    // Which bank is currently the "fill" bank (0 or 1)?
    reg fill_bank;

    // Write index into the current fill bank: 0 .. NUM_PES-1
    localparam integer WR_IDX_WIDTH = $clog2(NUM_PES);
    reg [WR_IDX_WIDTH-1:0] wr_idx;

    // Full flags for each bank (set when NUM_PES vectors written)
    reg bank0_full;
    reg bank1_full;

    // Active bank used by the PEs (0 or 1) and a flag that says "in use".
    reg        active_bank;
    reg        active_valid;

    assign active_bank_id = active_bank;
    assign bank_active    = active_valid;

    // A bank is "available for compute" if it is full and not the current active bank.
    wire bank0_ready_for_compute = bank0_full && (!active_valid || (active_bank != 1'b0));
    wire bank1_ready_for_compute = bank1_full && (!active_valid || (active_bank != 1'b1));

    assign bank_full = bank0_ready_for_compute || bank1_ready_for_compute;

    // --------------------------------------------
    // Load-side: write into the current fill bank
    // --------------------------------------------

    // We can accept data as long as the current fill bank isn't full.
    wire fill_bank_full = (fill_bank == 1'b0) ? bank0_full : bank1_full;
    assign load_ready   = !fill_bank_full;

    integer i;

    // Write logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fill_bank   <= 1'b0;
            wr_idx      <= {WR_IDX_WIDTH{1'b0}};
            bank0_full  <= 1'b0;
            bank1_full  <= 1'b0;
        end else begin
            // Handle load
            if (load_valid && load_ready) begin
                if (!fill_bank) begin
                    bank0[wr_idx] <= load_data;
                end else begin
                    bank1[wr_idx] <= load_data;
                end

                // Advance write index
                if (wr_idx == NUM_PES-1) begin
                    wr_idx <= {WR_IDX_WIDTH{1'b0}};
                    // Mark this bank full
                    if (!fill_bank) begin
                        bank0_full <= 1'b1;
                    end else begin
                        bank1_full <= 1'b1;
                    end

                    // Switch fill bank if the other one is not active+full
                    // (simple ping-pong; you can refine this if you want).
                    fill_bank <= ~fill_bank;
                end else begin
                    wr_idx <= wr_idx + 1'b1;
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