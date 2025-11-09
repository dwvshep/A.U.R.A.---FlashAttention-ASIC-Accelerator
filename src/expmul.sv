//This mpodule computes the exponential multiplication of the score and the maximum score

//Formula: vec_out[i] = exp(a - b) * vec_in[i]

module expmul(
    //control signals
    input clk,
    input rst,

    //Handshake signals
    input vld_in,
    input rdy_in,
    output vld_out,
    output rdy_out,

    //Data signals
    input INT_T a,
    input INT_T b,
    input V_VECTOR_T vec_in,
    output V_VECTOR_T vec_out
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