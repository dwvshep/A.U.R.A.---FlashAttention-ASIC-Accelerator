//This modeule computes the dot product between a Q vector and a K vector
//The result is then scaled by dividing by the square root of the matrix dimension
//If we assume dk = 64, then dividing by root dk is equivalent to >> 3

module dot_product(
    //control signals
    input clk,
    input rst,

    //Handshake signals
    input vld_in,   //Upstream valid
    input rdy_in,   //Downstream ready
    output vld_out, //Outputs from this cycle will are valid
    output rdy_out, //Ready to accept new inputs

    //Data signals
    input Q_VECTOR_T q_in,
    input K_VECTOR_T k_in,
    output INT_T s_out
);

    //Internal Pipeline Registers
    Q_VECTOR_T q;
    K_VECTOR_T k;
    logic valid_reg;

    assign vld_out = valid_reg;
    assign rdy_out = rdy_in;

    //Latch inputs first
    always_ff @(posedge clk) begin
        if(rst) begin
            q <= '0;
            k <= '0;
            valid_reg <= 1'b0;
        end else begin
            if(vld_in && rdy_in) begin //Handshake successful
                q <= q_in;
                k <= k_in;
                valid_reg <= 1'b1;
            end else if(rdy_in) begin //Only downstream is ready (clear internal pipeline)
                valid_reg <= 1'b0;
            end
        end
    end

    //output is combinational
    always_comb begin
        
    end


endmodule