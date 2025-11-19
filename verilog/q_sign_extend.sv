`include "include/sys_defs.svh"

module q_sign_extend #(
    parameter int W_IN, 
    parameter int W_OUT
)(
    input logic signed [W_IN-1:0] in,
    output logic signed [W_OUT-1:0] out
);

    assign out = {{(W_OUT-W_IN){in[W_IN-1]}}, in};

endmodule