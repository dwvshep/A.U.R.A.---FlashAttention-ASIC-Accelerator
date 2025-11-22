// -----------------------------------------------------------------------------
// Signed integer division for Q-format values
// Inputs:  numerator_in, denominator_in are Q9.7  (DIV_INPUT_QT)
// Output: quotient_out is Q0.7                   (OUTPUT_VEC_QT)
// Internally performs:  (abs(num) << 7) / abs(den)
// Uses non-restoring division for iterative quotient generation
// -----------------------------------------------------------------------------
`include "include/sys_defs.svh"

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
    input  DIV_INPUT_QT numerator_in,
    input  DIV_INPUT_QT denominator_in,
    output OUTPUT_VEC_QT quotient_out
);

    localparam int DIV_INPUT_W = $bits(DIV_INPUT_QT);

    // Divider working registers
    logic signed [DIV_INPUT_W:0] rem;   // remainder with sign bit
    logic signed [DIV_INPUT_W:0] rem_next;
    logic [DIV_INPUT_W-2:0] q_reg;                            // Q0.7 working quotient bits
    DIV_INPUT_QT divd;                   // |numerator| << 7
    DIV_INPUT_QT divs;                   // |denominator|
    logic [$clog2(DIV_INPUT_W+1)-1:0] bit_idx;

    // -------------------------------------------------------------------------
    // Internal control registers
    // -------------------------------------------------------------------------
    logic valid_reg;
    logic busy;   // <--- moved here (declared BEFORE first use)

    // -------------------------------------------------------------------------
    // Sign + absolute value registers (Q9.7)
    // -------------------------------------------------------------------------
    logic            sign_numerator_reg;
    logic            sign_denominator_reg;
    logic            sign_quotient_reg;
    DIV_INPUT_QT abs_numerator_reg;
    DIV_INPUT_QT abs_denominator_reg;

    // -------------------------------------------------------------------------
    // Output quotient (Q0.7 magnitude + signed output)
    // -------------------------------------------------------------------------
    
    //OUTPUT_VEC_QT abs_quotient;
    logic [DIV_INPUT_W-2:0] abs_quotient;

    logic [DIV_INPUT_W-1:0] quotient_signed;

    // -------------------------------------------------------------------------
    // Handshake
    // - Cannot accept new inputs while busy
    // - Valid_out means output is ready
    // -------------------------------------------------------------------------
    assign vld_out = valid_reg;
    assign rdy_out = !busy && (rdy_in || !valid_reg);

    // -------------------------------------------------------------------------
    // Divider FSM States
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        DIV_IDLE,
        DIV_RUN,
        DIV_DONE
    } div_state_e;

    div_state_e state;

    // -------------------------------------------------------------------------
    // INPUT LATCH: capture sign and magnitude when new transaction arrives
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            busy                 <= 1'b0;
            sign_numerator_reg   <= 1'b0;
            sign_denominator_reg <= 1'b0;
            sign_quotient_reg    <= 1'b0;
            abs_numerator_reg    <= '0;
            abs_denominator_reg  <= '0;

        end else begin
            if (vld_in && rdy_out) begin
                busy <= 1'b1;

                // Sign bits
                sign_numerator_reg   <= numerator_in[DIV_INPUT_W-1];
                sign_denominator_reg <= denominator_in[DIV_INPUT_W-1];
                sign_quotient_reg    <= numerator_in[DIV_INPUT_W-1] ^
                                        denominator_in[DIV_INPUT_W-1];

                // Magnitude (abs value)
                abs_numerator_reg   <= numerator_in[DIV_INPUT_W-1]
                                       ? (~numerator_in  + 1'b1)
                                       :  numerator_in;

                abs_denominator_reg <= denominator_in[DIV_INPUT_W-1]
                                       ? (~denominator_in + 1'b1)
                                       :  denominator_in;

            end else if (rdy_in && valid_reg) begin
                // Downstream consumed the output → free divider
                busy <= 1'b0;
            end
        end
        $display("state: %0b", state); // DEBUG
        $display("divd: %0d, divs: %0d, bit_idx: %0d", divd, divs, bit_idx); // DEBUG
        $display("rem: %0d, rem_next: %0d", rem, rem_next); // DEBUG
        $display("quotient_out: %0d, q_reg: %0d, abs_quotient: %0d, quotient_signed: %0d\n", quotient_out, q_reg, abs_quotient, quotient_signed); // DEBUG, 
        
    end



    

    // -------------------------------------------------------------------------
    // DIVIDER FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= DIV_IDLE;
            rem          <= '0;
            q_reg        <= '0;
            divd         <= '0;
            divs         <= '0;
            bit_idx      <= '0;
            abs_quotient <= '0;
            valid_reg    <= 1'b0;

        end else begin
            // Drop valid when downstream accepts the output
            if (valid_reg && rdy_in)
                valid_reg <= 1'b0;

            case (state)

                // -------------------------------------------------------------
                // IDLE: Wait for busy=1 (new transaction latched)
                // -------------------------------------------------------------
                DIV_IDLE: begin
                    if (busy && !valid_reg && abs_denominator_reg != '0) begin
                        // Init non-restoring division
                        divd    <= abs_numerator_reg <<< `DIV_INPUT_F;  // scale numerator
                        divs    <= abs_denominator_reg;
                        rem     <= '0;
                        q_reg   <= '0;
                        bit_idx <= DIV_INPUT_W-1;
                        state   <= DIV_RUN;

                    end else if (busy && abs_denominator_reg == '0) begin
                        // Division by zero → output = 0
                        abs_quotient <= '0;
                        valid_reg    <= 1'b1;
                        state        <= DIV_IDLE;
                    end
                end

                // -------------------------------------------------------------
                // RUN: iterate through bits
                // -------------------------------------------------------------
                DIV_RUN: begin

                    // Shift remainder left + inject next input bit
                    rem_next      = rem <<< 1;
                    rem_next[0]   = divd[bit_idx];

                    // Non-restoring update
                    if (rem >= 0) rem_next = rem_next - {1'b0, divs};
                    else          rem_next = rem_next + {1'b0, divs};

                    // Save quotient bit if in Q0.7 range
                    //if (bit_idx <= 7)
                        q_reg[bit_idx] <= (rem_next >= 0);

                    // State update
                    rem <= rem_next;

                    if (bit_idx == 0)
                        state <= DIV_DONE;
                    else
                        bit_idx <= bit_idx - 1;
                end

                // -------------------------------------------------------------
                // DONE: perform final correction & publish result
                // -------------------------------------------------------------
                DIV_DONE: begin
                    // Correction cycle (does not affect quotient bits)
                    if (rem < 0)
                        rem <= rem + {1'b0, divs};

                    abs_quotient <= q_reg;
                    valid_reg    <= 1'b1;
                    state        <= DIV_IDLE;
                end

            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Apply sign in two's complement
    // -------------------------------------------------------------------------
    always_comb begin
        quotient_signed = {sign_quotient_reg, {sign_quotient_reg
                          ? (~abs_quotient + 1'b1)
                          :  abs_quotient}};
    end

    // Final output
    q_convert  #(
        .IN_I(`DIV_INPUT_I),
        .IN_F(`DIV_INPUT_F),
        .OUT_I(`OUTPUT_VEC_I),
        .OUT_F(`OUTPUT_VEC_F)
    ) div_conv (
        .in(quotient_signed),
        .out(quotient_out)
    );
    //assign quotient_out = quotient_signed;

endmodule
