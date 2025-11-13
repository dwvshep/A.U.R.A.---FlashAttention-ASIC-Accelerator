//This is the top-level module for the AURA accelerator
//This is where memory interfaces should be instantiated and connected to the processing elements

module top(
    input clk, // System clock
    input rst, // System reset

    //CPU Command Register Interface

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
    O_VECTOR_T output_vector_scaled;

    //Internal Handshake Signals
    logic Q_vld_in;
    logic K_vld_in;
    logic V_vld_in;
    logic Q_rdy_out;
    logic K_rdy_out;
    logic V_rdy_out;
    logic ctrl_ready;
    logic output_valid;
    
    //Instantiate SRAMs for Q tiles, K vectors, V vectors, and O vectors
    QSRAM QSRAM_inst (
        .clock(clk),
        .reset(rst),
        
        .write_enable(),    //Asserted when memory controller is ready to write an entire row
        .read_enable(),     //Asserted when all backend PEs are ready to read
        .read_data_valid(),    //Assert when entire bank is ready to be read
        .sram_ready(),        //Asserted when the fill bank can accept a new row

        .write_data(),      // Input write data
        .read_data()        // Output read data array
    );

    KSRAM KSRAM_inst (
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

    VSRAM VSRAM_inst (
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

    OSRAM OSRAM_inst (
        .clock(clk),
        .reset(rst),
        
        .write_enable(),    //Asserted when PEs are ready to write an entire bank (can just check the first one)
        .drain_enable(),     //Asserted when all backend PEs are ready to read
        .drain_data_valid(),  //Assert when any data in the drain bank is ready to be sent to memory
        .sram_ready(),        //Asserted when the fill bank
        
        .write_data(),      // Input write data array
        .drain_data()       // Output drain data
    );


    //Instantiate control module and backend processing modules
    memory_controller ctrl_inst (
        .clk(clk),
        .rst(rst),
        // Connect other signals as needed
    );

    PE pe_inst (
        .clk(clk),
        .rst(rst),

        .Q_vld_in(Q_vld_in),
        .K_vld_in(K_vld_in),
        .V_vld_in(V_vld_in),

        .Q_rdy_out(Q_rdy_out),
        .K_rdy_out(K_rdy_out),
        .V_rdy_out(V_rdy_out),

        .ctrl_ready(),
        .output_valid(),
        
        .q_vector(q_vector),
        .k_vector(k_vector),
        .v_vector(v_vector),
        .output_vector_scaled(output_vector_scaled)
    );

endmodule