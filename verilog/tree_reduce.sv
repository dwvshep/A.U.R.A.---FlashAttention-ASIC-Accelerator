//This module computes the sum of a list of inputs in a tree-like fashion
//Assumes LEN is a power of 2
//STAGES must divide evenly into $clog2(LEN)

`include "include/sys_defs.svh"

module tree_reduce #(
    parameter int LEN      = `MAX_EMBEDDING_DIM,
    parameter int W_IN     = `Q_WIDTH(`PRODUCT_I, `PRODUCT_F),  // width of each input operand
    parameter int W_OUT    = W_IN + $clog2(LEN),    // width of sum
    parameter int STAGES   = $clog2(LEN),
    parameter int REDUCTIONS_PER_STAGE = (W_OUT-W_IN)/STAGES
)(
    //control signals
    input clk,
    input rst,

    //Handshake signals
    input vld_in,
    input rdy_in,
    output vld_out,
    output rdy_out,

    //Data signals
    input  logic signed  [W_IN-1:0] list_in [0:LEN-1],
    output logic signed [W_OUT-1:0] sum
);

    // ------------------------------------------------------------
    // Handshake wiring between stages
    // ------------------------------------------------------------
    logic vld_stage [0:STAGES];
    logic rdy_stage [0:STAGES];

    assign vld_stage[0]      = vld_in;      // input to first stage
    assign rdy_out           = rdy_stage[0];

    assign vld_out           = vld_stage[STAGES];
    assign rdy_stage[STAGES] = rdy_in;

    generate
        for(genvar s = 0; s < STAGES; s++) begin : STAGE
            localparam int IN_LEN  = LEN >> (s*REDUCTIONS_PER_STAGE);
            localparam int OUT_LEN = LEN >> ((s+1)*REDUCTIONS_PER_STAGE);
            localparam int IN_WIDTH = W_IN + (s*REDUCTIONS_PER_STAGE);
            localparam int OUT_WIDTH = W_IN + ((s+1)*REDUCTIONS_PER_STAGE);
            
            logic signed [IN_WIDTH-1:0]  stage_list_in  [0:IN_LEN-1];
            logic signed [OUT_WIDTH-1:0] stage_list_out [0:OUT_LEN-1];

            //Assign list_in to first stage's input, else last stage's output
            if (s == 0) begin : FIRST
                for (genvar i = 0; i < IN_LEN; i++) begin : COPY0
                    assign stage_list_in[i] = list_in[i];
                end
            end
            else begin : NOT_FIRST
                for (genvar i = 0; i < IN_LEN; i++) begin : COPYN
                    assign stage_list_in[i] = STAGE[s-1].stage_list_out[i];
                end
            end

            reduction_step #(
                    .INPUT_LEN (IN_LEN),         // LEN >> s*REDUCTIONS_PER_STAGE
                    .W_IN      (IN_WIDTH),       // already at full accumulation width
                    .STEPS     (REDUCTIONS_PER_STAGE),
                    .W_OUT     (OUT_WIDTH),
                    .OUTPUT_LEN(OUT_LEN)
            ) reduce_step_inst (
                    .clk     (clk),
                    .rst     (rst),
                    .vld_in  (vld_stage[s]),
                    .rdy_in  (rdy_stage[s+1]),
                    .vld_out (vld_stage[s+1]),
                    .rdy_out (rdy_stage[s]),

                    // connect from previous stage's list_out
                    .list_in (stage_list_in),
                    .list_out(stage_list_out)
                );
        end
    endgenerate

    assign sum = STAGE[STAGES-1].stage_list_out[0];

endmodule