//This module implements a generic handshake register with valid-ready handshake

module handshake_reg(
    //control signals
    input  clk,
    input  rst,

    //Handshake signals
    input  vld_in,
    input  rdy_in,
    output vld_out,
    output rdy_out,

    //Data signals
    input  DATA_T data_in,
    output DATA_T data_out
);

    //Internal Pipeline Registers
    DATA_T data_reg;
    logic valid_reg;

    assign vld_out = valid_reg;
    assign rdy_out = rdy_in;
    assign data_out = data_reg;

    //Latch inputs first
    always_ff @(posedge clk) begin
        if(rst) begin
            data_reg <= '0;
            valid_reg <= 1'b0;
        end else begin
            if(vld_in && rdy_in) begin //Handshake successful
                data_reg <= data_in;
                valid_reg <= 1'b1;
            end else if(rdy_in) begin //Only downstream is ready (clear internal pipeline)
                valid_reg <= 1'b0;
            end
        end
    end

endmodule