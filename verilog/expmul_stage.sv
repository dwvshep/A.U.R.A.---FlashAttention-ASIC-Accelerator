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

`include "include/sys_defs.svh"

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
    input EXPMUL_DIFF_IN_QT a_in, //Q4.4
    input EXPMUL_DIFF_IN_QT b_in, //Q4.4
    input STAR_VECTOR_T v_in, //Q9.17
    output STAR_VECTOR_T v_out, //Q9.17,
    output logic [$clog2(`MAX_SEQ_LENGTH)-1:0] kv_counter,

    //Mode setting
    input o_star_mode
);

    //Internal Pipeline Registers
    EXPMUL_DIFF_IN_QT a;
    EXPMUL_DIFF_IN_QT b;
    EXPMUL_DIFF_OUT_QT x_diff;
    EXPMUL_LOG2E_IN_QT x_diff_condensed;
    EXPMUL_LOG2E_OUT_QT log_e_x;
    STAR_VECTOR_T v, v_stage_2;
    logic stage_1_valid, stage_2_valid, stage_1_ready, stage_2_ready;
    EXPMUL_SHIFT_STAGE_QT shift_stage_1_1, shift_stage_2_1, shift_stage_3_1, shift_stage_4_1, shift_stage_5_1;
    EXPMUL_EXP_QT l_hat, l_hat_next;
    EXPMUL_SHIFT_VECTOR_T v_stage_2_expanded;
    EXPMUL_SHIFT_VECTOR_T shift_stage_1_result; //Q9.23
    EXPMUL_SHIFT_VECTOR_T shift_stage_2_result; //Q9.23
    EXPMUL_SHIFT_VECTOR_T shift_stage_3_result; //Q9.23
    EXPMUL_SHIFT_VECTOR_T shift_stage_4_result; //Q9.23
    EXPMUL_SHIFT_VECTOR_T shift_stage_5_result; //Q9.23
    logic [$clog2(`MAX_SEQ_LENGTH)-1:0] kv_counter;

    `Q_TYPE(6, 4) log_e_x_test;
    `Q_TYPE(5, 4) x_diff_expanded;
    EXPMUL_VEC_QT v_in_1, v_out_1, v_out_0;

    assign v_in_1 = v_in[1];
    assign v_out_1 = v_out[1];
    assign v_out_0 = v_out[0];

    assign stage_2_ready = rdy_in || (kv_counter > 0);
    assign stage_1_ready = (!stage_1_valid) || stage_2_ready;
    assign rdy_out = stage_1_ready;
    assign vld_out = stage_2_valid;
    assign x_diff = a - b;
    assign shift_stage_1_1 = shift_stage_1_result[1];
    assign shift_stage_2_1 = shift_stage_2_result[1];
    assign shift_stage_3_1 = shift_stage_3_result[1];
    assign shift_stage_4_1 = shift_stage_4_result[1];
    assign shift_stage_5_1 = shift_stage_5_result[1];
    
    //remove the bits that represent the "decimal" portion of the real unquantized value, value of shift is subject
    //to change depending on format of incoming data

    //Latch inputs first
    //First stage: Diff and then do log2e*X approximation
    always_ff @(posedge clk) begin
        if(rst) begin
            a <= '0;
            b <= '0;
            v <= '0;
            stage_1_valid <= 1'b0;
        end else begin //Handshake successful
            if (vld_in && stage_1_ready) begin
                a <= a_in;
                b <= b_in;
                v <= v_in;
                stage_1_valid <= 1'b1;
        end else if (stage_2_ready) begin
            stage_1_valid <= 0;
        end
        end
    end

    q_convert #(.IN_I(5), .IN_F(4), .OUT_I(5), .OUT_F(2)) x_diff_condense(
        .in(x_diff),
        .out(x_diff_condensed)
    );

    // q_convert #(.IN_I(5), .IN_F(4), .OUT_I(5), .OUT_F(8)) x_diff_expand(
    //     .in(x_diff),
    //     .out(x_diff_expanded)
    // );
    
    // q_convert #(.IN_I(6), .IN_F(2), .OUT_I(4), .OUT_F(0)) log_e_x_condense(
    //     .in(log_e_x),
    //     .out(l_hat_next)
    // );

    q_convert #(.IN_I(6), .IN_F(4), .OUT_I(4), .OUT_F(0)) log_e_x_condense(
        .in(log_e_x_test),
        .out(l_hat_next)
    );

    generate
        for (genvar i = 0; i < `MAX_EMBEDDING_DIM + 1; i++) begin
            q_convert #(.IN_I(9), .IN_F(23), .OUT_I(9), .OUT_F(17)) v_out_condense(
                .in(shift_stage_5_result[i]),
                .out(v_out[i])
            );
        end
    endgenerate

    generate
        for (genvar i = 0; i < `MAX_EMBEDDING_DIM + 1; i++) begin
            q_convert #(.IN_I(9), .IN_F(17), .OUT_I(9), .OUT_F(23)) v_stage_expand(
                .in(v_stage_2[i]),
                .out(v_stage_2_expanded[i])
            );
        end
    endgenerate
            

    //Second stage: 2^-L * V
    always_ff @(posedge clk) begin
        if (rst) begin
            stage_2_valid <= 1'b0;
            l_hat <= '0;
            v_stage_2 <= '0;
            kv_counter <= '0;
        end else begin
            if (stage_1_valid && stage_2_ready) begin
                stage_2_valid <= 1'b1;
                l_hat <= l_hat_next;
                v_stage_2 <= (o_star_mode == 1) ? v_in : v;
                kv_counter <= (kv_counter == 0) ? `MAX_SEQ_LENGTH-1 : kv_counter - 1;
            end else if (rdy_in) begin
                stage_2_valid <= 1'b0;
            end
        end
    end

    //output is combinational
    always_comb begin
        // log_e_x = x_diff_condensed + (x_diff_condensed >>> 1) - (x_diff_condensed >>> 4);
        log_e_x_test = x_diff + (x_diff >>> 1) - (x_diff >>> 4);
        // log_e_x_test = x_diff_expanded + (x_diff_expanded >>> 1) - (x_diff_expanded >>> 4);
    end

    generate    
        for (genvar i = 0; i < `MAX_EMBEDDING_DIM+1; i++) begin : barrel_shift_generate
            assign shift_stage_1_result[i] = l_hat[4] ? v_stage_2_expanded[i] >>> 16 : v_stage_2_expanded[i];
            assign shift_stage_2_result[i] = l_hat[3] ? shift_stage_1_result[i] <<< 8 : shift_stage_1_result[i];
            assign shift_stage_3_result[i] = l_hat[2] ? shift_stage_2_result[i] <<< 4 : shift_stage_2_result[i];
            assign shift_stage_4_result[i] = l_hat[1] ? shift_stage_3_result[i] <<< 2 : shift_stage_3_result[i];
            assign shift_stage_5_result[i] = l_hat[0] ? shift_stage_4_result[i] <<< 1 : shift_stage_4_result[i];
        end
    endgenerate

endmodule