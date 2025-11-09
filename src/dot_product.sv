//This modeule computes the dot product between a Q vector and a K vector
//The result is then scaled by dividing by the square root of the matrix dimension
//If we assume dk = 64, then dividing by root dk is equivalent to >> 3

module dot_product(
    //control signals
    input clk,
    input rst,

    //Handshake signals
    input vld_in,
    input rdy_in,
    output vld_out,
    output rdy_out,

    //Data signals
    input Q_VECTOR_T q_i,
    input K_VECTOR_T k_i,
    output INT_T s_i
);

    //Latch inputs first
    always_ff @(posedge clk) begin
        if(rst) begin

        end else begin

        end
    end

    always_comb begin
        
    end


endmodule