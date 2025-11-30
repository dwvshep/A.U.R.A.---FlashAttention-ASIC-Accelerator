//This module performs element-wise division of a vector by a scalar divisor

module vector_division #(
    parameter int VEC_LEN = `MAX_EMBEDDING_DIM,          // Number of elements in the vector
    parameter int DATA_WIDTH = `INTEGER_WIDTH       // Bit width of each element
)(
    // Control signals
    input  clock,
    input  reset,

    // Handshake signals
    input  vld_in,
    input  rdy_in,
    output vld_out,
    output rdy_out,

    // Data signals
    input  STAR_VECTOR_T vec_in,
    output O_VECTOR_T vec_out
);

    // Internal signals
    DIV_INPUT_QT numerators [1:VEC_LEN];
    DIV_INPUT_QT denominator;
    logic vld_outs [1:VEC_LEN];

    q_convert #(
        .IN_I(`EXPMUL_VEC_I),
        .IN_F(`EXPMUL_VEC_F),
        .OUT_I(`DIV_INPUT_I),
        .OUT_F(`DIV_INPUT_F)
    ) denom_conv (
        .in(vec_in[0]),
        .out(denominator)
    );

    generate
        for (genvar i = 1; i <= VEC_LEN; i++) begin : gen_div
            q_convert #(
                .IN_I(`EXPMUL_VEC_I),
                .IN_F(`EXPMUL_VEC_F),
                .OUT_I(`DIV_INPUT_I),
                .OUT_F(`DIV_INPUT_F)
            ) div_conv (
                .in(vec_in[i]),
                .out(numerators[i])
            );
            int_division div_inst (
                .clock(clock),
                .reset(reset),
                .vld_in(vld_in),
                .rdy_in(rdy_in),
                .vld_out(vld_outs[i]), //Connect this to top-level if needed
                .rdy_out(rdy_out), //Connect this to top-level if needed
                .numerator_in(numerators[i]),
                .denominator_in(denominator),
                .quotient_out(vec_out[i-1])
            );
        end
    endgenerate

    assign vld_out = vld_outs[1];

endmodule