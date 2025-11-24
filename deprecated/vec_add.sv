//This module computes the element-wise addition of two vectors

module vec_add #(
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
    input  logic [DATA_WIDTH-1:0] a_in [VEC_LEN],
    input  logic [DATA_WIDTH-1:0] b_in [VEC_LEN],
    output logic [DATA_WIDTH-1:0] sum [VEC_LEN]
);

    //Internal Pipeline Registers
    logic [DATA_WIDTH-1:0] a [VEC_LEN];  
    logic [DATA_WIDTH-1:0] b [VEC_LEN];
    logic valid_reg;

    assign vld_out = valid_reg;
    assign rdy_out = rdy_in || !valid_reg;

    //Latch inputs first
    always_ff @(posedge clk) begin
        if(rst) begin
            a <= '0;
            b <= '0;
            valid_reg <= 1'b0;
        end else begin
            if(vld_in && rdy_out) begin //Handshake successful
                a <= a_in;
                b <= b_in;
                valid_reg <= 1'b1;
            end else if(rdy_in) begin //Only downstream is ready (clear internal pipeline)
                valid_reg <= 1'b0;
            end
        end
    end
    
    //output is combinational
    always_comb begin
        for (int i = 0; i < VEC_LEN; i++) begin
            sum[i] = a[i] + b[i];
        end
    end

endmodule