`timescale 1ns/1ps
`include "include/sys_defs.svh"

module q_convert_tb;

    // ------------------------------------------------------------
    // Parameters to test
    // Change these to exercise other configurations
    // ------------------------------------------------------------
    localparam int IN_I  = 7;
    localparam int IN_F  = 5;
    localparam int OUT_I = 4;
    localparam int OUT_F = 4;

    localparam int W_IN  = `Q_WIDTH(IN_I, IN_F);
    localparam int W_OUT = `Q_WIDTH(OUT_I, OUT_F);

    // DUT signals
    logic signed [W_IN-1:0]  in;
    logic signed [W_OUT-1:0] out;

    // Instantiate DUT
    q_convert #(
        .IN_I(IN_I), .IN_F(IN_F),
        .OUT_I(OUT_I), .OUT_F(OUT_F)
    ) dut (
        .in(in),
        .out(out)
    );

    // ------------------------------------------------------------
    // Helper: Convert Q format to real
    // ------------------------------------------------------------
    function real q_to_real(input logic signed [W_IN-1:0] val);
        return val / real'(1 << IN_F);
    endfunction

    function real q_out_to_real(input logic signed [W_OUT-1:0] val);
        return val / real'(1 << OUT_F);
    endfunction

    // ------------------------------------------------------------
    // Helper: Convert real → quantized integer (saturating)
    // ------------------------------------------------------------
    function automatic logic signed [W_OUT-1:0]
    real_to_q_out(real r);
        real scaled = r * real'(1 << OUT_F);
        real maxr   = (real'((1 << (OUT_I + OUT_F - 1)) - 1)) / (1 << OUT_F);
        real minr   = (real'(-(1 << (OUT_I + OUT_F - 1)))) / (1 << OUT_F);

        if (scaled >  (1 << (OUT_I + OUT_F - 1)) - 1)
            scaled =  (1 << (OUT_I + OUT_F - 1)) - 1;
        else if (scaled < -(1 << (OUT_I + OUT_F - 1)))
            scaled = -(1 << (OUT_I + OUT_F - 1));

        return $rtoi(scaled);
    endfunction

    // ------------------------------------------------------------
    // Test procedure
    // ------------------------------------------------------------
    int num_tests = 200;
    int pass = 0;

    // Directed corner cases first
    logic signed [W_IN-1:0] cases[$] = '{
        '0,
        (1 << (W_IN-1)) - 1,    // max positive
        -(1 << (W_IN-1)),       // max negative
        (1 << (IN_F-1)),        // +0.5
        -((1 << (IN_F-1))),     // -0.5
        (1 << IN_F),            // +1.0
        -((1 << IN_F))          // -1.0
    };

    initial begin
        $display("===============================================");
        $display(" Testing q_convert (Q%0d.%0d → Q%0d.%0d)",
                 IN_I, IN_F, OUT_I, OUT_F);
        $display("===============================================");

        foreach (cases[i]) begin
            run_test(cases[i]);
        end

        // Random tests
        repeat (num_tests) begin
            logic signed [W_IN-1:0] rand_in = $urandom_range(-(1<<(W_IN-1)), (1<<(W_IN-1))-1);
            run_test(rand_in);
        end

        $display("===============================================");
        $display(" Final: PASS=%0d  FAIL=%0d", pass, (num_tests + cases.size()) - pass);
        $display("===============================================");
        $finish;
    end

    // ------------------------------------------------------------
    // Single test executor
    // ------------------------------------------------------------
    task run_test(input logic signed [W_IN-1:0] xin);
        real rin       = q_to_real(xin);        // true input
        real golden_r  = rin;                   // q_convert only formats value
        logic signed [W_OUT-1:0] golden_q;

        in = xin;
        #1; // allow combinational settle

        // Convert golden real into quantized Q_OUT format
        golden_q = real_to_q_out(golden_r);

        if (out === golden_q) begin
            pass++;
            $display("[PASS] in=%13b (%f)  out=%9b (%f)  golden=%0b (%f)",
                     xin, rin, out, q_out_to_real(out),
                     golden_q, q_out_to_real(golden_q));
        end else begin
            $display("[FAIL] in=%13b (%f)  out=%9b (%f)  expected=%0b (%f)",
                     xin, rin, out, q_out_to_real(out),
                     golden_q, q_out_to_real(golden_q));
        end
    endtask

    // Waveform dump
    initial begin
        $dumpfile("q_convert_tb.vcd");
        $dumpvars(0, q_convert_tb);
    end

endmodule