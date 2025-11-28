`include "include/sys_defs.svh"

module expmul(
    //control signals
    input clock,
    input reset,

    //Handshake signals
    input vld_in,
    input rdy_in,
    output vld_out,
    output rdy_out,

    //Data signals
    input EXPMUL_DIFF_IN_QT m_in,
    input EXPMUL_DIFF_IN_QT m_prev_in,
    input STAR_VECTOR_T o_star_prev_in,
    input EXPMUL_DIFF_IN_QT s_in,
    input STAR_VECTOR_T v_star_in,
    output STAR_VECTOR_T exp_v_out,
    output STAR_VECTOR_T exp_o_out
);

    //Internal Pipeline Registers
    // STAR_VECTOR_T exp_v_out;
    EXPMUL_DIFF_IN_QT m;
    EXPMUL_DIFF_IN_QT m_prev;
    EXPMUL_DIFF_IN_QT s;
    STAR_VECTOR_T o_star_prev;
    STAR_VECTOR_T v_star;
    logic expmul_o_valid, expmul_o_rdy, expmul_v_valid, expmul_v_rdy;
    logic [$clog2(`MAX_SEQ_LENGTH)-1:0] kv_counter_1, kv_counter_2;
    STAR_VECTOR_T exp_o_out_partial, exp_o_out_partial_reg, exp_o_input;

    assign vld_out = expmul_o_valid && expmul_v_valid && (kv_counter_1 == 0);
    assign rdy_out = (expmul_o_rdy && expmul_v_rdy) || (!expmul_o_valid && !expmul_v_valid);

    generate
        for (genvar i = 0; i < `MAX_EMBEDDING_DIM + 1; i++) begin
            assign exp_o_out[i] = exp_o_out_partial[i] + exp_v_out[i];
        end
    endgenerate
    

    assign exp_o_input = (kv_counter_1 == 0) ? o_star_prev_in : exp_o_out;
                //o_star_prev_in : exp_o_out_partial + exp_v_out;
                // kv_counter <= (kv_counter == 0) ? `MAX_SEQ_LENGTH-1 : kv_counter - 1;

 
    expmul_stage expmul_o_inst (
        .clock(clock),
        .reset(reset),
        .vld_in(vld_in),
        .rdy_in(rdy_in),
        .vld_out(expmul_o_valid),
        .rdy_out(expmul_o_rdy),
        .a_in(m_prev_in),
        .b_in(m_in),
        .v_in(exp_o_input),
        .v_out(exp_o_out_partial),
        .o_star_mode(1'b1),
        .kv_counter(kv_counter_1)
    );

    expmul_stage expmul_v_inst (
        .clock(clock),
        .reset(reset),
        .vld_in(vld_in),
        .rdy_in(rdy_in),
        .vld_out(expmul_v_valid),
        .rdy_out(expmul_v_rdy),
        .a_in(s_in),
        .b_in(m_in),
        .v_in(v_star_in),
        .v_out(exp_v_out),
        .o_star_mode(1'b0),
        .kv_counter(kv_counter_2)
    );


endmodule