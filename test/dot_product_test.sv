`include "include/sys_defs.svh"

module dot_product_tb;

    // --------------------------------------------------------
    // Parameters
    // --------------------------------------------------------
    
    localparam int DIM = `MAX_EMBEDDING_DIM;
    localparam int ELEM_W = `INTEGER_WIDTH;   // Q0.7
    localparam int SCORE_W = 8;  // your output width
    localparam int NUM_TESTS = 1;

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
    EXPMUL_DIFF_IN_QT s_out;
    

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
    function logic signed [12:0] real_to_q07(real r);
        real scaled = r * 128.0;
        if (scaled > 127)  scaled = 127;
        if (scaled < -128) scaled = -128;
        return $rtoi(scaled);
    endfunction

    // Convert real to SCORE_QT (signed 13-bit)
    function EXPMUL_DIFF_IN_QT real_to_score(real r);
        //real scaled_r = r * 32.0;
        //real rounded_r = r * 32.0 + (r * 32.0 >= 0 ? 0.5 : -0.5);
        // if (r * 2**`SCORE_F + ((r * 2**`SCORE_F) >= 0 ? 0.5 : -0.5) > 127)  return 127;
        // if (r * 2**`SCORE_F + ((r * 2**`SCORE_F) >= 0 ? 0.5 : -0.5) < -128) return -128;
        // return $rtoi(r * 2**`SCORE_F + (r * 2**`SCORE_F >= 0 ? 0.5 : -0.5)); 
        //half-away-from-zero bias
        if (r * 2**`EXPMUL_DIFF_IN_F >= 0) begin
            if($rtoi(r * 2**`EXPMUL_DIFF_IN_F + 0.5) > 127) return 127;
            if($rtoi(r * 2**`EXPMUL_DIFF_IN_F + 0.5) < -128) return -128;
            return $rtoi(r * 2**`EXPMUL_DIFF_IN_F + 0.5);
        end
        else begin
            if($rtoi(r * 2**`EXPMUL_DIFF_IN_F - 0.4999) > 127) return 127;
            if($rtoi(r * 2**`EXPMUL_DIFF_IN_F - 0.4999) < -128) return -128;
            return $rtoi(r * 2**`EXPMUL_DIFF_IN_F - 0.4999);
        end
        // if($rtoi(r * 2**`SCORE_F) > 127) return 127;
        // if($rtoi(r * 2**`SCORE_F) < -128) return -128;
        // return $rtoi(r * 2**`SCORE_F);
    endfunction


    int pass_count = 0;
    DOT_QT golden_q;
    EXPMUL_DIFF_IN_QT expected_queue[$];  // FIFO
    EXPMUL_DIFF_IN_QT expected;
    real golden_row[DIM];      // store golden results for 512 K’s
    real golden_val;
    // --------------------------------------------------------
    // Reset --> TEST
    // --------------------------------------------------------
    initial begin : TEST_MAIN
        $display("QTYPES:");
        $display("SCORE_QT: Q(%0d,%0d)", `SCORE_I, `SCORE_F);
        $display("PRODUCT_QT: Q(%0d,%0d)", `PRODUCT_I, `PRODUCT_F);
        $display("INTERMEDIATE_PRODUCT_QT: Q(%0d,%0d)", `INTERMEDIATE_PRODUCT_I, `INTERMEDIATE_PRODUCT_F);
        $display("DOT_QT: Q(%0d,%0d)", `DOT_I, `DOT_F);
        clk = 0;
        rst = 1;
        Q_vld_in = 0;
        K_vld_in = 0;
        rdy_in   = 1;

        @(posedge clk);
        @(posedge clk)
        rst = 0;

        for (int t = 0; t < NUM_TESTS; t++) begin
            //-----------------------------
            // 1. Generate one Q vector
            //-----------------------------
            for (int i = 0; i < DIM; i++)
                q_in[i] = $urandom_range(-128, 127);

            Q_vld_in = 1;
            wait (Q_rdy_out);
            @(posedge clk);
            Q_vld_in = 0;

            //-----------------------------
            // 3. Stream K vectors
            //-----------------------------
            for (int k = 0; k < `MAX_EMBEDDING_DIM; k++) begin
                // generate a NEW K vector each cycle
                golden_val = 0.0;
                for (int i = 0; i < DIM; i++) begin
                    k_in[i] = $urandom_range(-128, 127);
                    golden_val += q07_to_real(q_in[i]) * q07_to_real(k_in[i]);
                    //golden_val += (q_in[i]) * (k_in[i]);
                end
                //golden_val = real_to_score(golden_val);
                $display("golden_val: %0f (%13b)", golden_val, golden_val);
                golden_val /= 8.0;  // >>3 scaling;
                $display("golden_val/8: %0f (%13b)", golden_val, golden_val);
                golden_q = real_to_score(golden_val);
                $display("golden_q: %0d (%13b)", golden_q, golden_q);
                expected_queue.push_back(golden_q);
                
                // handshake for K
                K_vld_in = 1;
                wait (K_rdy_out);
                @(posedge clk);
                K_vld_in = 0;

                // Check for result
                if (vld_out) begin
                    expected = expected_queue.pop_front();

                    if (s_out !== expected) begin
                        $display("[FAIL] got=%0d (%0b) expected=%0d (%0b)", s_out, s_out, expected, expected);
                    end else begin
                        $display("[PASS] out=%0d (%0b) expected=%0d (%0b)", s_out, s_out, expected, expected);
                    end
                end
            end

            //-----------------------------
            // 4. Wait for Q to clear
            //-----------------------------
            //wait (Q_rdy_out);
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