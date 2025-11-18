// This module performs signed integer division of two INT_T numbers.
// Currently uses the '/' operator as a placeholder for the core division.
// Sign handling is done via pre/post processing.

module int_division(
    // Control signals
    input  logic clk,
    input  logic rst,

    // Handshake signals
    input  logic vld_in,
    input  logic rdy_in,
    output logic vld_out,
    output logic rdy_out,

    // Data signals
    input  INT_T numerator_in,
    input  INT_T denominator_in,
    output INT_T quotient_out
);

    // Internal pipeline registers for raw inputs
    INT_T numerator;
    INT_T denominator;
    logic valid_reg;

    // Sign & magnitude registers
    logic                      sign_numerator_reg;
    logic                      sign_denominator_reg;
    logic                      sign_quotient_reg;
    logic [`INTEGER_WIDTH-1:0] abs_numerator_reg;
    logic [`INTEGER_WIDTH-1:0] abs_denominator_reg;

    // Quotient magnitude and signed result
    logic [`INTEGER_WIDTH-1:0] abs_quotient;
    logic [`INTEGER_WIDTH-1:0] quotient_signed;

    // Handshake
    assign vld_out = valid_reg;
    assign rdy_out = rdy_in || !valid_reg;

    // Latch inputs and precompute sign/abs once per transaction
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            numerator            <= '0;
            denominator          <= '0;
            valid_reg            <= 1'b0;

            sign_numerator_reg   <= 1'b0;
            sign_denominator_reg <= 1'b0;
            sign_quotient_reg    <= 1'b0;
            abs_numerator_reg    <= '0;
            abs_denominator_reg  <= '0;

        end else begin
            if (vld_in && rdy_out) begin
                numerator   <= numerator_in;
                denominator <= denominator_in;
                valid_reg   <= 1'b1;
                busy        <= 1'b1;

                // Latch sign bits
                sign_numerator_reg   <= numerator_in[`INTEGER_WIDTH-1];
                sign_denominator_reg <= denominator_in[`INTEGER_WIDTH-1]; // should be 0 for l_N
                sign_quotient_reg    <= numerator_in[`INTEGER_WIDTH-1] ^ denominator_in[`INTEGER_WIDTH-1];

                // Latch absolute values (2's complement)
                abs_numerator_reg   <= numerator_in[`INTEGER_WIDTH-1] ? (~numerator_in  + 1'b1) : numerator_in;
                abs_denominator_reg <= denominator_in[`INTEGER_WIDTH-1] ? (~denominator_in + 1'b1) : denominator_in;

            end else if (rdy_in) begin
                valid_reg <= 1'b0;
            end
        end
    end

    typedef enum logic [1:0] {
        DIV_IDLE,
        DIV_RUN,
        DIV_DONE
    } div_state_e;

    div_state_e state;

    logic signed [`INTEGER_WIDTH:0] rem;   // partial remainder with extra sign bit
    logic        [`INTEGER_WIDTH-1:0] q_reg; // working quotient
    logic        [`INTEGER_WIDTH-1:0] divd;  // local copy of abs_numerator
    logic        [`INTEGER_WIDTH-1:0] divs;  // local copy of abs_denominator
    integer bit_idx;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= DIV_IDLE;
            rem        <= '0;
            q_reg      <= '0;
            divd       <= '0;
            divs       <= '0;
            bit_idx    <= 0;
            abs_quotient <= '0;
        end else begin
            case (state)
                DIV_IDLE: begin
                    if (busy && !valid_reg && abs_denominator_reg != '0) begin
                        // Initialize iterative division when a new transaction arrives
                        divd    <= abs_numerator_reg;
                        divs    <= abs_denominator_reg;
                        rem     <= '0;
                        q_reg   <= '0;
                        bit_idx <= `INTEGER_WIDTH-1;

                        state   <= DIV_RUN;
                    end else if (busy && abs_denominator_reg == '0) begin
                        // Division by zero: define quotient as 0 (or saturate if you prefer)
                        abs_quotient <= '0;
                        valid_reg    <= 1'b1;
                        busy         <= 1'b0;
                        state        <= DIV_IDLE;
                    end
                end

                DIV_RUN: begin
                    // Compute next remainder and quotient bit
                    logic signed [`INTEGER_WIDTH:0] rem_next;

                    // Shift remainder left and bring in next dividend bit
                    rem_next      = rem <<< 1;
                    rem_next[0]   = divd[bit_idx];

                    // Non-restoring add/sub based on sign of previous remainder
                    if (rem >= 0) rem_next = rem_next - {1'b0, divs};
                    else rem_next = rem_next + {1'b0, divs};

                    // Set quotient bit for this position
                    q_reg[bit_idx] <= (rem_next >= 0);

                    // Update remainder
                    rem <= rem_next;

                    // Move to next bit or finish
                    if (bit_idx == 0) state <= DIV_DONE;
                    else bit_idx <= bit_idx - 1;
                    
                end

                DIV_DONE: begin
                    // Final corrective step for negative remainder (standard non-restoring)
                    if (rem < 0) rem <= rem + {1'b0, divs};
                    // Latch final quotient magnitude
                    abs_quotient <= q_reg;
                    // Mark result valid and clear busy
                    valid_reg    <= 1'b1;
                    busy         <= 1'b0;
                    // Return to idle; next transaction will restart FSM
                    state        <= DIV_IDLE;
                end

            endcase
        end
    end
    // Combinational division placeholder
    always_comb begin
        quotient_signed = sign_quotient_reg ? (~abs_quotient + 1'b1) : abs_quotient;
    end

    // Final output assignment for quotient sign
    assign quotient_out = quotient_signed;
endmodule
