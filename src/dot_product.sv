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
    output SCORE_QT s_out
    output V_VECTOR_T v_out
);

    //Internal Handshake signals


    //Internal Data signals
    //Products array here

    //Multiply gen block


    //Tree Reduction
    tree_reduce tree_inst


endmodule