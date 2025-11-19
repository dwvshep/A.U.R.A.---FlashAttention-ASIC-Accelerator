`include "include/sys_defs.svh"

module q_align_int #(
    parameter int IN_I, 
    parameter int IN_F,
    parameter int OUT_I, 
    parameter int OUT_F,
    localparam int W_IN  = `Q_WIDTH(IN_I, IN_F),
    localparam int W_OUT = `Q_WIDTH(IN_I, OUT_F)
)(
    input logic signed [W_IN-1:0] in,
    output logic signed [W_OUT-1:0] out
);
    
    logic signed [W_OUT-1:0] temp;

    generate
        // Same number of fractional bits → sign extend only
        if (IN_I == OUT_I) begin
            assign temp = in;

        // Need MORE fractional bits → LEFT SHIFT
        end else if (IN_I > OUT_I) begin
            q_saturate #(.W_OUT(W_OUT), .W_IN(W_IN)) q_sat_inst (
                .in(in), 
                .out(temp)
            );

        // Need FEWER fractional bits → RIGHT SHIFT
        end else begin // OUT_F < IN_F
            q_sign_extend #(.W_IN(W_IN), .W_OUT(W_OUT)) q_sign_inst (
                .in(in), 
                .out(temp)
            );
        end
    endgenerate

    assign out = temp;
endmodule