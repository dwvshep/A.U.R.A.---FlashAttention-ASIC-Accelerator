`include "include/sys_defs.svh"

module q_saturate #(
    parameter int W_OUT, 
    parameter int W_IN
)(
    input logic signed [W_IN-1:0] in,
    output logic signed [W_OUT-1:0] out
);
    localparam logic signed [W_OUT-1:0] MAXV = {1'b0, {(W_OUT-1){1'b1}}};
    localparam logic signed [W_OUT-1:0] MINV = {1'b1, {(W_OUT-1){1'b0}}};

    always_comb begin
        if (in > MAXV)
            out = MAXV;
        else if (in < MINV)
            out = MINV;
        else
            out = in[W_OUT-1:0];  // truncation is safe
    end
endmodule