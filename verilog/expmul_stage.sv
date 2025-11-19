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

module expmul_stage (
    //control signals
    input clk,
    input rst,

    //Handshake signals
    input vld_in,
    input rdy_in,
    output vld_out,
    output rdy_out,

    //Data signals
    input SCORE_QT a_in, //Q4.3
    input SCORE_QT b_in, //Q4.3
    input EXPMUL_VSHIFT_QT v_in, //Q9.8
    output EXPMUL_VSHIFT_QT v_out //Q9.8
);

    //Internal Pipeline Registers
    SCORE_QT a;
    SCORE_QT b;
    `Q_TYPE(5, 3) x_diff;
    `Q_TYPE(5, 2) x_diff_condensed;
    `Q_TYPE(6, 6) log_e_x;
    `Q_TYPE(6, 1) log_e_x_condensed;
    EXPMUL_VSHIFT_QT v;
    logic stage_1_valid, stage_2_valid, stage_1_ready, stage_2_ready;
    `Q_TYPE(4, 0) l_hat, l_hat_next;
    EXPMUL_VSHIFT_QT [`MAX_EMBEDDING_DIM+1] shift_stage_1_result; //Q9.16
    EXPMUL_VSHIFT_QT [`MAX_EMBEDDING_DIM+1] shift_stage_2_result; //Q9.16
    EXPMUL_VSHIFT_QT [`MAX_EMBEDDING_DIM+1] shift_stage_3_result; //Q9.16
    EXPMUL_VSHIFT_QT [`MAX_EMBEDDING_DIM+1] shift_stage_4_result; //Q9.16
    EXPMUL_VSHIFT_QT [`MAX_EMBEDDING_DIM+1] shift_stage_5_result; //Q9.16

    assign stage_2_ready = rdy_in;
    assign stage_1_ready = (!stage_1_valid) || stage_2_ready;
    assign rdy_out = stage_1_ready;
    assign vld_out = stage_2_valid;
    assign x_diff = a - b;
    assign x_diff_condensed = q_convert(5, 3, 5, 2); // Convert from Q5.3 to Q5.2
    
    //remove the bits that represent the "decimal" portion of the real unquantized value, value of shift is subject
    //to change depending on format of incoming data

    //Latch inputs first
    //First stage: Diff and then do log2e*X approximation
    always_ff @(posedge clk) begin
        if(rst) begin
            a <= '0;
            b <= '0;
            v <= '0;
            x <= '0;
            stage_1_valid <= 1'b0;
        end else begin //Handshake successful
            if (vld_in && stage_1_ready) begin
                a <= a_in;
                b <= b_in;
                v <= v_in;
                stage_1_valid <= 1'b1;
        end else if (stage_1_ready) begin
            stage_1_valid <= 0;
        end
        end
    end

    //Second stage: 2^-L * V
    always_ff @(posedge clk) begin
        if (rst) begin
            stage_2_valid <= 1'b0;
        end else begin
            if (stage_1_valid && stage_2_ready) begin
                stage_2_valid <= 1'b1;
                l_hat <= l_hat_next;
            end else if (stage_2_ready) begin
                stage_2_valid <= 1'b0;
            end
        end
    end

    //output is combinational
    always_comb begin
        log_e_x = {1'b0, x_diff_condensed, 4'b0000} + {1'b0, ({x_diff_condensed, 4'b0000} >> 1)} - {1'b0, ({x_diff_condensed, 4'b0000} >> 4)};
        l_hat_next = q_convert(); //Convert Q6.6 to Q4.0
        //l_hat_next = log_e_x[12] : {1'b1, log_e_x[6 +: 4]} : '0;
    end

    generate 
        for (genvar i = 0; i < `MAX_EMBEDDING_DIM+1; i++) begin
            assign shift_stage_1_result[i] = l_hat[4] ? {v[i], 16'h0000} >> 16 : {v[i], 16'h0000};
            assign shift_stage_2_result[i] = l_hat[3] ? {v[i], 8'b00000000} >> 8 : {v[i], 8'h00};
            assign shift_stage_3_result[i] = l_hat[2] ? {v[i], 4'b0000} >> 4 : {v[i], 4'b0000};
            assign shift_stage_4_result[i] = l_hat[1] ? {v[i], 2'b00} >> 2 : {v[i], 2'b00};
            assign shift_stage_5_result[i] = l_hat[0] ? {v[i], 1'b0} >> 1 : {v[i], 1'b0};
            assign v_out[i] = q_convert(); //Convert Q9.23 to Q9.7
        end
    endgenerate

endmodule