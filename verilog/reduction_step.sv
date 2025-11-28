//This module computes the sum of a list of inputs in a tree-like fashion

`include "include/sys_defs.svh"

module reduction_step #(
    parameter int INPUT_LEN      = `MAX_EMBEDDING_DIM,
    parameter int W_IN           = 2*`INTEGER_WIDTH,  // width of each input operand
    parameter int STEPS          = 1,
    parameter int W_OUT          = W_IN + STEPS,  // width of sum
    parameter int OUTPUT_LEN     = INPUT_LEN >> STEPS
)(
    //control signals
    input  clk,
    input  rst,

    //Handshake signals
    input  vld_in,
    input  rdy_in,
    output vld_out,
    output rdy_out,

    //Data signals
    input  logic signed  [W_IN-1:0] list_in  [0:INPUT_LEN-1],
    output logic signed [W_OUT-1:0] list_out [0:OUTPUT_LEN-1]
);

    //Internal Pipeline Registers
    logic signed [W_IN-1:0] list [0:INPUT_LEN-1];
    logic valid_reg;

    assign vld_out = valid_reg;
    assign rdy_out = rdy_in || !valid_reg;

    //Latch inputs first
    always_ff @(posedge clk) begin
        //$display("[REDUCTION STEP LATCH]");
        if(rst) begin
            //list <= '0;
            for (int i = 0; i < INPUT_LEN; i++) begin
                list[i] <= '0;
            end
            valid_reg <= 1'b0;
        end else begin
            if(vld_in && rdy_out) begin //Handshake successful
                //list <= list_in;
                for (int i = 0; i < INPUT_LEN; i++) begin
                    list[i] <= list_in[i];
                end
                valid_reg <= 1'b1;
            end else if(rdy_in) begin //Only downstream is ready (clear internal pipeline)
                valid_reg <= 1'b0;
            end
        end
        // $display("valid_reg: %0b", valid_reg);
        // $display("list[0]: %0b",
                // list[0]);
        // for (int i = 0; i < INPUT_LEN; ++i) begin
        //     $display("list[%0d]: %0b",
        //     i, list[i]);
        // end
    end

    //outputs are combinational
    logic signed [W_OUT-1:0] temp   [0:INPUT_LEN-1];
    logic signed [W_OUT-1:0] stageN [0:INPUT_LEN-1];
    int out_len;
    always_comb begin
        //sign extend inputs first
        for(int i = 0; i < INPUT_LEN; i++) begin
            stageN[i] = {{(W_OUT-W_IN){list[i][W_IN-1]}}, list[i]};
        end

        out_len = INPUT_LEN >> 1;

        //Reduce
        for(int s = 0; s < STEPS; s++) begin
            // Pairwise sum: stageN → temp
            for (int i = 0; i < out_len; i++) begin
                temp[i] = stageN[2*i] + stageN[2*i+1];
            end

            // Copy temp → stageN for next pass (shrinking)
            for (int j = 0; j < out_len; j++) begin
                stageN[j] = temp[j];
            end

            out_len = out_len >> 1;
        end

        //Copy to final output list
        for (int i = 0; i < OUTPUT_LEN; i++) begin
            list_out[i] = stageN[i];
        end
    end

endmodule