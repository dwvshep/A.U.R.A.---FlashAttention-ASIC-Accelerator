//This module computes the exponential multiplication of the score and the maximum score

//Formula: vec_out[i] = exp(a - b) * vec_in[i]

module expmul_stage(
    //control signals
    input clk,
    input rst,

    //Handshake signals
    input vld_in,
    input rdy_in,
    output vld_out,
    output rdy_out,

    //Data signals
    input INT_T a_in,
    input INT_T b_in,
    input STAR_VECTOR_T v_in,
    output STAR_VECTOR_T v_out
);

    //Internal Pipeline Registers
    INT_T a;
    INT_T b;
    STAR_VECTOR_T v;
    logic valid_reg;

    assign vld_out = valid_reg;
    assign rdy_out = rdy_in;

    //Latch inputs first
    always_ff @(posedge clk) begin
        if(rst) begin
            a <= '0;
            b <= '0;
            v <= '0;
            valid_reg <= 1'b0;
        end else begin
            if(vld_in && rdy_in) begin //Handshake successful
                a <= a_in;
                b <= b_in;
                v <= v_in;
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