`include "include/sys_defs.svh"

module q_align_frac #(
    parameter int IN_I, 
    parameter int IN_F,
    parameter int OUT_F,
    localparam int W_IN  = `Q_WIDTH(IN_I, IN_F),
    localparam int W_OUT = `Q_WIDTH(IN_I, OUT_F)
)(
    input logic signed [W_IN-1:0] in,
    output logic signed [W_OUT-1:0] out
);
    
    logic signed [W_OUT-1:0] temp;

    always_comb begin
        // Same number of fractional bits → sign extend only
        if (OUT_F == IN_F) begin
            temp = in;

        // Need MORE fractional bits → LEFT SHIFT
        end else if (OUT_F > IN_F) begin
            temp = {in, {(OUT_F-IN_F){1'b0}}};

        // Need FEWER fractional bits → RIGHT SHIFT
        end else begin // OUT_F < IN_F
            temp = (in >>> (IN_F-OUT_F));
        end

        out = temp;
    end
endmodule