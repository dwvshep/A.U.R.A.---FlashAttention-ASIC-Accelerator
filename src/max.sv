//This module computes the maximum between the current score and the previous maximum score

module max(
    //control signals
    input clk,
    input rst,

    //Handshake signals
    input vld_in,
    input rdy_in,
    output vld_out,
    output rdy_out,

    //Data signals
    input INT_T s_i,
    input INT_T m_i_prev,
    output INT_T m_i
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