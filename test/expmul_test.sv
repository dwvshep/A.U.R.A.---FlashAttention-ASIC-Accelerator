`timescale 1ns/1ps
`include "include/sys_defs.svh"

module tb_expmul;

    // -------------------------------------------------------------
    // DUT type imports from sys_defs.svh
    // -------------------------------------------------------------
    localparam DIM = `MAX_EMBEDDING_DIM + 1;

    // -------------------------------------------------------------
    // Testbench signals
    // -------------------------------------------------------------
    logic clk;
    logic rst;

    logic vld_in;
    logic rdy_in;
    logic vld_out;
    logic rdy_out;

    EXPMUL_DIFF_IN_QT                    m_in;
    EXPMUL_DIFF_IN_QT                    m_prev_in;
    EXPMUL_DIFF_IN_QT                    s_in;

    STAR_VECTOR_T     o_star_prev_in;
    STAR_VECTOR_T     v_star_in;     
    STAR_VECTOR_T     exp_v_out;
    STAR_VECTOR_T     exp_o_out; 

    // -------------------------------------------------------------
    // Clock generation (100 MHz)
    // -------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // -------------------------------------------------------------
    // Reset sequence
    // -------------------------------------------------------------
    initial begin
        rst = 1;
        vld_in = 0;
        rdy_in = 1;   // downstream initially ready
        #(20);
        rst = 0;
    end

    // -------------------------------------------------------------
    // Instantiate DUT
    // -------------------------------------------------------------
    expmul dut (
        .clk(clk),
        .rst(rst),

        .vld_in(vld_in),
        .rdy_in(rdy_in),
        .vld_out(vld_out),
        .rdy_out(rdy_out),

        .m_in(m_in),
        .m_prev_in(m_prev_in),
        .o_star_prev_in(o_star_prev_in),
        .s_in(s_in),
        .v_star_in(v_star_in),

        .exp_v_out(exp_v_out),
        .exp_o_out(exp_o_out)
    );

    // -------------------------------------------------------------
    // Utility: Random vector generator
    // -------------------------------------------------------------
    task automatic rand_vector(
        output STAR_VECTOR_T vec
    );
        foreach (vec[i])
            vec[i] = $urandom_range(0, 50);
            vec[1] = 131072;
    endtask

    function real q07_to_real(logic signed [7:0] x);
        return x / 128.0; // 2^7
    endfunction

    function real q62_to_real(logic signed [9:0] x);
        return x / 4.0;
    endfunction

    function automatic real q917_to_real(logic signed [26:0] x);
        return x / real'(1 << 17);
    endfunction

    function real q44_to_real(logic signed [9:0] x);
        return x / 16.0;
    endfunction

    // Convert a real number to fixed-point representation
    function automatic logic signed [26:0] real_to_fixed
    (
        input real r,                  // input real number
        input int FRACTIONAL_BITS     // number of fractional bits
    );
        int scaled;
        begin
        // Scale by 2^FRACTIONAL_BITS
        scaled = $rtoi(r * (1 << FRACTIONAL_BITS));

        // Clip to WIDTH bits (saturation logic optional)
        if (scaled >  (1 << (9-1)) - 1)
            real_to_fixed = (1 << (9-1)) - 1;   // max positive
        else if (scaled < -(1 << (9-1)))
            real_to_fixed = -(1 << (9-1));      // max negative
        else
            real_to_fixed = scaled[9-1:0];      // fit into WIDTH bits
        end
    endfunction

    function automatic int round_half_toward_zero(real val);
    real a     = $abs(val);
    real frac  = a - $floor(a);
    int  nearest;

    // Standard nearest (ties away from zero): +0.5 -> up, -0.5 -> down
    nearest = (val >= 0.0)
                ? int'($floor(val + 0.5))
                : -int'($floor(-val + 0.5));

    // Override the exact half case for negatives to go toward zero
    if ((frac == 0.5) && (val < 0.0))
        return int'($ceil(val));
    else
        return nearest;
    endfunction

    function automatic int pow2(input int n);
        return (1 << n);
    endfunction

    function automatic int limit_output (input int n);
        if (n < -16) begin
            return -16;
        end else begin
            return n;
        end
    endfunction
    // -------------------------------------------------------------
    // Transaction sender (handles ready/valid correctly)
    // -------------------------------------------------------------
    task automatic send_tx(
    input EXPMUL_DIFF_IN_QT m,
    input EXPMUL_DIFF_IN_QT m_prev,
    input EXPMUL_DIFF_IN_QT s,
    input STAR_VECTOR_T o_prev,
    input STAR_VECTOR_T v_prev
    );
        begin
            // Wait until DUT ready to accept input
            @(posedge clk);
            while (!rdy_out) @(posedge clk);

            m_in       <= m;
            m_prev_in  <= m_prev;
            s_in       <= s;

            // copy arrays
            for (int i = 0; i < DIM; i++) begin
                o_star_prev_in[i] = o_prev[i];
                v_star_in[i]      = v_prev[i];
            end

            vld_in <= 1;

            @(posedge clk);

            // Wait until handshake completes
            //while (!(vld_in && rdy_out)) @(posedge clk);

            vld_in <= 0;

            // $display("[%0t] SENT TX: m=%0d, m_prev=%0d, s=%0d",
            //          $time, m, m_prev, s);
        end
    endtask

    // -------------------------------------------------------------
    // Output Monitor
    // -------------------------------------------------------------
    // always @(posedge clk) begin
    //         $write("[%0t] OUT VALID: exp_o_out[1]=%0d, exp_v_out[1]=%0d",
    //                $time,
    //                exp_o_out[1],
    //                exp_v_out[1]);

    //         // Print only first few elements for readability
    //         if (DIM > 10) begin
    //             $write(" ... dim=%0d", DIM);
    //         end

    //         $display("");
    // end

    // -------------------------------------------------------------
    // Downstream backpressure generator
    // -------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst)
            // rdy_in <= $urandom_range(0, 1);  // random 0/1
            rdy_in <= 1;
    end


    STAR_VECTOR_T o_prev_rand;
    STAR_VECTOR_T v_prev_rand;
    logic signed [8:0] m_send;
    logic signed [8:0] m_prev_send;
    logic signed [8:0] s_send;
    real o_star_test;
    int count, count_total;

    // -------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------
    initial begin
        $dumpfile("../expmul.vcd");
        $dumpvars(0, tb_expmul.dut);
        wait(!rst);
        @(posedge clk);

        // ---------------------------------------------------------
        // Directed tests
        // ---------------------------------------------------------
        rand_vector(o_prev_rand);
        rand_vector(v_prev_rand);
        $display("v_prev_rand[1]: %d", v_prev_rand[1]);
        count = 0;
        count_total = 0;
        o_star_test = 0;
        // for (s_send = -256; s_send < 255; s_send++)begin
        //     for (m_prev_send = s_send; m_prev_send < 255; m_prev_send++)begin
            for (int a = 0; a < 4096; a++) begin
                    //m_prev_send = $urandom_range(-256, 255);
                    s_send = $urandom_range(-256, 255);
                    m_send = $urandom_range(s_send, 255);
                    m_prev_send = $urandom_range(-256, m_send);
                if ((m_send > s_send) && (m_send > m_prev_send)) begin
                    send_tx(m_send, m_prev_send, s_send, v_prev_rand, o_prev_rand);
                    #25;
                    o_star_test = ((o_star_test) * 2.0**(round_half_toward_zero(((q44_to_real(m_prev_send) - q44_to_real(m_send)) + (q44_to_real(m_prev_send) - q44_to_real(m_send))/2.0 - (q44_to_real(m_prev_send) - q44_to_real(m_send))/16.0)))) + (v_prev_rand[1]/real'(1<<17) * 2.0**round_half_toward_zero(((q44_to_real(s_send)-q44_to_real(m_send)) + (q44_to_real(s_send)-q44_to_real(m_send))/2.0 - (q44_to_real(s_send)-q44_to_real(m_send))/16.0)));
                //$display("power thing: %f", (round_half_toward_zero((q44_to_real(s_send)-q44_to_real(m_send)) + (q44_to_real(s_send)-q44_to_real(m_send))/2.0 - (q44_to_real(s_send)-q44_to_real(m_send))/16.0)));
                //$display("v_prev_rand[1]: %f", v_prev_rand[1]/real'(1<<17));
                    count_total++;
                    // if ($abs(q917_to_real(exp_v_out[1])-v_prev_rand[1]/real'(1<<17) * 2.0**(round_half_toward_zero(((q44_to_real(s_send)-q44_to_real(m_send)) + (q44_to_real(s_send)-q44_to_real(m_send))/2.0 - (q44_to_real(s_send)-q44_to_real(m_send))/16.0)))) > 1e-3) begin
                    if (q917_to_real(exp_v_out[1]) != v_prev_rand[1]/real'(1<<17) * 2.0**(limit_output(round_half_toward_zero(((q44_to_real(s_send)-q44_to_real(m_send)) + (q44_to_real(s_send)-q44_to_real(m_send))/2.0 - (q44_to_real(s_send)-q44_to_real(m_send))/16.0))))) begin
                        $display("s_send: %f, m_send: %f\n", q44_to_real(s_send), q44_to_real(m_send));
                        $display("Ideal v_out_1 value: %f ", v_prev_rand[1]/real'(1<<17) * 2.0**round_half_toward_zero(((q44_to_real(s_send)-q44_to_real(m_send)) + (q44_to_real(s_send)-q44_to_real(m_send))/2.0 - (q44_to_real(s_send)-q44_to_real(m_send))/16.0))); 
                        $display("Actual v_out_1 value: %f\n", q917_to_real(exp_v_out[1]));
                        count++;
                    end
                    // if (vld_out) begin
                    //     $display("Expmul o out[1]: %f", q917_to_real(exp_o_out[1]));
                    //     $display("Expmul o out ideal: %f", o_star_test);
                    // end
                end
            end
        
        // send_tx(real_to_fixed(0.625, 4), real_to_fixed(0.25, 4), real_to_fixed(0.25, 4), v_prev_rand, o_prev_rand);
        // $display("Ideal v_out_1 value: %f ", v_prev_rand[1]/(1<<17) * 2.0**((0.25-0.625) * 1.442695)); 
        // #50;
        // for (int i = 0; i < DIM; i++) begin
        //     v_prev_rand[i] = exp_v_out[i];
        //     o_prev_rand[i] = exp_o_out[i];
        // end
        // $display("Acutal v_out_1 value int: %d ", exp_v_out[1]);
        // $display("Actual v_out_1 value: %f\n", q917_to_real(exp_v_out[1]));
        // send_tx(real_to_fixed(30.0, 4), real_to_fixed(23.0, 4), real_to_fixed(28.0, 4), v_prev_rand, o_prev_rand);
        // #50;

        // ---------------------------------------------------------
        // Random tests
        // ---------------------------------------------------------
        //repeat (20) begin
          //  rand_vector(o_prev_rand);
        //     rand_vector(v_prev_rand);

        //     send_tx(
        //         $urandom_range(0, 100),
        //         $urandom_range(0, 100),
        //         $urandom_range(0, 100),
        //         o_prev_rand,
        //         v_prev_rand
        //     );
        // end
        // #200;
        #200;
        $display("Count: %d", count);
        $display("Count Total: %d", count_total);
        // $display("Expmul o out[1]: %f", q917_to_real(exp_o_out[1]));
        // $display("Expmul o out ideal: %f", o_star_test);
        $display("==== TEST COMPLETE ====");
        $finish;
    end

endmodule
