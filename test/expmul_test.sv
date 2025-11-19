`timescale 1ns/1ps

`include "include/sys_defs.svh"

module tb_expmul;


    // ---------------------------------------------------------
    // Testbench signals
    // ---------------------------------------------------------
    logic clk;
    logic rst;

    logic vld_in;
    logic rdy_in;
    logic vld_out;
    logic rdy_out;

    SCORE_QT          m_in;
    SCORE_QT          m_prev_in;
    EXPMUL_VSHIFT_QT  o_star_prev_in;
    SCORE_QT          s_in;
    EXPMUL_VSHIFT_QT  v_star_in;

    EXPMUL_VSHIFT_QT  exp_v_out;
    EXPMUL_VSHIFT_QT  exp_o_out;

    // ---------------------------------------------------------
    // Clock Generation
    // ---------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end

    // ---------------------------------------------------------
    // Reset generator
    // ---------------------------------------------------------
    initial begin
        rst = 1;
        vld_in = 0;
        rdy_in = 1;  // downstream initially ready
        #40;
        rst = 0;
    end

    // ---------------------------------------------------------
    // Instantiate DUT
    // ---------------------------------------------------------
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

    // ---------------------------------------------------------
    // Handshake + Stimulus Driver
    // ---------------------------------------------------------
    task send_transaction(
        input SCORE_QT          m,
        input SCORE_QT          m_prev,
        input EXPMUL_VSHIFT_QT  o_prev,
        input SCORE_QT          s,
        input EXPMUL_VSHIFT_QT  v_prev
    );
    begin
        // Wait until DUT ready
        @(posedge clk);
        while (!rdy_out) @(posedge clk);

        m_in           <= m;
        m_prev_in      <= m_prev;
        o_star_prev_in <= o_prev;
        s_in           <= s;
        v_star_in      <= v_prev;

        vld_in <= 1'b1;

        @(posedge clk);

        // Hold until handshake happens
        while (!(vld_in && rdy_out)) @(posedge clk);

        // Deassert valid after handshake
        vld_in <= 1'b0;

        $display("[%0t] TX Sent: m=%0d m_prev=%0d o_prev=%0d s=%0d v_prev=%0d",
                 $time, m, m_prev, o_prev, s, v_prev);
    end
    endtask


    // ---------------------------------------------------------
    // Output Monitor
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (vld_out && rdy_in) begin
            $display("[%0t] RX Received: exp_o_out=%0d exp_v_out=%0d",
                     $time, exp_o_out, exp_v_out);
        end
    end

    // ---------------------------------------------------------
    // Backpressure Generator (downstream ready)
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (!rst) begin
            // Randomly deassert rdy_in to test backpressure
            rdy_in <= {$random} % 2;
        end
    end

    // ---------------------------------------------------------
    // Test Sequence
    // ---------------------------------------------------------
    initial begin
        wait(!rst);
        @(posedge clk);

        // Directed tests
        send_transaction(10,  2, 5,  3, 7);
        send_transaction(20,  4, 6,  8, 9);

        // Randomized tests
        repeat (20) begin
            SCORE_QT          rm       = $urandom_range(0, 100);
            SCORE_QT          rm_prev  = $urandom_range(0, 100);
            EXPMUL_VSHIFT_QT  rv_prev1 = $urandom_range(0, 100);
            SCORE_QT          rs       = $urandom_range(0, 100);
            EXPMUL_VSHIFT_QT  rv_prev2 = $urandom_range(0, 100);

            send_transaction(rm, rm_prev, rv_prev1, rs, rv_prev2);
        end

        #200;
        $display("==== TEST COMPLETE ====");
        $finish;
    end

endmodule
