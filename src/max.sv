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
    input INT_T s_in,
    input INT_T m_prev_in,
    output INT_T m_out,
    output INT_T s_out
);

    //Internal Pipeline Registers
    INT_T s;
    INT_T m_prev;
    logic valid_reg;

    assign vld_out = valid_reg;
    assign rdy_out = rdy_in;

    //Latch inputs first
    always_ff @(posedge clk) begin
        if(rst) begin
            s <= '0;
            m_prev <= '0;
            valid_reg <= 1'b0;
        end else begin
            if(vld_in && rdy_in) begin //Handshake successful
                s <= s_in;
                m_prev <= m_prev_in;
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
    end

endmodule