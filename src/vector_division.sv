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
    input  logic [DATA_WIDTH-1:0] vec_in [VEC_LEN],
    input  logic [DATA_WIDTH-1:0] divisor_in,
    output logic [DATA_WIDTH-1:0] vec_out [VEC_LEN]
);

    //Internal Pipeline Registers
    logic [DATA_WIDTH-1:0] vec [VEC_LEN];  
    logic [DATA_WIDTH-1:0] divisor;
    logic valid_reg;

    assign vld_out = valid_reg;
    assign rdy_out = rdy_in;

    //Latch inputs first
    always_ff @(posedge clk) begin
        if(rst) begin
            vec <= '0;
            divisor <= '0;
            valid_reg <= 1'b0;
        end else begin
            if(vld_in && rdy_in) begin //Handshake successful
                vec <= vec_in;
                divisor <= divisor_in;
                valid_reg <= 1'b1;
            end else if(rdy_in) begin //Only downstream is ready (clear internal pipeline)
                valid_reg <= 1'b0;
            end
        end
    end
    
    //Use this if division module is combinational
    generate
        for (genvar i = 0; i < VEC_LEN; i++) begin : gen_div_comb
            int_div_comb div_comb_inst (
                .numerator_in(vec[i]),
                .denominator_in(divisor),
                .quotient_out(vec_out[i])
            );
        end
    endgenerate

    //Use this if division module is pipelined
    //But remember to not latch inputs in this top module so you dont waste an extra cycle
    //Also add support for internal valid-ready signals
    generate
        for (genvar i = 0; i < VEC_LEN; i++) begin : gen_div
            int_division div_inst (
                .clk(clk),
                .rst(rst),
                .vld_in(vld_in),
                .rdy_in(rdy_in),
                .vld_out(), //Connect this to top-level if needed
                .rdy_out(), //Connect this to top-level if needed
                .numerator_in(vec[i]),
                .denominator_in(divisor),
                .quotient_out(vec_out[i])
            );
        end
    endgenerate

endmodule