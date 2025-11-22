`timescale 1ns/1ps
`include "sys_defs.svh"

module int_division_tb;

    // --------------------------------------------------------
    // Parameters
    // --------------------------------------------------------
    localparam int DIV_INPUT_W = $bits(DIV_INPUT_QT);   // Total width of DIV_INPUT_QT
    localparam int QUOT_W = $bits(OUTPUT_VEC_QT);   // Q0.7 output should have width 8
    localparam int NUM_TESTS = 250;

    // Q0.7 signed range: [-128, 127]
    localparam int QUOT_MAX = (1 << (QUOT_W-1)) - 1; //  127
    localparam int QUOT_MIN = -(1 << (QUOT_W-1));    // -128

    //localparam int NUM_MAX = ((1 << (`DIV_INPUT_F + `DIV_INPUT_I)) - 1);   // up to 1.0
    localparam int NUM_MAX = (1 << `DIV_INPUT_F);
    localparam int DEN_MIN = (1 << `DIV_INPUT_F);   // >= 1.0
    localparam int DEN_MAX = ((1 << (`DIV_INPUT_F + `DIV_INPUT_I)) - 1);   // up to (2^8)

    // Convenience constants for Q9.7 / parameterizable 
    localparam real ONE_QIN   = 1;    // 1.0 in Q9.7
    localparam real HALF_QIN  = ONE_QIN / 2;    // 0.5
    localparam real QUART_QIN = ONE_QIN / 4;    // 0.25, etc.

    // --------------------------------------------------------
    // DUT Signals
    // --------------------------------------------------------
    logic clk, rst;

    // Handshake signals
    logic vld_in;
    logic rdy_in;
    logic vld_out;
    logic rdy_out;

    DIV_INPUT_QT numerator_in;
    DIV_INPUT_QT denominator_in;
    OUTPUT_VEC_QT quotient_out;

    // --------------------------------------------------------
    // Instantiate DUT
    // --------------------------------------------------------
    int_division dut (
        .clk(clk),
        .rst(rst),

        .vld_in(vld_in),
        .rdy_in(rdy_in),
        .vld_out(vld_out),
        .rdy_out(rdy_out),

        .numerator_in(numerator_in),
        .denominator_in(denominator_in),
        .quotient_out(quotient_out)
    );

    // --------------------------------------------------------
    // Clock
    // --------------------------------------------------------
    always #5 clk = ~clk;   // 100 MHz

    // --------------------------------------------------------
    // Helper Functions
    // --------------------------------------------------------
    
    // Convert DIV_INPUT_QT to real
    function automatic real div_input_to_real(DIV_INPUT_QT x);
        // Q(`DIV_INPUT_I, `DIV_INPUT_F) to real
        return real'(x) / real'(1 << `DIV_INPUT_F); // 2^DIV_INPUT_F
    endfunction

    // Convert real to DIV_INPUT_QT (round + saturate)
    function automatic OUTPUT_VEC_QT real_to_output_vec(real r);
        real scaled = r * real'(1 << `OUTPUT_VEC_F); // r * 2^OUTPUT_VEC_F
        real rounded;
        int q_int;

        //deal with rounding cases
        if(`ROUNDING) begin
            rounded = (scaled >= 0.0) ? (scaled + 0.5) : (scaled - 0.5);
        end else begin
            rounded = scaled;
        end

        //cast to int
        q_int = $rtoi(rounded);
        
        //saturate
        if (q_int > QUOT_MAX)  q_int = QUOT_MAX;
        if (q_int < QUOT_MIN)  q_int = QUOT_MIN;
        
        return OUTPUT_VEC_QT'(q_int);
    endfunction

    // Convert output_vec to real (to print values if needed)
    function automatic real output_vec_to_real(OUTPUT_VEC_QT x);
        return real'(x) / real'(1 << `OUTPUT_VEC_F);
    endfunction

    // Convert real to DIV_INPUT_QT (refer to real to score)
    function automatic DIV_INPUT_QT real_to_div_input(real r);
        if (r * 2**`DIV_INPUT_F >= 0) begin
            if($rtoi(r * 2**`DIV_INPUT_F + 0.5) > 511) return 511;
            if($rtoi(r * 2**`DIV_INPUT_F + 0.5) < -512) return -512;
            return $rtoi(r * 2**`DIV_INPUT_F + 0.5);
        end
        else begin
            if($rtoi(r * 2**`DIV_INPUT_F - 0.4999) > 511) return 511;
            if($rtoi(r * 2**`DIV_INPUT_F - 0.4999) < -512) return -512;
            return $rtoi(r * 2**`DIV_INPUT_F - 0.4999);
        end
    endfunction

    // --------------------------------------------------------
    // Reset    
    // --------------------------------------------------------

    initial begin
        clk = 0;
        rst = 1;
        vld_in = 0;
        rdy_in = 1;
        numerator_in = '0;
        denominator_in = '0;

        #20;
        rst = 0; 
    end

    // --------------------------------------------------------
    // Reference Model (Q9.8 division)
    // --------------------------------------------------------
    // DIV_INPUT_QT is Q(`DIV_INPUT_I, `DIV_INPUT_F)
    // num_real = num / 2^`DIV_INPUT_F
    // den_real = den / 2^`DIV_INPUT_F
    // true quotient = num_real / den_real = num / den
    //
    // OUTPUT_VEC_QT is Q(`OUTPUT_VEC_I, `OUTPUT_VEC_F)
    // q_fixed ≈ (num / den) * 2^`OUTPUT_VEC_F = (num * 2^`OUTPUT_VEC_F) / den
    // --------------------------------------------------------
    function automatic OUTPUT_VEC_QT div_ref (
        input DIV_INPUT_QT num,     // Q9.8 presumably
        input DIV_INPUT_QT den      // Q9.8
    );
        real num_real;
        real den_real;
        real quot_real;
        int quot_int;

        //divide by zero case, saturate towards +/- max
        if (den == 0) begin
            return (num >= 0) ? OUTPUT_VEC_QT'(QUOT_MAX) 
                              : OUTPUT_VEC_QT'(QUOT_MIN);
        end

        //turn that shit into a real num
        num_real = div_input_to_real(num);
        den_real = div_input_to_real(den);

        //true real quotient 
        quot_real = num_real / den_real;

        //real quotient converted back into output vec format
        return real_to_output_vec(quot_real);
    endfunction

    // --------------------------------------------------------
    // Task to run a single test
    // --------------------------------------------------------
    int pass_count = 0;
    int total_count = 0;

    task automatic run_single_test(
        input DIV_INPUT_QT num,
        input DIV_INPUT_QT den
    );
        OUTPUT_VEC_QT golden_q;
        real num_r, den_r, q_r, g_r;
        begin
            golden_q = div_ref(num, den);

            num_r = div_input_to_real(num);
            den_r = div_input_to_real(den);
            q_r   = output_vec_to_real(quotient_out);
            g_r   = output_vec_to_real(golden_q);

            // Drive inputs
            @(posedge clk);
            wait (rdy_out == 1); // Wait until DUT is ready

            numerator_in   <= num;
            denominator_in <= den;
            vld_in         <= 1; 

            @(posedge clk);
            vld_in         <= 0;
            numerator_in   <= 'x;
            denominator_in <= 'x;

            // Wait for valid output
            wait (vld_out == 1);

            // Sample result on the valid cycle
            @(posedge clk);
            total_count++;

            if (quotient_out === golden_q) begin
                $display("[PASS] n=%0d (%.7f) d=%0d (%.7f) -> q=%0d (%0b, %.7f)  golden=%0d (%0b, %.7f)",
                        num, num_r,
                        den, den_r,
                        quotient_out, quotient_out, q_r,
                        golden_q,     golden_q,     g_r);
                pass_count++;
            end else begin
                $display("[FAIL] n=%0d (%.7f) d=%0d (%.7f) -> q=%0d (%0b, %.7f)  golden=%0d (%0b, %.7f)",
                        num, num_r,
                        den, den_r,
                        quotient_out, quotient_out, q_r,
                        golden_q,     golden_q,     g_r);
            end

            // one idle cycle between tests
            @(posedge clk);
        end
    endtask

    // --------------------------------------------------------
    // TEST PROCESS
    // --------------------------------------------------------
    initial begin : TEST_MAIN
        // Wait for reset deassert
        $display("QTYPES:");
        $display("DIV_INPUT_QT: Q(%0d,%0d)", `DIV_INPUT_I, `DIV_INPUT_F);
        $display("OUTPUT_VEC_QT: Q(%0d,%0d)", `OUTPUT_VEC_I, `OUTPUT_VEC_F);

        @(negedge rst);
        @(posedge clk);

        // --- Some directed edge cases ---
        run_single_test(real_to_div_input(0),       real_to_div_input(ONE_QIN)); // 0.0 / 1.0 -> 0.0
        run_single_test(real_to_div_input(HALF_QIN),    real_to_div_input(ONE_QIN)); // 0.5 / 1.0 -> 0.5
        run_single_test(real_to_div_input(ONE_QIN),     real_to_div_input(2*ONE_QIN)); // 1.0 / 2.0 -> 0.5
        run_single_test(real_to_div_input((3*ONE_QIN)/4), real_to_div_input((3*ONE_QIN)/2)); // 0.75 / 1.5 -> 0.5
        run_single_test(real_to_div_input(ONE_QIN),     real_to_div_input(4*ONE_QIN)); // 1.0 / 4.0 -> 0.25
        //
        // --- Random tests ---
        //for (int t = 0; t < NUM_TESTS; t++) begin
        //    DIV_INPUT_QT n;
        //    DIV_INPUT_QT d;
        //    int ni;
        //    int di;
//
        //    n = $urandom_range(-(2**17), (2**17)-1);
        //    d = $urandom_range(DEN_MIN, DEN_MAX);
        //    ni = int'(n);
        //    di = int'(d);
//
        //    // Debug print to verify randomness:
        //    $display("RANDOM TEST %0d: raw n_i=%0d d_i=%0d  n=%0d d=%0d",
        //            t, n, d, n, d);   
//
        //    run_single_test(n, d);
        //    //if ($abs(ni) < $abs(di)) begin
        //    //    run_single_test(n, d);
        //    //end else begin
        //    //    //skip this combo? to avoid large quotients
        //    //    t = t - 1;
        //    //end
        //end

        $display("\n======== DIVISION TEST SUMMARY ========");
        $display("Pass: %0d / %0d", pass_count, total_count);
        $display("=======================================\n");
//
        $finish;
    end

    // --------------------------------------------------------
    // Waveform
    // --------------------------------------------------------
    initial begin
        $dumpfile("tb_int_division.vcd");
        //$dumpvars(0, int_division_tb);
    end

endmodule