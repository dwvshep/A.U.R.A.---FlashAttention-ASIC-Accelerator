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



endmodule