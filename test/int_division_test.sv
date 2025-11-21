`timescale 1ns/1ps

module int_division_tb;

    // --------------------------------------------------------
    // Parameters
    // --------------------------------------------------------
    localparam int INT_W = 17;   // Q9.7
    localparam int FRAC_IN = 7;  // Q9.8 has 8 fractional bits
    localparam int QUOT_W = 8;   // Q0.7
    localparam int FRAC_OUT = 7; // Q0.7 has 7 fractional bits
    localparam int NUM_TESTS = 100;

    // Q0.7 signed range: [-128, 127]
    localparam int QUOT_MAX = (1 << (QUOT_W-1)) - 1; //  127
    localparam int QUOT_MIN = -(1 << (QUOT_W-1));    // -128

    // --------------------------------------------------------
    // DUT Signals
    // --------------------------------------------------------
    logic clk, rst;

    // Handshake signals
    logic vld_in;
    logic rdy_in;
    logic vld_out;
    logic rdy_out;

    logic signed [INT_W-1:0] numerator_in;
    logic signed [INT_W-1:0] denominator_in;
    logic signed [QUOT_W-1:0] quotient_out;

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
    // num_real = num / 2^8
    // den_real = den / 2^8
    // true quotient = num_real / den_real = num / den
    //
    // Q0.7 representation:
    //   q_fixed ≈ (num / den) * 2^7 = (num * 2^7) / den
    // --------------------------------------------------------
    function automatic logic signed [INT_W-1:0] div_q98_to_q07_ref (
        input logic signed [INT_W-1:0] num,     // Q9.8
        input logic signed [INT_W-1:0] den      // Q9.8
    );
        int signed num_ext;
        int signed den_int;
        int signed q_int;

        begin
            // divide by zero safety 
            // (we expect den will never be zero but just in case)
            if (den == 0) begin
                if (num >= 0)
                    q_int = QUOT_MAX;
                else
                    q_int = QUOT_MIN;
            end else begin
                num_ext = num <<< FRAC_OUT; // num_ext = num * 2^FRAC_W
                den_int = den;
                q_int   = num_ext / den_int;  // lol just divide that shit

                // Saturate to INT_W bits
                // (another safety net for overflows)
                if (q_int > QUOT_MAX) q_int = QUOT_MAX;
                if (q_int < QUOT_MIN) q_int = QUOT_MIN;
            end

            return logic'(q_int[QUOT_W-1:0]);
        end
    endfunction

    // --------------------------------------------------------
    // Task to run a single test
    // --------------------------------------------------------
    int pass_count = 0;
    int total_count = 0;

    task automatic run_single_test(
        input logic signed [INT_W-1:0] num,
        input logic signed [INT_W-1:0] den
    );
        logic signed [INT_W-1:0] golden_q;
        begin
            golden_q = div_q98_to_q07_ref(num, den);

            // Drive inputs
            @(posedge clk);
            numerator_in   <= num;
            denominator_in <= den;
            vld_in         <= 1;

            // Wait for DUT to be ready to accept the transaction
            wait (rdy_out == 1);

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
                $display("[PASS] n=%0d d=%0d -> q=%0d (golden=%0d)",
                         num, den, quotient_out, golden_q);
                pass_count++;
            end else begin
                $display("[FAIL] n=%0d d=%0d -> q=%0d (golden=%0d)",
                         num, den, quotient_out, golden_q);
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
        @(negedge rst);
        @(posedge clk);

        // --- Some directed edge cases ---
        run_single_test( 17'sd0,    17'sd256 ); // 0.0 / 1.0 -> 0.0
        run_single_test( 17'sd128,  17'sd256 ); // 0.5 / 1.0 -> 0.5
        run_single_test( 17'sd256,  17'sd512 ); // 1.0 / 2.0 -> 0.5
        run_single_test( 17'sd192,  17'sd384 ); // 0.75 / 1.5 -> 0.5
        run_single_test( 17'sd256,  17'sd1024 ); // 1.0 / 4.0 -> 0.25

        // --- Random tests ---
        for (int t = 0; t < NUM_TESTS; t++) begin
            logic signed [INT_W-1:0] n;
            logic signed [INT_W-1:0] d;

            int NUM_MAX = (1 << FRAC_IN);   // 1 << 8 = 256 => 1.0
            int DEN_MIN = (1 << FRAC_IN);   // 256 => 1.0
            int DEN_MAX = (4 << FRAC_IN);   // 4 << 8 = 1024 => 4.0

            int n_i = $urandom_range(0, NUM_MAX);
            int d_i = $urandom_range(DEN_MIN, DEN_MAX);

            n = logic'(n_i[INT_W-1:0]);
            d = logic'(d_i[INT_W-1:0]);     

            run_single_test(n, d);
        end

        $display("\n======== DIVISION TEST SUMMARY ========");
        $display("Pass: %0d / %0d", pass_count, total_count);
        $display("=======================================\n");

        $finish;
    end

    // --------------------------------------------------------
    // Waveform
    // --------------------------------------------------------
    initial begin
        $dumpfile("tb_int_division.vcd");
        $dumpvars(0, int_division_tb);
    end

endmodule