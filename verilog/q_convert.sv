`include "include/sys_defs.svh"

module q_convert #(
    parameter int IN_I, 
    parameter int IN_F,
    parameter int OUT_I, 
    parameter int OUT_F,
    localparam int W_IN  = `Q_WIDTH(IN_I, IN_F),
    localparam int W_MID = `Q_WIDTH(IN_I, OUT_F),
    localparam int W_OUT = `Q_WIDTH(OUT_I, OUT_F)
)(
    input logic signed [W_IN-1:0] in,
    output logic signed [W_OUT-1:0] out
);

    logic signed [W_MID-1:0] frac_aligned;
    logic signed [W_OUT-1:0] int_aligned;

    q_align_frac #(.IN_I(IN_I), .IN_F(IN_F), .OUT_F(OUT_F)) frac_inst (
        .in(in),
        .out(frac_aligned)
    );
    q_align_int #(.IN_I(IN_I), .IN_F(OUT_F), .OUT_I(OUT_I), .OUT_F(OUT_F)) int_inst (
        .in(frac_aligned),
        .out(int_aligned)
    );

    assign q_convert = int_aligned;

endmodule