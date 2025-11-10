//This module performs integer division of two INT_T numbers in a combinational manner

module int_div_comb(
    // Data signals
    input INT_T numerator_in,
    input INT_T denominator_in,
    output INT_T quotient_out
);

    // output is combinational
    always_comb begin

        //PLACE HOLDER FOR DIVISION LOGIC
        if (denominator_in != 0) begin
            quotient_out = numerator_in / denominator_in;
        end else begin
            quotient_out = '0; // Handle division by zero case
        end

    end

endmodule