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
    input INT_T m_in,
    input INT_T m_prev_in,
    input STAR_VECTOR_T o_star_prev_in,
    input INT_T s_in,
    input STAR_VECTOR_T v_star_in,
    output STAR_VECTOR_T exp_v_out,
    output STAR_VECTOR_T exp_o_out
);

    //Internal Pipeline Registers
    INT_T m,
    INT_T m_prev;
    STAR_VECTOR_T o_star_prev;
    INT_T s;
    STAR_VECTOR_T v_star;
    logic valid_reg;

    assign vld_out = valid_reg;
    assign rdy_out = rdy_in;

    //Latch inputs first
    always_ff @(posedge clk) begin
        if(rst) begin
            m <= '0;
            m_prev <= '0;
            o_star_prev <= '0;
            s <= '0;
            v_star <= '0;
            valid_reg <= 1'b0;
        end else begin
            if(vld_in && rdy_in) begin //Handshake successful
                m <= m_in;
                m_prev <= m_prev_in;
                o_star_prev <= o_star_prev_in;
                s <= s_in;
                v_star <= v_star_in;
                valid_reg <= 1'b1;
            end else if(rdy_in) begin //Only downstream is ready (clear internal pipeline)
                valid_reg <= 1'b0;
            end
        end
    end


    //Use these blocks if expmul is combinational
    expmul_comb expmul_o_inst (
        .a_in(m_prev),
        .b_in(m),
        .v_in(o_star_prev),
        .v_out(exp_o_out)
    );

    expmul_comb expmul_v_inst (
        .a_in(s),
        .b_in(m),
        .v_in(v_star),
        .v_out(exp_v_out)
    );

    //Use these if expmul is pipelined
    //But remember to not latch inputs in this top module so you dont waste an extra cycle
    //Also add support for internal valid-ready signals
    // expmul_stage expmul_o_inst (
    //     .clk(clk),
    //     .rst(rst),
    //     .vld_in(vld_in),
    //     .rdy_in(rdy_in),
    //     .vld_out(),
    //     .rdy_out(),
    //     .a_in(m_prev),
    //     .b_in(m),
    //     .v_in(o_star_prev),
    //     .v_out(exp_o_out)
    // );

    // expmul_stage expmul_v_inst (
    //     .clk(clk),
    //     .rst(rst),
    //     .vld_in(vld_in),
    //     .rdy_in(rdy_in),
    //     .vld_out(),
    //     .rdy_out(),
    //     .a_in(s),
    //     .b_in(m),
    //     .v_in(v_star),
    //     .v_out(exp_v_out)
    // );


endmodule