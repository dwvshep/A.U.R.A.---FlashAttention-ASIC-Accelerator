`include "include/sys_defs.svh"

module dot_product_tb;

    // --------------------------------------------------------
    // Parameters
    // --------------------------------------------------------
    
    localparam int DIM = `MAX_EMBEDDING_DIM;
    localparam int ELEM_W = `INTEGER_WIDTH;   // Q0.7
    localparam int SCORE_W = 8;  // your output width
    localparam int NUM_TESTS = 50;

    // --------------------------------------------------------
    // DUT Signals
    // --------------------------------------------------------
    logic clk, rst;

    logic Q_vld_in, K_vld_in, rdy_in;
    logic vld_out;
    logic Q_rdy_out, K_rdy_out;

    // logic signed [ELEM_W-1:0] q_in [DIM];
    // logic signed [ELEM_W-1:0] k_in [DIM];
    // logic signed [SCORE_W-1:0] s_out;
    Q_VECTOR_T q_in;
    K_VECTOR_T k_in;
    SCORE_QT s_out;
    

    // --------------------------------------------------------
    // Instantiate DUT
    // --------------------------------------------------------
    dot_product dut (
        .clk(clk),
        .rst(rst),

        .Q_vld_in(Q_vld_in),
        .K_vld_in(K_vld_in),
        .V_vld_in(1'b1),
        .rdy_in(rdy_in),
        .vld_out(vld_out),
        .Q_rdy_out(Q_rdy_out),
        .K_rdy_out(K_rdy_out),
        .V_rdy_out(),

        .q_in(q_in),
        .k_in(k_in),
        .v_in('0),
        .s_out(s_out),
        .v_out()
    );

    // --------------------------------------------------------
    // Clock
    // --------------------------------------------------------
    always #5 clk = ~clk;   // 100 MHz

    // --------------------------------------------------------
    // Fixed-Point Helper Functions
    // --------------------------------------------------------

    // Convert Q0.7 (signed 8-bit) to real
    function real q07_to_real(logic signed [7:0] x);
        return x / 128.0; // 2^7
    endfunction

    // Convert real to Q0.7 (saturate)
    function logic signed [7:0] real_to_q07(real r);
        real scaled = r * 128.0;
        if (scaled > 127)  scaled = 127;
        if (scaled < -128) scaled = -128;
        return $rtoi(scaled);
    endfunction

    // Convert real to SCORE_QT (signed 8-bit)
    function logic signed [7:0] real_to_score(real r);
        real scaled = r * 128.0; // since your output is also Q0.7
        if (scaled > 127)  scaled = 127;
        if (scaled < -128) scaled = -128;
        return $rtoi(scaled);
    endfunction

    // --------------------------------------------------------
    // Reset
    // --------------------------------------------------------
    initial begin
        clk = 0;
        rst = 1;
        Q_vld_in = 0;
        K_vld_in = 0;
        rdy_in   = 1;

        #20;
        rst = 0;
    end

    // --------------------------------------------------------
    // TEST PROCESS
    // --------------------------------------------------------
    int pass_count = 0;
    logic signed [7:0] golden_q;

    initial begin : TEST_MAIN
        @(negedge rst);
        #10;

        for (int t = 0; t < NUM_TESTS; t++) begin
            automatic real golden = 0.0;

            // -------------------------------
            // Generate random Q0.7 input vectors
            // -------------------------------
            for (int i = 0; i < DIM; i++) begin
                q_in[i] = $urandom_range(-128, 127);
                k_in[i] = $urandom_range(-128, 127);

                golden += q07_to_real(q_in[i]) * q07_to_real(k_in[i]);
            end

            // Apply the >>> 3 division (divide by sqrt(64)=8)
            golden = golden / 8.0;

            golden_q = real_to_score(golden);

            // -------------------------------
            // Drive handshake for inputs
            // -------------------------------
            @(posedge clk);
            Q_vld_in <= 1;
            K_vld_in <= 1;

            // Wait for DUT to accept inputs
            wait (Q_rdy_out && K_rdy_out);

            @(posedge clk);
            Q_vld_in <= 0;
            K_vld_in <= 0;

            // -------------------------------
            // Wait for output
            // -------------------------------
            wait (vld_out == 1);

            // Check result
            if (s_out === golden_q) begin
                $display("[PASS] test %0d: s_out=%0d, golden=%0d",
                         t, s_out, golden_q);
                pass_count++;
            end else begin
                $display("[FAIL] test %0d: s_out=%0d, golden=%0d",
                         t, s_out, golden_q);
            end

            // Add spacing between tests
            @(posedge clk);
        end

        $display("\n======== TEST SUMMARY ========");
        $display("Pass: %0d / %0d", pass_count, NUM_TESTS);
        $display("==============================\n");

        $finish;
    end

    // --------------------------------------------------------
    // Waveform
    // --------------------------------------------------------
    initial begin
        $dumpfile("tb_dot_product.vcd");
        //$dumpvars(0, tb_dot_product);
    end

endmodule