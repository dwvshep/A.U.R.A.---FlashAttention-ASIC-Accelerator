//This module implements the backend single processing element (PE) for the AURA architecture.

module PE(
    input  clk, // System clock
    input  rst, // System reset

    //Handshake Signals
    input  Q_vld_in,     //Upstream valid
    input  K_vld_in,     //Upstream valid
    input  V_vld_in,     //Upstream valid
    output Q_rdy_out,    //Backend Q ready
    output K_rdy_out,    //Backend K ready
    output V_rdy_out,    //Backend V ready
    input  O_sram_rdy, //OSRAM ready to receive output
    output output_valid, //Output valid

    //Data Signals
    input Q_VECTOR_T q_vector,
    input K_VECTOR_T k_vector,
    input V_VECTOR_T v_vector,
    output O_VECTOR_T output_vector_scaled
);

    //Internal Data Signals
    V_VECTOR_T v_vector_delayed;
    V_VECTOR_T v_vector_double_delayed;
    STAR_VECTOR_T v_star;
    EXPMUL_DIFF_IN_QT score;
    EXPMUL_DIFF_IN_QT score_delayed;
    EXPMUL_DIFF_IN_QT max_score;
    EXPMUL_DIFF_IN_QT max_score_prev;
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

    //Generate v_star by appending 1 to v_vector_double_delayed and converting to Q9.8
    generate
        assign v_star[0] = 1;
        for(genvar v = 1; v <= `MAX_EMBEDDING_DIM; v++) begin
            q_convert #(
                .IN_I(`INPUT_VEC_I), 
                .IN_F(`INPUT_VEC_F), 
                .OUT_I(`EXPMUL_VEC_I), 
                .OUT_F(`EXPMUL_VEC_F)
            ) prod_conv_inst (
                .in(v_vector_double_delayed[v]),
                .out(v_star[v])
            );
        end
    endgenerate

    //Internal Data Flow Modules
    dot_product dot_product_inst (
        .clk(clk),
        .rst(rst),
        .Q_vld_in(Q_vld_in),
        .K_vld_in(K_vld_in),
        .V_vld_in(V_vld_in),
        .rdy_in(max_ready),
        .vld_out(dot_product_valid),
        .Q_rdy_out(Q_rdy_out),
        .K_rdy_out(K_rdy_out),
        .V_rdy_out(V_rdy_out),
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
        .v_star_in(v_star),
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
        .a_in(exp_o_vector),
        .b_in(exp_v_vector),
        .sum(output_vector)
    );

    vector_division vector_division_inst (
        .clk(clk),
        .rst(rst),
        .vld_in(vec_add_valid),
        .rdy_in(O_sram_rdy),
        .vld_out(output_valid),
        .rdy_out(vector_division_ready),
        .vec_in(output_vector[1:`MAX_EMBEDDING_DIM]),
        .divisor_in(output_vector[0]),
        .vec_out(output_vector_scaled)
    );

endmodule