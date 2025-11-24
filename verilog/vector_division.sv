//This module performs element-wise division of a vector by a scalar divisor

module vector_division #(
    parameter int VEC_LEN = `MAX_EMBEDDING_DIM,          // Number of elements in the vector
    parameter int DATA_WIDTH = `INTEGER_WIDTH       // Bit width of each element
)(
    // Control signals
    input  clk,
    input  rst,

    // Handshake signals
    input  vld_in,
    input  rdy_in,
    output vld_out,
    output rdy_out,

    // Data signals
    //input  logic [DATA_WIDTH-1:0] vec_in [VEC_LEN],
    input  STAR_VECTOR_T vec_in,
    input  EXPMUL_VEC_QT divisor_in, //single element (l)
    output O_VECTOR_T vec_out,
);

    generate
        for (genvar i = 1; i <= VEC_LEN; i++) begin : gen_div
            int_division div_inst (
                .clk(clk),
                .rst(rst),
                .vld_in(vld_in),
                .rdy_in(rdy_in),
                .vld_out(vld_out), //Connect this to top-level if needed
                .rdy_out(rdy_out), //Connect this to top-level if needed
                .numerator_in(vec[i]),
                .denominator_in(vec[0]),
                .quotient_out(vec_out[i])
            );
        end
    endgenerate

endmodule