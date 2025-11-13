//This modeule computes the dot product between a Q vector and a K vector
//The result is then scaled by dividing by the square root of the matrix dimension
//If we assume dk = 64, then dividing by root dk is equivalent to >> 3

module dot_product(
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
    output INT_T s_out
    output V_VECTOR_T v_out
);

    //Internal Pipeline Registers
    Q_VECTOR_T q;
    K_VECTOR_T k;
    V_VECTOR_T v;
    logic valid_q;
    logic valid_k;
    logic valid_v;
    logic all_valid;
    logic [$clog2(`MAX_SEQ_LENGTH)-1:0] row_counter;

    assign all_valid = valid_q && valid_k && valid_v;
    assign vld_out = all_valid;
    assign Q_rdy_out = !valid_q || (all_valid && rdy_in && (row_counter == 0));
    assign K_rdy_out = !valid_k || (all_valid && rdy_in);
    assign V_rdy_out = !valid_v || (all_valid && rdy_in);

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
            end else if(all_valid && rdy_in && (row_counter != 0)) begin
                row_counter <= row_counter - 1;
            end else if(all_valid && rdy_in && (row_counter == 0)) begin //Only downstream is ready (clear internal pipeline)
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

    //output is combinational
    always_comb begin
        v_out = v;
        //See logic implementation options from chatgpt below (I like Option 2)
    end

    //Option 1: Fully combinational (single-cycle MAC tree)
    always_comb begin
        logic signed [INT_WIDTH+log2(dk)-1:0] acc;
        acc = '0;
        for (int i = 0; i < DK; i++) begin
            acc += q[i] * k[i];
        end
        s_out = acc >>> 3; // divide by sqrt(64)
    end

    //Option 2: Pipelined / partially combinational tree
    logic signed [INT_WIDTH+3:0] partial_sum [0:7];

    always_comb begin
        for (int g = 0; g < 8; g++) begin
            partial_sum[g] = '0;
            for (int i = 0; i < 8; i++)
                partial_sum[g] += q[g*8+i] * k[g*8+i];
        end
        logic signed [INT_WIDTH+6:0] acc = '0;
        for (int g = 0; g < 8; g++)
            acc += partial_sum[g];
        s_out = acc >>> 3;
    end
    
    //Option 3: Sequential MAC (1 multiplier reused)
    always_ff @(posedge clk) begin
        if (rst) begin
            acc <= '0;
            idx <= 0;
            valid_reg <= 0;
        end else if (vld_in && rdy_in) begin
            acc <= acc + q_in[idx] * k_in[idx];
            idx <= idx + 1;
            if (idx == DK-1) begin
                s_out <= acc >>> 3;
                valid_reg <= 1;
            end
        end
    end


endmodule