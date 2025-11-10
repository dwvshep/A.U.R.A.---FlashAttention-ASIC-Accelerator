//This is the top-level module for the AURA accelerator
//This is where memory interfaces should be instantiated and connected to the processing elements

module top(
    input clk, // System clock
    input rst, // System reset

    //Memory interface signals copied from 470 template
    input MEM_TAG   mem2proc_transaction_tag, // Memory tag for current transaction
    input MEM_BLOCK mem2proc_data,            // Data coming back from memory
    input MEM_TAG   mem2proc_data_tag,        // Tag for which transaction data is for

    output MEM_COMMAND proc2mem_command, // Command sent to memory
    output ADDR        proc2mem_addr,    // Address sent to memory
    output MEM_BLOCK   proc2mem_data,     // Data sent to memory

    //Maybe add some output packet like the commits in 470 to test end-to-end functionality using writeback/output_mem files
);

    //Internal Data Signals
    Q_VECTOR_T q_vector;
    K_VECTOR_T k_vector;
    V_VECTOR_T v_vector;
    V_VECTOR_T v_vector_delayed;
    V_VECTOR_T v_vector_double_delayed;
    INT_T score;
    INT_T score_delayed;
    INT_T max_score;
    INT_T max_score_prev;
    STAR_VECTOR_T exp_o_vector;
    STAR_VECTOR_T exp_v_vector;
    STAR_VECTOR_T output_vector;
    O_VECTOR_T output_vector_scaled;

    //Internal Handshake Signals
    logic dot_product_valid;
    logic dot_product_ready;
    logic max_valid;
    logic max_ready;
    logic expmul_valid;
    logic expmul_ready;
    logic vec_add_valid;
    logic vec_add_ready;
    logic vector_division_valid;
    logic vector_division_ready;

    //Instantiate SRAMs for Q tiles, K vectors, and V vectors
    SRAM Q_TILE_SRAM (
        .clock(clk),
        .reset(rst),
        // Read port 0
        .re(),       // Read enable
        .raddr(),    // Read address
        .rdata(),    // Read data
        // Write port
        .we(),       // Write enable
        .waddr(),    // Write address
        .wdata()     // Write data
    );

    SRAM K_VECTOR_SRAM (
        .clock(clk),
        .reset(rst),
        // Read port 0
        .re(),       // Read enable
        .raddr(),    // Read address
        .rdata(),    // Read data
        // Write port
        .we(),       // Write enable
        .waddr(),    // Write address
        .wdata()     // Write data
    );

    SRAM V_VECTOR_SRAM (
        .clock(clk),
        .reset(rst),
        // Read port 0
        .re(),       // Read enable
        .raddr(),    // Read address
        .rdata(),    // Read data
        // Write port
        .we(),       // Write enable
        .waddr(),    // Write address
        .wdata()     // Write data
    );

    dot_product dot_product_inst (
        .clk(clk),
        .rst(rst),
        .vld_in(),
        .rdy_in(max_ready),
        .vld_out(dot_product_valid),
        .rdy_out(dot_product_ready),
        .q_in(q_vector),
        .k_in(k_vector),
        .v_in(v_vector),
        .s_out(score),
        .v_out(v_vector_delayed)
    );

    max max_inst (
        .clk(clk),
        .rst(rst),
        .vld_in(dot_product_valid),
        .rdy_in(),
        .vld_out(),
        .rdy_out(),
        .s_in(score),
        .m_prev_in(max_score),
        .v_in(v_vector_delayed),
        .m_out(max_score),
        .s_out(score_delayed),
        .m_prev_out(max_score_prev),
        .v_out(v_vector_double_delayed)
    );

    expmul_stage expmul_stage_inst (
        .clk(clk),
        .rst(rst),
        .vld_in(v_handshake_reg_2_valid),
        .rdy_in(vector_division_ready),
        .vld_out(expmul_valid),
        .rdy_out(expmul_ready),
        .m_in(max_score),
        .m_prev_in(max_score_prev),
        .o_star_prev_in(output_vector),
        .s_in(score_delayed),
        .v_star_in({1, v_vector_double_delayed}),
        .exp_v_out(exp_v_vector),
        .exp_o_out(exp_o_vector)
    );

    vec_add vec_add_inst (
        .clk(clk),
        .rst(rst),
        .vld_in(),
        .rdy_in(),
        .vld_out(),
        .rdy_out(),
        .vec_a_in(exp_o_vector),
        .vec_b_in(exp_v_vector),
        .vec_out(output_vector)
    );

    vector_division vector_division_inst (
        .clk(clk),
        .rst(rst),
        .vld_in(),
        .rdy_in(),
        .vld_out(),
        .rdy_out(),
        .vec_in(output_vector[`MAX_EMBEDDING_DIM-1:0]),
        .divisor_in(output_vector[`MAX_EMBEDDING_DIM]),
        .vec_out(output_vector_scaled)
    );

endmodule