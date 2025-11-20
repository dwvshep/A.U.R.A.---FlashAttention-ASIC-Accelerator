`include "include/sys_defs.svh"

module q_align_frac #(
    parameter int IN_I, 
    parameter int IN_F,
    parameter int OUT_F,
    localparam int W_IN  = `Q_WIDTH(IN_I, IN_F),
    localparam int W_OUT = `Q_WIDTH(IN_I, OUT_F)
)(
    input logic signed [W_IN-1:0] in,
    output logic signed [W_OUT-1:0] out
);
    
    logic signed [W_OUT-1:0] temp;

    generate 
        // Same number of fractional bits → sign extend only
        if (OUT_F == IN_F) begin
            assign temp = in;

        // Need MORE fractional bits → LEFT SHIFT AND PAD
        end else if (OUT_F > IN_F) begin
            assign temp = {in, {(OUT_F-IN_F){1'b0}}};

        // Need FEWER fractional bits → RIGHT SHIFT
        //This is where rounding occurs if enabled
        end else begin // OUT_F < IN_F
            if(`ROUNDING) begin
                //Perform rounding by adding a bias term with values extended by 1 bit to 
                //prevent overflow/wrap around, and then saturate
                logic signed [W_IN:0] in_ext;
                assign in_ext = {in[W_IN-1], in};

                logic signed [W_IN:0] abs_bias;
                assign abs_bias = (W_IN+1)'(1) << ((IN_F-OUT_F)-1);

                logic signed [W_IN:0] bias;
                assign bias = (in_ext[W_IN] == 0) ? abs_bias : -abs_bias; // Use sign bit to choose bias sign

                logic signed [W_IN:0] sum_wide;
                assign sum_wide = in_ext + bias;

                logic signed [W_IN:0] shifted_wide;
                assign shifted_wide = (sum_wide >>> (IN_F-OUT_F));

                q_saturate #(
                    .W_OUT(W_OUT),
                    .W_IN(W_IN+1)
                ) round_sat (
                    .in(shifted_wide),
                    .out(temp)
                );
            end else begin
                assign temp = (in >>> (IN_F-OUT_F));
            end
        end
    endgenerate

    assign out = temp;

endmodule