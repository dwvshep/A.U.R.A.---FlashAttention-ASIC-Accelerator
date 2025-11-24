
`include "include/sys_defs.svh"

module int_division(
    // Control signals
    input  logic clk,
    input  logic rst,

    // Upstream
    input  logic vld_in,    // data from upstream is valid
    output logic rdy_out,   // ready to accept input from upstream

    // Downstream
    input  logic rdy_in,    // downstream is ready to accept output
    output logic vld_out,   // sending valid data to downstream

    // Data signals
    input  DIV_INPUT_QT numerator_in,
    input  DIV_INPUT_QT denominator_in,
    output OUTPUT_VEC_QT quotient_out
);

    localparam int DIV_INPUT_W = $bits(DIV_INPUT_QT);

    // -------------------------------------------------------------------------
    // Internal Registers
    // -------------------------------------------------------------------------
    logic sign_n, sign_d, sign_q; 
    logic [DIV_INPUT_W-2:0] abs_num, abs_den;

    logic start_div;
    logic div_busy, div_done, div_valid;

    logic [DIV_INPUT_W-2:0] div_unsigned_q;
    DIV_INPUT_QT signed_q;

    logic valid_reg;

    assign rdy_out = !valid_reg && !div_busy;
    assign vld_out = valid_reg;

    //assign start_div = vld_in && rdy_out;

    // -------------------------------------------------------------------------
    // INPUT LATCH: capture sign and magnitude when new transaction arrives
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_reg <= 1'b0;
            start_div <= 1'b0;
            sign_n    <= 1'b0;
            sign_d    <= 1'b0;
            sign_q    <= 1'b0;
            abs_num   <= '0;
            abs_den   <= '0;
        end else begin
            //pulses for one cycle whenever we hanshake
            start_div <= vld_in && rdy_out;

            if (vld_in && rdy_out) begin
                // Extract signs
                sign_n <= numerator_in[DIV_INPUT_W-1];
                sign_d <= denominator_in[DIV_INPUT_W-1];
                sign_q <= numerator_in[DIV_INPUT_W-1] ^ denominator_in[DIV_INPUT_W-1];

                // Abs values
                abs_num <= numerator_in[DIV_INPUT_W-1] ? (~numerator_in[DIV_INPUT_W-2:0] + 1'b1) :  numerator_in[DIV_INPUT_W-2:0];
                abs_den <= denominator_in[DIV_INPUT_W-1] ? (~denominator_in[DIV_INPUT_W-2:0] + 1'b1) : denominator_in[DIV_INPUT_W-2:0];

                valid_reg <= 1'b0; //division not done
            end

            if(div_done) begin //capture output when divider finishes
                valid_reg <= 1'b1;
            `ifdef INT_DIV_DEBUG
                $display("[DIV_DBG] DONE div_unsigned_q=%0d sign_q=%0b", div_unsigned_q, sign_q);
            `endif
            end

            if (valid_reg && rdy_in) begin //clear when downstream accpets
                valid_reg <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // DIVU Module Instance: unsigned division
    // -------------------------------------------------------------------------

    divu #(
        .WIDTH(DIV_INPUT_W-1),              // your Q_WIDTH-1 config matches the type
        .FBITS(`DIV_INPUT_F)
    ) div_inst (
        .clk   (clk),
        .rst   (rst),
        .start (start_div),
        .busy  (div_busy),
        .done  (div_done),
        .valid (div_valid),
        .a     (abs_num),
        .b     (abs_den),
        .val   (div_unsigned_q)
    );

    always_comb begin
        if (sign_q)
            signed_q = {sign_q, ~div_unsigned_q + 1};
        else
            signed_q = {sign_q, div_unsigned_q};
    end

    q_convert  #(
        .IN_I(`DIV_INPUT_I),
        .IN_F(`DIV_INPUT_F),
        .OUT_I(`OUTPUT_VEC_I),
        .OUT_F(`OUTPUT_VEC_F)
    ) div_conv (
        .in(signed_q),
        .out(quotient_out)
    );

endmodule

// -------------------------------------------------------------------------



module divu #(
    parameter WIDTH=`Q_WIDTH(`DIV_INPUT_I, `DIV_INPUT_F) - 1,  // width of numbers in bits (integer and fractional)
    parameter FBITS= `DIV_INPUT_F   // fractional bits within WIDTH
    ) (
    input  clk,    // clock
    input  rst,    // reset
    input wire logic start,  // start calculation
    output     logic busy,   // calculation in progress
    output     logic done,   // calculation is complete (high for one tick)
    output     logic valid,  // result is valid
    input wire logic [WIDTH-1:0] a,   // dividend (numerator)
    input wire logic [WIDTH-1:0] b,   // divisor (denominator)
    output     logic [WIDTH-1:0] val  // result value: quotient
    );

    localparam FBITSW = (FBITS == 0) ? 1 : FBITS;  // avoid negative vector width when FBITS=0

    logic [WIDTH-1:0] b1;             // copy of divisor
    logic [WIDTH-1:0] quo, quo_next;  // intermediate quotient
    logic [WIDTH:0] acc, acc_next;    // accumulator (1 bit wider)

    localparam ITER = WIDTH + FBITS;  // iteration count: unsigned input width + fractional bits
    logic [$clog2(ITER)-1:0] i;       // iteration counter

    // division algorithm iteration
    always_comb begin
        if (acc >= {1'b0, b1}) begin
            acc_next = acc - b1;
            {acc_next, quo_next} = {acc_next[WIDTH-1:0], quo, 1'b1};
        end else begin
            {acc_next, quo_next} = {acc, quo} << 1;
        end
    end

    // calculation control
    always_ff @(posedge clk) begin
        done <= 0;
        if (start) begin
            valid <= 0;
            i <= 0;
            busy <= 1;
            b1 <= b;
            {acc, quo} <= {{WIDTH{1'b0}}, a, 1'b0};  // initialize calculation
        end else if (busy) begin
            if (i == ITER-1) begin  // done
                busy <= 0;
                done <= 1;
                valid <= 1;
                val <= quo_next;
            end else begin  // next iteration
                i <= i + 1;
                acc <= acc_next;
                quo <= quo_next;
            end
        end
        if (rst) begin
            busy <= 0;
            done <= 0;
            valid <= 0;
            val <= 0;
        end
    end
endmodule