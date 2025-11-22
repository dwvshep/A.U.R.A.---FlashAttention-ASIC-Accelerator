`include "include/sys_defs.svh"

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
    input EXPMUL_DIFF_IN_QT m_in,
    input EXPMUL_DIFF_IN_QT m_prev_in,
    input STAR_VECTOR_T o_star_prev_in,
    input EXPMUL_DIFF_IN_QT s_in,
    input STAR_VECTOR_T v_star_in,
    output STAR_VECTOR_T exp_v_out,
    output STAR_VECTOR_T exp_o_out
);

    //Internal Pipeline Registers
    EXPMUL_DIFF_IN_QT m;
    EXPMUL_DIFF_IN_QT m_prev;
    EXPMUL_DIFF_IN_QT s;
    STAR_VECTOR_T o_star_prev;
    STAR_VECTOR_T v_star;
    logic expmul_o_valid, expmul_o_rdy, expmul_v_valid, expmul_v_rdy;

    assign vld_out = expmul_o_valid && expmul_v_valid;
    assign rdy_out = (expmul_o_rdy && expmul_v_rdy) || !(expmul_o_valid && expmul_v_valid);

    //Latch inputs first
    // always_ff @(posedge clk) begin
    //     if(rst) begin
    //         m <= '0;
    //         m_prev <= '0;
    //         o_star_prev <= '0;
    //         s <= '0;
    //         v_star <= '0;
    //         valid_reg <= 1'b0;
    //     end else begin
    //         if(vld_in && rdy_out) begin //Handshake successful
    //             m <= m_in;
    //             m_prev <= m_prev_in;
    //             o_star_prev <= o_star_prev_in;
    //             s <= s_in;
    //             v_star <= v_star_in;
    //             valid_reg <= 1'b1;
    //         end else if(rdy_in) begin //Only downstream is ready (clear internal pipeline)
    //             valid_reg <= 1'b0;
    //         end
    //     end
    // end


    //Use these blocks if expmul is combinational
    // expmul_comb expmul_o_inst (
    //     .a_in(m_prev),
    //     .b_in(m),
    //     .v_in(o_star_prev),
    //     .v_out(exp_o_out)
    // );

    // expmul_comb expmul_v_inst (
    //     .a_in(s),
    //     .b_in(m),
    //     .v_in(v_star),
    //     .v_out(exp_v_out)
    // );

    //Use these if expmul is pipelined
    //But remember to not latch inputs in this top module so you dont waste an extra cycle
    //Also add support for internal valid-ready signals
    expmul_stage expmul_o_inst (
        .clk(clk),
        .rst(rst),
        .vld_in(vld_in),
        .rdy_in(rdy_in),
        .vld_out(expmul_o_valid),
        .rdy_out(expmul_o_rdy),
        .a_in(m_prev_in),
        .b_in(m_in),
        .v_in(o_star_prev_in),
        .v_out(exp_o_out)
    );

    expmul_stage expmul_v_inst (
        .clk(clk),
        .rst(rst),
        .vld_in(vld_in),
        .rdy_in(rdy_in),
        .vld_out(expmul_v_valid),
        .rdy_out(expmul_v_rdy),
        .a_in(s_in),
        .b_in(m_in),
        .v_in(v_star_in),
        .v_out(exp_v_out)
    );


endmodule