`include "include/sys_defs.svh"

// P4 TODO: Add your own debugging framework. Basic printing of data structures
//          is an absolute necessity for the project. You can use C functions 
//          like in test/pipeline_print.c or just do everything in verilog.
//          Be careful about running out of space on CAEN printing lots of state
//          for longer programs (alexnet, outer_product, etc.)

// These link to the pipeline_print.c file in this directory, and are used below to print
// detailed output to the pipeline_output_file, initialized by open_pipeline_output_file()
import "DPI-C" function string decode_inst(int inst);
//import "DPI-C" function void open_pipeline_output_file(string file_name);
//import "DPI-C" function void print_header();
//import "DPI-C" function void print_cycles(int clock_count);
//import "DPI-C" function void print_stage(int inst, int npc, int valid_inst);
//import "DPI-C" function void print_reg(int wb_data, int wb_idx, int wb_en);
//import "DPI-C" function void print_membus(int proc2mem_command, int proc2mem_addr,
//                                          int proc2mem_data_hi, int proc2mem_data_lo);
//import "DPI-C" function void close_pipeline_output_file();


`define TB_MAX_CYCLES 50000000
`define DEBUG
// `define SIM


module testbench;
    // string inputs for loading memory and output files
    // run like: cd build && ./simv +MEMORY=../programs/mem/<my_program>.mem +OUTPUT=../output/<my_program>
    // this testbench will generate 4 output files based on the output
    // named OUTPUT.{out cpi, wb, ppln} for the memory, cpi, writeback, and pipeline outputs.
    string Q_mem, K_mem, V_mem;
    string output_name;
    string out_outfile;// mem_output file
    int out_fileno; // verilog uses integer file handles with $fopen and $fclose

    // variables used in the testbench
    logic        clock;
    logic        reset;
    
    logic [31:0] clock_count; // also used for terminating infinite loops
    logic [31:0] instr_count;

    
    MEM_COMMAND proc2mem_command;
    ADDR        proc2mem_addr;
    MEM_BLOCK   proc2mem_data;
    MEM_TAG     mem2proc_transaction_tag;
    MEM_BLOCK   mem2proc_data;
    MEM_TAG     mem2proc_data_tag;
    MEM_SIZE    proc2mem_size;
    
    logic done;

    EXCEPTION_CODE error_status = NO_ERROR;

    
    // INST          [`N-1:0] insts;
    // ADDR          [`N-1:0] PCs;
    COMMIT_PACKET [`N-1:0] committed_insts;

    // UPDATED MEMORY
    DATA [1:0] updated_memory [`MEM_64BIT_LINES-1:0];

    localparam WIDTH = $bits(MEM_BLOCK);

    
    localparam integer K_IDX = K_BASE >> 3;  
    localparam integer V_IDX = V_BASE >> 3;
    localparam integer Q_IDX = Q_BASE >> 3;
    localparam integer O_IDX = O_BASE >> 3;
    localparam integer ROW = 512;

    
    // Instantiate the the Top-Level
    AURA AURA_dut (
        // Inputs
        .clock (clock),
        .reset (reset),
        
        .mem2proc_transaction_tag (mem2proc_transaction_tag),
        .mem2proc_data            (mem2proc_data),
        .mem2proc_data_tag        (mem2proc_data_tag),

        // Outputs
        .proc2mem_command (proc2mem_command),
        .proc2mem_addr    (proc2mem_addr),
        .proc2mem_data    (proc2mem_data),

        .done(done),
    );

    // Instantiate the Data Memory
    mem memory (
        // Inputs
        .clock            (clock),
        .proc2mem_command (proc2mem_command),
        .proc2mem_addr    (proc2mem_addr),
        .proc2mem_data    (proc2mem_data),

        // Outputs
        .mem2proc_transaction_tag (mem2proc_transaction_tag),
        .mem2proc_data            (mem2proc_data),
        .mem2proc_data_tag        (mem2proc_data_tag)
    );

    

    // Generate System Clock
    always begin
        #(`CLOCK_PERIOD/2.0);
        clock = ~clock;
    end

    // generate
    // genvar i;
    //     for(i = 0; i < `N; ++i) begin
    //         logic [63:0] mem_block;
    //         assign mem_block = memory.unified_memory[PCs[i][15:3]];
    //         assign insts[i] = PCs[i][2] ? mem_block[63:32] : mem_block[31:0];
    //     end
    // endgenerate

    initial begin
        $dumpfile("../cpu.vcd");
        $dumpvars(0, testbench.verisimpleV);
        $display("\n---- Starting CPU Testbench ----\n");

        // set paramterized strings, see comment at start of module
        if ($value$plusargs("Q_MEMORY=%s", Q_mem)) begin
            $display("Using Q memory file  : %s", Q_mem);
        end else begin
            $display("Did not receive '+Q_MEMORY=' argument. Exiting.\n");
            $finish;
        end

        if ($value$plusargs("K_MEMORY=%s", K_mem)) begin
            $display("Using K memory file  : %s", K_mem);
        end else begin
            $display("Did not receive '+K_MEMORY=' argument. Exiting.\n");
            $finish;
        end

        if ($value$plusargs("V_MEMORY=%s", V_mem)) begin
            $display("Using V memory file  : %s", V_mem);
        end else begin
            $display("Did not receive '+V_MEMORY=' argument. Exiting.\n");
            $finish;
        end

        if ($value$plusargs("OUTPUT=%s", output_name)) begin
            $display("Using output files : %s.out", output_name);
            out_outfile       = {output_name,".out"}; // this is how you concatenate strings in verilog
        end else begin
            $display("\nDid not receive '+OUTPUT=' argument. Exiting.\n");
            $finish;
        end

        clock = 1'b0;
        reset = 1'b0;

        $display("\n  %16t : Asserting Reset", $realtime);
        reset = 1'b1;

        @(posedge clock);
        @(posedge clock);

        $display("  %16t : Loading Unified Memory", $realtime);
        // load the compiled program's hex data into the memory module
        $readmemh(Q_mem, memory.unified_memory, Q_IDX, Q_IDX + ROW - 1);
        $readmemh(K_mem, memory.unified_memory, K_IDX, K_IDX + ROW - 1);
        $readmemh(V_mem, memory.unified_memory, V_IDX, V_IDX + ROW - 1);

        @(posedge clock);
        @(posedge clock);
        #1; // This reset is at an odd time to avoid the pos & neg clock edges
        $display("  %16t : Deasserting Reset", $realtime);
        reset = 1'b0;

        out_fileno = $fopen(out_outfile);

        $display("  %16t : Running Processor", $realtime);
    end

    always @(negedge clock) begin
        if (reset) begin
            // Count the number of cycles and number of instructions committed
            clock_count = 0;
            instr_count = 0;
        end else begin
            #2; // wait a short time to avoid a clock edge

            clock_count = clock_count + 1;

            if (clock_count % 10000 == 0) begin
                $display("  %16t : %d cycles", $realtime, clock_count);
            end

            // TODO: change error status to done flag

            // stop the processor
            if (done || clock_count > `TB_MAX_CYCLES) begin

                $display("  %16t : Processing Finished", $realtime);

                @(negedge clock);
                show_final_mem_and_status();

                $display("\n---- Finished CPU Testbench ----\n");

                #100 $finish;
            end
        end // if(reset)
    end


    // Show contents of Unified Memory in both hex and decimal
    // Also output the final processor status
    task show_final_mem_and_status;
        
        begin
            
            updated_memory = memory.unified_memory;
            $fdisplay(out_fileno, "\nFinal memory state and exit status:\n");
            $fdisplay(out_fileno, "@@@ Unified Memory contents hex on left, decimal on right: ");
            $fdisplay(out_fileno, "Display starts at Base Addr: %x", O_BASE)
            $fdisplay(out_fileno, "@@@");
            showing_data = 0;

            for(int k = 0; k < ROW; k++) begin
                $fdisplay(out_fileno, "@@@ mem[%5d] = %x : %0d", k*8, updated_memory[O_IDX + k], updated_memory[O_IDX + k]);
            end

            $fdisplay(out_fileno, "@@@");

            $fdisplay(out_fileno, "@@@");
            $fclose(out_fileno);
        end
    endtask // task show_final_mem_and_status

    



    // OPTIONAL: Print our your data here
    // It will go to the $program.log file
    task print_custom_data;
        $display("%3d: YOUR DATA HERE", 
           clock_count-1
        );
    endtask


endmodule // module testbench