//This is the top-level module for the AURA accelerator
//This is where memory interfaces should be instantiated and connected to the processing elements

module AURA(
    input clk, // System clock
    input rst, // System reset

    //Memory interface signals copied from 470 template
    input  MEM_TAG     mem2proc_transaction_tag, // Memory tag for current transaction
    input  MEM_BLOCK   mem2proc_data,            // Data coming back from memory
    input  MEM_TAG     mem2proc_data_tag,        // Tag for which transaction data is for

    output MEM_COMMAND proc2mem_command, // Command sent to memory
    output ADDR        proc2mem_addr,    // Address sent to memory
    output MEM_BLOCK   proc2mem_data,     // Data sent to memory

    // Done flag for the testbench
    output logic       done
);

    //Memory controller handshake signals
    logic Q_sram_rdy;
    logic K_sram_rdy;
    logic V_sram_rdy;
    logic O_sram_vld;
    logic ctrl_O_rdy;
    logic ctrl_Q_vld;
    logic ctrl_K_vld;
    logic ctrl_V_vld;

    //Memory controller data signals
    // Q_VECTOR_T loaded_Q_vector;
    // K_VECTOR_T loaded_K_vector;
    // V_VECTOR_T loaded_V_vector;
    Q_VECTOR_T loaded_vector;
    O_VECTOR_T drained_vector;

    //Internal Handshake Signals
    logic Q_vld;
    logic K_vld;
    logic V_vld;
    logic Q_rdy [`NUM_PES];
    logic K_rdy [`NUM_PES];
    logic V_rdy [`NUM_PES];
    logic O_vld [`NUM_PES];
    logic O_sram_rdy;
    
    //Internal Data Signals
    Q_VECTOR_T q_vectors [`NUM_PES];
    K_VECTOR_T k_vector;
    V_VECTOR_T v_vector;
    O_VECTOR_T output_vectors_scaled [`NUM_PES];

    //Instantiate memory controller
    memory_controller mem_ctrl_inst (
        .clk(clk),
        .rst(rst),

        .mem2proc_transaction_tag(mem2proc_transaction_tag),
        .mem2proc_data(mem2proc_data),
        .mem2proc_data_tag(mem2proc_data_tag),
        .proc2mem_command(proc2mem_command),
        .proc2mem_addr(proc2mem_addr),
        .proc2mem_data(proc2mem_data),
    
        .Q_sram_rdy(Q_sram_rdy),
        .K_sram_rdy(K_sram_rdy),
        .V_sram_rdy(V_sram_rdy),
        .O_sram_vld(O_sram_vld),
        .ctrl_O_rdy(ctrl_O_rdy),
        .ctrl_Q_vld(ctrl_Q_vld),
        .ctrl_K_vld(ctrl_K_vld),
        .ctrl_V_vld(ctrl_V_vld),
        
        .drained_vector(drained_vector),
        .loaded_vector(loaded_vector),

        .done(done)
    );
    
    //Instantiate SRAMs for Q tiles, K vectors, V vectors, and Output tiles
    QSRAM QSRAM_inst (
        .clk(clk),
        .rst(rst),
        
        .write_enable(ctrl_Q_vld),    //Asserted when memory controller is ready to write an entire row
        .read_enable(Q_rdy[0]),     //Asserted when all backend PEs are ready to read (just check the first one)
        .read_data_valid(Q_vld),    //Assert when entire bank is ready to be read
        .sram_ready(Q_sram_rdy),        //Asserted when the fill bank can accept a new row

        .write_data(loaded_vector),      // Input write data
        .read_data(q_vectors)        // Output read data array
    );

    KSRAM KSRAM_inst (
        .clk(clk),
        .rst(rst),
        
        .write_enable(ctrl_K_vld),    //Asserted when memory controller is ready to write an entire row
        .read_enable(K_rdy[0]),     //Asserted when all backend PEs are ready to read (can just check the first one)
        .read_data_valid(K_vld),    //Assert when entire bank is ready to be read
        .sram_ready(K_sram_rdy),        //Asserted when the fill bank can accept a new row

        .write_data(loaded_vector),      // Input write data
        .read_data(k_vector)        // Output read data
    );

    VSRAM VSRAM_inst (
        .clk(clk),
        .rst(rst),
        
        .write_enable(ctrl_V_vld),    //Asserted when memory controller is ready to write an entire row
        .read_enable(V_rdy[0]),     //Asserted when all backend PEs are ready to read (can just check the first one)
        .read_data_valid(V_vld),    //Assert when entire bank is ready to be read
        .sram_ready(V_sram_rdy),        //Asserted when the fill bank can accept a new row

        .write_data(loaded_vector),      // Input write data
        .read_data(v_vector)        // Output read data
    );

    OSRAM OSRAM_inst (
        .clk(clk),
        .rst(rst),
        
        .write_enable(O_vld[0]),    //Asserted when PEs are ready to write an entire bank (can just check the first one)
        .drain_enable(ctrl_O_rdy),     //Asserted when all backend PEs are ready to read
        .drain_data_valid(O_sram_vld),  //Assert when any data in the drain bank is ready to be sent to memory
        .sram_ready(O_sram_rdy),        //Asserted when the fill bank
        
        .write_data(output_vectors_scaled),      // Input write data array
        .drain_data(drained_vector)       // Output drain data
    );


    //Instantiate backend processing modules
    generate
        for (genvar i = 0; i < `NUM_PES; i++) begin : gen_pe
            PE pe_inst (
                .clk(clk),
                .rst(rst),

                .Q_vld_in(Q_vld),
                .K_vld_in(K_vld),
                .V_vld_in(V_vld),

                .Q_rdy_out(Q_rdy[i]),
                .K_rdy_out(K_rdy[i]),
                .V_rdy_out(V_rdy[i]),

                .O_sram_rdy(O_sram_rdy),
                .output_valid(O_vld[i]),
                
                .q_vector(q_vectors[i]),
                .k_vector(k_vector),
                .v_vector(v_vector),
                .output_vector_scaled(output_vectors_scaled[i])
            );
        end
    endgenerate

    // `ifdef AURA_DEBUG
    //     always_ff @(posedge clk) begin
    //         $display("[DIV_DBG] valid_in: %0b, valid_reg: %0b, valid_out: %0b, ready_in: %0b, ready_out: %0b", 
    //             gen_pe[0].pe_inst.vector_division_inst.gen_div[0].div_inst.vld_in,
    //             gen_pe[0].pe_inst.vector_division_inst.gen_div[0].div_inst.valid_reg,
    //             gen_pe[0].pe_inst.vector_division_inst.gen_div[0].div_inst.vld_out,
    //             gen_pe[0].pe_inst.vector_division_inst.gen_div[0].div_inst.rdy_in,
    //             gen_pe[0].pe_inst.vector_division_inst.gen_div[0].div_inst.rdy_out,
    //         );
    //     end
    // `endif

endmodule