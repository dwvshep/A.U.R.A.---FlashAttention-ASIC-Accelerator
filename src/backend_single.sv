//This module implements the backend single processing element (PE) for the AURA architecture.

module AURA_PE(
    input clk, // System clock
    input rst, // System reset

    //Handshake Signals
    input inputs_valid,
    input ctrl_ready,
    output output_valid,
    output backend_ready,

    //Data Signals
    input Q_VECTOR_T q_vector,
    input K_VECTOR_T k_vector,
    input V_VECTOR_T v_vector,
    output O_VECTOR_T output_vector_scaled
);

    //Internal Data Signals
    V_VECTOR_T v_vector_delayed;
    V_VECTOR_T v_vector_double_delayed;
    INT_T score;
    INT_T score_delayed;
    INT_T max_score;
    INT_T max_score_prev;
    STAR_VECTOR_T exp_o_vector;
    STAR_VECTOR_T exp_v_vector;
    STAR_VECTOR_T output_vector;

    //Internal Handshake Signals
    logic dot_product_valid;
    logic max_valid;
    logic max_ready;
    logic expmul_valid;
    logic expmul_ready;
    logic vec_add_valid;
    logic vec_add_ready;
    logic vector_division_ready;

    //Internal Data Flow Modules
    dot_product dot_product_inst (
        .clk(clk),
        .rst(rst),
        .vld_in(inputs_valid),
        .rdy_in(max_ready),
        .vld_out(dot_product_valid),
        .rdy_out(backend_ready),
        .q_in(q_vector),
        .k_in(k_vector),
        .v_in(v_vector),
        .s_out(score),
        .v_out(v_vector_delayed)
    );

    max max_inst (
        .clk(clk),
        .rst(rst),
        .vld_in(dot_product_valid),
        .rdy_in(expmul_ready),
        .vld_out(max_valid),
        .rdy_out(max_ready),
        .s_in(score),
        .m_prev_in(max_score),
        .v_in(v_vector_delayed),
        .m_out(max_score),
        .s_out(score_delayed),
        .m_prev_out(max_score_prev),
        .v_out(v_vector_double_delayed)
    );

    expmul expmul_inst (
        .clk(clk),
        .rst(rst),
        .vld_in(max_valid),
        .rdy_in(vec_add_ready),
        .vld_out(expmul_valid),
        .rdy_out(expmul_ready),
        .m_in(max_score),
        .m_prev_in(max_score_prev),
        .o_star_prev_in(output_vector),
        .s_in(score_delayed),
        .v_star_in({1, v_vector_double_delayed}),
        .exp_v_out(exp_v_vector),
        .exp_o_out(exp_o_vector)
    );

    vec_add vec_add_inst (
        .clk(clk),
        .rst(rst),
        .vld_in(expmul_valid),
        .rdy_in(vector_division_ready),
        .vld_out(vec_add_valid),
        .rdy_out(vec_add_ready),
        .vec_a_in(exp_o_vector),
        .vec_b_in(exp_v_vector),
        .vec_out(output_vector)
    );

    vector_division vector_division_inst (
        .clk(clk),
        .rst(rst),
        .vld_in(vec_add_valid),
        .rdy_in(ctrl_ready),
        .vld_out(output_valid),
        .rdy_out(vector_division_ready),
        .vec_in(output_vector[`MAX_EMBEDDING_DIM-1:0]),
        .divisor_in(output_vector[`MAX_EMBEDDING_DIM]),
        .vec_out(output_vector_scaled)
    );

endmodule