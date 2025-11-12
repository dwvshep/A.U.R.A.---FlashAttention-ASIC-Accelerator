//This module performs integer division of two INT_T numbers

module int_division(
    // Control signals
    input clk,
    input rst,

    // Handshake signals
    input vld_in,
    input rdy_in,
    output vld_out,
    output rdy_out,

    // Data signals
    input INT_T numerator_in,
    input INT_T denominator_in,
    output INT_T quotient_out
);

    // Internal Pipeline Registers
    INT_T numerator;
    INT_T denominator;
    logic valid_reg;

    assign vld_out = valid_reg;
    assign rdy_out = rdy_in || !valid_reg;

    // Latch inputs first
    always_ff @(posedge clk) begin
        if (rst) begin
            numerator <= '0;
            denominator <= '0;
            valid_reg <= 1'b0;
        end else begin
            if (vld_in && rdy_out) begin // Handshake successful
                numerator <= numerator_in;
                denominator <= denominator_in;
                valid_reg <= 1'b1;
            end else if (rdy_in) begin // Only downstream is ready (clear internal pipeline)
                valid_reg <= 1'b0;
            end
        end
    end

    // output is combinational
    always_comb begin

        //PLACE HOLDER FOR DIVISION LOGIC
        if (denominator != 0) begin
            quotient_out = numerator / denominator;
        end else begin
            quotient_out = '0; // Handle division by zero case
        end

    end

endmodule