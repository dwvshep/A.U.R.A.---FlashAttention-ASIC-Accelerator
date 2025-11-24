
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
    logic busy; 
    localparam FBITS = 8;

    // -------------------------------------------------------------------------
    // INPUT LATCH: capture sign and magnitude when new transaction arrives
    // -------------------------------------------------------------------------
    // always_ff @(posedge clk or posedge rst) begin
    //     if (rst) begin

    //     end else begin
    //         if (vld_in && rdy_out) begin

    //         end else if(rdy_in) begin //Only downstream is ready (clear internal pipeline)
    //             valid_reg <= 1'b0;
    //         end
    //     end
    // end



    q_convert  #(
        .IN_I(`DIV_INPUT_I),
        .IN_F(`DIV_INPUT_F),
        .OUT_I(`OUTPUT_VEC_I),
        .OUT_F(`OUTPUT_VEC_F)
    ) div_conv (
        .in(),
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
            end else if (i == WIDTH-1 && quo_next[WIDTH-1:WIDTH-FBITSW] != 0) begin  // overflow?
                busy <= 0;
                done <= 1;
                ovf <= 1;
                val <= 0;
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
            dbz <= 0;
            ovf <= 0;
            val <= 0;
        end
    end
endmodule







module divu #(
    parameter WIDTH=8,  // width of numbers in bits (integer and fractional)
    parameter FBITS=4   // fractional bits within WIDTH
    ) (
    input wire logic clk,    // clock
    input wire logic rst,    // reset
    input wire logic start,  // start calculation
    output     logic busy,   // calculation in progress
    output     logic done,   // calculation is complete (high for one tick)
    output     logic valid,  // result is valid
    output     logic dbz,    // divide by zero
    output     logic ovf,    // overflow
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
            ovf <= 0;
            i <= 0;
            if (b == 0) begin  // catch divide by zero
                busy <= 0;
                done <= 1;
                dbz <= 1;
            end else begin
                busy <= 1;
                dbz <= 0;
                b1 <= b;
                {acc, quo} <= {{WIDTH{1'b0}}, a, 1'b0};  // initialize calculation
            end
        end else if (busy) begin
            if (i == ITER-1) begin  // done
                busy <= 0;
                done <= 1;
                valid <= 1;
                val <= quo_next;
            end else if (i == WIDTH-1 && quo_next[WIDTH-1:WIDTH-FBITSW] != 0) begin  // overflow?
                busy <= 0;
                done <= 1;
                ovf <= 1;
                val <= 0;
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
            dbz <= 0;
            ovf <= 0;
            val <= 0;
        end
    end
endmodule