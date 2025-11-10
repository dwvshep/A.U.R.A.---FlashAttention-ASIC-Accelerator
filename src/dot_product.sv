//This modeule computes the dot product between a Q vector and a K vector
//The result is then scaled by dividing by the square root of the matrix dimension
//If we assume dk = 64, then dividing by root dk is equivalent to >> 3

module dot_product(
    //control signals
    input clk,
    input rst,

    //Handshake signals
    input vld_in,   //Upstream valid
    input rdy_in,   //Downstream ready
    output vld_out, //Outputs from this cycle will are valid
    output rdy_out, //Ready to accept new inputs

    //Data signals
    input Q_VECTOR_T q_in,
    input K_VECTOR_T k_in,
    output INT_T s_out
);

    //Internal Pipeline Registers
    Q_VECTOR_T q;
    K_VECTOR_T k;
    logic valid_reg;

    assign vld_out = valid_reg;
    assign rdy_out = rdy_in;

    //Latch inputs first
    always_ff @(posedge clk) begin
        if(rst) begin
            q <= '0;
            k <= '0;
            valid_reg <= 1'b0;
        end else begin
            if(vld_in && rdy_in) begin //Handshake successful
                q <= q_in;
                k <= k_in;
                valid_reg <= 1'b1;
            end else if(rdy_in) begin //Only downstream is ready (clear internal pipeline)
                valid_reg <= 1'b0;
            end
        end
    end

    //output is combinational
    always_comb begin
        //See implementation options from chatgpt below (I like Option 2)
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