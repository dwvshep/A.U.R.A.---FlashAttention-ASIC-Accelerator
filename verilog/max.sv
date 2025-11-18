//This module computes the maximum between the current score and the previous maximum score

module max(
    //control signals
    input clk,
    input rst,

    //Handshake signals
    input vld_in,
    input rdy_in,
    output vld_out,
    output rdy_out,

    //Data signals
    input SCORE_QT s_in,
    input SCORE_QT m_prev_in,
    input V_VECTOR_T v_in,
    output SCORE_QT m_out,
    output SCORE_QT s_out,
    output SCORE_QT m_prev_out,
    output V_VECTOR_T v_out
);

    //Internal Pipeline Registers
    SCORE_QT s;
    SCORE_QT m_prev;
    V_VECTOR_T v;
    logic valid_reg;

    assign vld_out = valid_reg;
    assign rdy_out = rdy_in || !valid_reg;

    //Latch inputs first
    always_ff @(posedge clk) begin
        if(rst) begin
            s <= '0;
            m_prev <= '0;
            v <= '0;
            valid_reg <= 1'b0;
        end else begin
            if(vld_in && rdy_out) begin //Handshake successful
                s <= s_in;
                m_prev <= m_prev_in;
                v <= v_in;
                valid_reg <= 1'b1;
            end else if(rdy_in) begin //Only downstream is ready (clear internal pipeline)
                valid_reg <= 1'b0;
            end
        end
    end

    //outputs are combinational
    always_comb begin
        m_out = (s > m_prev) ? s : m_prev;
        s_out = s;
        m_prev_out = m_prev;
        v_out = v;
    end

endmodule