//This modeule computes the dot product between a Q vector and a K vector
//The result is then scaled by dividing by the square root of the matrix dimension
//If we assume dk = 64, then dividing by root dk is equivalent to >> 3

module dot_product import sys_defs_pkg::*; (
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
    DOT_QT sum, shifted_sum;

    //Latch Q input
    always_ff @(posedge clk) begin
        if(rst) begin
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
            end else if(all_valid && rdy_in) begin //Only downstream is ready (clear internal pipeline)
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
            end else if(all_valid && rdy_in) begin //Only downstream is ready (clear internal pipeline)
                valid_v <= 1'b0;
            end
        end
    end

    //Multiply 
    always_comb begin
        for(int i = 0; i < `MAX_EMBEDDING_DIM; i++) begin
            products[i] = q[i] * k[i];
        end
    end

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
    assign shifted_sum = sum >>> 3;
    assign s_out = q_convert(7, 6, 4, 3, shifted_sum);

endmodule