//This modeule computes the dot product between a Q vector and a K vector
//The result is then scaled by dividing by the square root of the matrix dimension
//If we assume dk = 64, then dividing by root dk is equivalent to >> 3

`include "include/sys_defs.svh"

module dot_product (
    //control signals
    input clk,
    input rst,

    //Handshake signals
    input Q_vld_in,    //Upstream valid
    input K_vld_in,    //Upstream valid
    input V_vld_in,    //Upstream valid
    input rdy_in,      //Downstream ready
    output vld_out,    //Outputs from this cycle are valid
    output Q_rdy_out,  //Ready to accept new Q inputs
    output K_rdy_out,  //Ready to accept new K inputs
    output V_rdy_out,  //Ready to accept new V inputs

    //Data signals
    input Q_VECTOR_T q_in,
    input K_VECTOR_T k_in,
    input V_VECTOR_T v_in,
    output SCORE_QT s_out,
    output V_VECTOR_T v_out
);

    //Internal Pipeline Registers
    Q_VECTOR_T q;
    K_VECTOR_T k;
    V_VECTOR_T v;
    logic valid_q;
    logic valid_k;
    logic valid_v;
    logic [$clog2(`MAX_SEQ_LENGTH)-1:0] row_counter;

    //Internal Handshake signals
    logic reduction_rdy;
    logic all_valid;

    assign all_valid = valid_q && valid_k && valid_v;
    assign Q_rdy_out = !valid_q || (all_valid && reduction_rdy && (row_counter == 0));
    assign K_rdy_out = !valid_k || (all_valid && reduction_rdy);
    assign V_rdy_out = !valid_v || (all_valid && reduction_rdy);

    //Internal Data signals
    // logic signed [W_PROD-1:0] products [LEN];
    // logic signed [W_SUM-1:0]  sum;
    PRODUCT_QT products [`MAX_EMBEDDING_DIM];
    INTERMEDIATE_PRODUCT_QT intermediate_products [`MAX_EMBEDDING_DIM];
    DOT_QT sum;
    //DOT_QT shifted_sum;
    SCORE_QT sum_conv;

    //Latch Q input
    always_ff @(posedge clk) begin
        //$display("[DOT PRODUCT Q LATCH]");
        if(rst) begin
            //$display("RESET");
            q <= '0;
            valid_q <= 1'b0;
            row_counter <= '0;
        end else begin
            if(Q_vld_in && Q_rdy_out) begin //Handshake successful
                q <= q_in;
                valid_q <= 1'b1;
                row_counter <= `MAX_SEQ_LENGTH - 1;
            end else if(all_valid && reduction_rdy && (row_counter != 0)) begin
                row_counter <= row_counter - 1;
            end else if(all_valid && reduction_rdy && (row_counter == 0)) begin //Only downstream is ready (clear internal pipeline)
                valid_q <= 1'b0;
            end
        end
        // $display("valid_q: %0b", valid_q);
        // $display("row_counter: %0d", row_counter);
        // for (int i = 0; i < `MAX_EMBEDDING_DIM; ++i) begin
        //     $display("q[%0d]: %0b OR %0f",
        //     i, q[i], q[i]/128.0);
        // end
    end

    //Latch K inputs
    always_ff @(posedge clk) begin
        if(rst) begin
            k <= '0;
            valid_k <= 1'b0;
        end else begin
            if(K_vld_in && K_rdy_out) begin //Handshake successful
                k <= k_in;
                valid_k <= 1'b1;
            end else if(all_valid && reduction_rdy) begin //Only downstream is ready (clear internal pipeline)
                valid_k <= 1'b0;
            end
        end
    end

    //Latch V inputs
    always_ff @(posedge clk) begin
        if(rst) begin
            v <= '0;
            valid_v <= 1'b0;
        end else begin
            if(V_vld_in && V_rdy_out) begin //Handshake successful
                v <= v_in;
                valid_v <= 1'b1;
            end else if(all_valid && reduction_rdy) begin //Only downstream is ready (clear internal pipeline)
                valid_v <= 1'b0;
            end
        end
    end

    //Multiply - Intermediate Full Width Results
    always_comb begin
        for(int i = 0; i < `MAX_EMBEDDING_DIM; i++) begin
            intermediate_products[i] = q[i] * k[i];
        end
    end

    //
    generate
        for(genvar p = 0; p < `MAX_EMBEDDING_DIM; p++) begin
            q_convert #(
                .IN_I(`INTERMEDIATE_PRODUCT_I), 
                .IN_F(`INTERMEDIATE_PRODUCT_F), 
                .OUT_I(`PRODUCT_I), 
                .OUT_F(`PRODUCT_F)
            ) prod_conv_inst (
                .in(intermediate_products[p]),
                .out(products[p])
            );
        end
    endgenerate

    //Tree Reduction
    tree_reduce #(
        .STAGES(3)
    ) tree_inst (
        .clk(clk),
        .rst(rst),

        .vld_in(all_valid),
        .rdy_in(rdy_in),
        .vld_out(vld_out),
        .rdy_out(reduction_rdy),

        .list_in(products),
        .sum(sum)
    );

    //scale by root(dk)
    //assign shifted_sum = sum >>> 3;
    q_convert #(
        .IN_I(`DOT_I), 
        .IN_F(`DOT_F), 
        .OUT_I(`SCORE_I), 
        .OUT_F(`SCORE_F)
    ) scale_conv_inst (
        .in(sum), //shifted_sum
        .out(sum_conv) //s_out
    );

    assign s_out = sum_conv >>> 3;

endmodule