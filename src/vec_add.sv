//This module computes the element-wise addition of two vectors

module vec_add #(
    parameter int VEC_LEN = 8,          // Number of elements in the vector
    parameter int DATA_WIDTH = 16       // Bit width of each element
)(
    // Control signals
    input  logic clk,
    input  logic rst,

    // Handshake signals
    input  logic vld_in,
    input  logic rdy_in,
    output logic vld_out,
    output logic rdy_out,

    // Data signals
    input  logic [DATA_WIDTH-1:0] a [VEC_LEN],
    input  logic [DATA_WIDTH-1:0] b [VEC_LEN],
    output logic [DATA_WIDTH-1:0] sum [VEC_LEN]
);

    //--------------------------------------------------------------------------
    // Element-wise addition
    //--------------------------------------------------------------------------

    always_comb begin
        for (int i = 0; i < VEC_LEN; i++) begin
            sum[i] = a[i] + b[i];
        end
    end

    //--------------------------------------------------------------------------
    // Simple handshake propagation (pass-through example)
    //--------------------------------------------------------------------------

    assign vld_out = vld_in;
    assign rdy_out = rdy_in;

endmodule








// module vec_add(
//     //control signals
//     input clk,
//     input rst,

//     //Handshake signals
//     input vld_in,
//     input rdy_in,
//     output vld_out,
//     output rdy_out,

//     //Data signals
//     input V_VECTOR_T a,
//     input V_VECTOR_T b,
//     output V_VECTOR_T sum
// );


// endmodule