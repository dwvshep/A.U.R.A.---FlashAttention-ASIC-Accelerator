//This module computes the exponential multiplication of the score and the maximum score

//Formula: vec_out[i] = exp(a - b) * vec_in[i]

/*
Algorithm:

Stage 1:
    diff = a - b

Stage 2:
    Log2Exp(X) = −⌊X + (X ≫ 1) − (Xˆ ≫ 4)⌉
    X is an INT8 (i.e XXXXXXXX.)
    define intermediate 8 bit fixed point variables m and n
    m will be represented as 7 integer bits and 1 fractional bit
    n will be represented as 4 integer bits and 4 fractional bits
    Therefore, this formula: m = x >> 1 is the same as m = x
    and this formula: n = x >> 4 is the same as n = x
*/

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
    input [`DOT_PRODUCT_SIZE-1:0] a_in,
    input [`DOT_PRODUCT_SIZE-1:0] b_in,
    input STAR_VECTOR_T_IN v_in,
    output STAR_VECTOR_T_OUT v_out
);

    //Internal Pipeline Registers
    INT_T a;
    INT_T b;
    INT_T x;
    STAR_VECTOR_T v;
    logic valid_reg;
    INT_T l_hat, l_hat_next;
    logic [`MAX_EMBEDDING_DIM+1][`INTEGER_WIDTH+15:0] shift_stage_1_result;
    logic [`MAX_EMBEDDING_DIM+1][`INTEGER_WIDTH+23:0] shift_stage_2_result;
    logic [`MAX_EMBEDDING_DIM+1][`INTEGER_WIDTH+27:0] shift_stage_3_result;
    logic [`MAX_EMBEDDING_DIM+1][`INTEGER_WIDTH+29:0] shift_stage_4_result;
    logic [`MAX_EMBEDDING_DIM+1][`INTEGER_WIDTH+30:0] shift_stage_5_result;

    INT_T int_portion_x;

    assign vld_out = valid_reg;
    assign rdy_out = rdy_in || !valid_reg;
    assign x = a - b;
    assign int_portion_x = x >> 7; //remove the bits that represent the "decimal" portion of the real unquantized value, value of shift is subject
                                   //to change depending on format of incoming data

    //Latch inputs first
    always_ff @(posedge clk) begin
        if(rst) begin
            a <= '0;
            b <= '0;
            v <= '0;
            x <= '0;
            valid_reg <= 1'b0;
        end else begin
            if(vld_in && rdy_out) begin //Handshake successful
                a <= a_in;
                b <= b_in;
                v <= v_in;
                valid_reg <= 1'b1;
            end else if(rdy_in) begin //Only downstream is ready (clear internal pipeline)
                valid_reg <= 1'b0;
            end
            l_hat <= l_hat_next;
        end
    end

    //output is combinational
    always_comb begin
        l_hat_next = int_portion_x + int_portion_x >> 1 - int_portion_x >> 4;
    end 

    generate 
        for (genvar i = 0; i < `MAX_EMBEDDING_DIM+1; i++) begin
            assign shift_stage_1_result[i] = l_hat[4] ? {v[i], 16'h0000} >> 16 : {v[i], 4'h0000};
            assign shift_stage_2_result[i] = l_hat[3] ? {v[i], 8'b00000000}


endmodule