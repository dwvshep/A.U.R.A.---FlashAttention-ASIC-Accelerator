//This module computes the product of two inputs

module multiply #(
    parameter int W_IN     = 8,              // width of each input operand
    parameter int W_OUT    = 2*W_IN           // width of product
)(
    //control signals
    input clk,
    input rst,

    //Handshake signals
    input vld_in,
    input rdy_in,
    output vld_out,
    output rdy_out,

    //Data signals
    input  logic signed  [W_IN-1:0] a_in,
    input  logic signed  [W_IN-1:0] b_in,
    output logic signed [W_OUT-1:0] product
);

    //Internal Pipeline Registers
    logic signed [W_IN-1:0] a, b;
    logic valid_reg;

    assign vld_out = valid_reg;
    assign rdy_out = rdy_in || !valid_reg;

    //Latch inputs first
    always_ff @(posedge clk) begin
        if(rst) begin
            a <= '0;
            b <= '0
            valid_reg <= 1'b0;
        end else begin
            if(vld_in && rdy_out) begin //Handshake successful
                a <= a_in;
                b <= b_in;
                valid_reg <= 1'b1;
            end else if(rdy_in) begin //Only downstream is ready (clear internal pipeline)
                valid_reg <= 1'b0;
            end
        end
    end

    //outputs are combinational
    assign product = a * b;

endmodule