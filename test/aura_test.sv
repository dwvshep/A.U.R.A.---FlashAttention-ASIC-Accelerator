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


`define TB_MAX_CYCLES 200000


module testbench;
    // string inputs for loading memory and output files
    // run like: cd build && ./simv +MEMORY=../mem/<my_test>.mem +OUTPUT=../output/<my_test>
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

    
    MEM_COMMAND proc2mem_command;
    ADDR        proc2mem_addr;
    MEM_BLOCK   proc2mem_data;
    MEM_TAG     mem2proc_transaction_tag;
    MEM_BLOCK   mem2proc_data;
    MEM_TAG     mem2proc_data_tag;
    MEM_SIZE    proc2mem_size;
    
    logic done;

    //EXCEPTION_CODE error_status = NO_ERROR;

    
    // INST          [`N-1:0] insts;
    // ADDR          [`N-1:0] PCs;
    // COMMIT_PACKET [`N-1:0] committed_insts;

    // UPDATED MEMORY
    MEM_BLOCK updated_memory [`MEM_64BIT_LINES-1:0];

    localparam WIDTH = $bits(MEM_BLOCK);

    
    localparam integer K_IDX = K_BASE >> 3;  
    localparam integer V_IDX = V_BASE >> 3;
    localparam integer Q_IDX = Q_BASE >> 3;
    localparam integer O_IDX = O_BASE >> 3;
    localparam integer BUF_SZ = BUF_SIZE_BYTES >> 3;
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

        .done(done)
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

    initial begin
        //$dumpfile("../aura.vcd");
        //$dumpvars(0, testbench.AURA_dut);

        $display("QTYPES:");
        $display("EXPMUL_DIFF_IN_QT: Q(%0d,%0d)", `EXPMUL_DIFF_IN_I, `EXPMUL_DIFF_IN_F);
        $display("PRODUCT_QT: Q(%0d,%0d)", `PRODUCT_I, `PRODUCT_F);
        $display("INTERMEDIATE_PRODUCT_QT: Q(%0d,%0d)", `INTERMEDIATE_PRODUCT_I, `INTERMEDIATE_PRODUCT_F);
        $display("DOT_QT: Q(%0d,%0d)", `DOT_I, `DOT_F);

        $display("EXPMUL_DIFF_OUT_QT: Q(%0d,%0d)", `EXPMUL_DIFF_OUT_I, `EXPMUL_DIFF_OUT_F);
        $display("EXPMUL_LOG2E_IN_QT: Q(%0d,%0d)", `EXP_LOG2E_IN_I, `EXP_LOG2E_IN_F);
        $display("EXPMUL_LOG2E_OUT_QT: Q(%0d,%0d)", `EXP_LOG2E_OUT_I, `EXP_LOG2E_OUT_F);
        $display("EXPMUL_EXP_QT: Q(%0d,%0d)", `EXPMUL_EXP_I, `EXPMUL_EXP_F);

        $display("EXPMUL_SHIFT_STAGE_QT: Q(%0d,%0d)", `EXPMUL_SHIFT_STAGE_I, `EXPMUL_SHIFT_STAGE_F);
        $display("EXPMUL_VEC_QT: Q(%0d,%0d)", `EXPMUL_VEC_I, `EXPMUL_VEC_F);
        $display("DIV_INPUT_QT: Q(%0d,%0d)", `DIV_INPUT_I, `DIV_INPUT_F);

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
        $readmemh(Q_mem, memory.unified_memory, Q_IDX, Q_IDX + BUF_SZ - 1);
        $readmemh(K_mem, memory.unified_memory, K_IDX, K_IDX + BUF_SZ - 1);
        $readmemh(V_mem, memory.unified_memory, V_IDX, V_IDX + BUF_SZ - 1);

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
        end else begin
            #2; // wait a short time to avoid a clock edge

            clock_count = clock_count + 1;

            if (clock_count % 10000 == 0) begin
                $display("  %16t : %d cycles", $realtime, clock_count);
            end

            // stop the processor
            if (done || clock_count > `TB_MAX_CYCLES) begin

                $display("  %16t : Processing Finished", $realtime);

                @(negedge clock);
                show_final_mem_and_status();

                $display("\n---- Finished CPU Testbench ----\n");

                #100 $finish;
            end
        end // if(reset)
        `ifdef AURA_DEBUG
            `ifdef DOT_PRODUCT_DEBUG
                $write("[DOT_PROD_DBG]\n");
                $write("q: ");
                foreach (AURA_dut.gen_pe[1].pe_inst.dot_product_inst.q[i]) begin
                    $write("%02x ", AURA_dut.gen_pe[1].pe_inst.dot_product_inst.q[i]); //or %0d for decimal val
                end
                $write("\n");
                $write("k: ");
                foreach (AURA_dut.gen_pe[1].pe_inst.dot_product_inst.k[i]) begin
                    $write("%02x ", AURA_dut.gen_pe[1].pe_inst.dot_product_inst.k[i]); //or %0d for decimal val
                end
                $write("\n");
                $write("v: ");
                foreach (AURA_dut.gen_pe[1].pe_inst.dot_product_inst.v[i]) begin
                    $write("%02x ", AURA_dut.gen_pe[1].pe_inst.dot_product_inst.v[i]); //or %0d for decimal val
                end
                $write("\n");
                $display("valid_q: %0b", AURA_dut.gen_pe[1].pe_inst.dot_product_inst.valid_q);
                $display("valid_k: %0b", AURA_dut.gen_pe[1].pe_inst.dot_product_inst.valid_k);
                $display("valid_v: %0b", AURA_dut.gen_pe[1].pe_inst.dot_product_inst.valid_v);
                $display("row_counter: %0d", AURA_dut.gen_pe[1].pe_inst.dot_product_inst.row_counter);
                $display("vld_out: %0b", AURA_dut.gen_pe[1].pe_inst.dot_product_inst.vld_out);
                $display("s_out: %9b", AURA_dut.gen_pe[1].pe_inst.dot_product_inst.s_out);
            `endif
            `ifdef MAX_DEBUG
                $display("[MAX_DEBUG]");
                $display("valid_in: %0b", AURA_dut.gen_pe[1].pe_inst.max_inst.vld_in);
                $display("valid_out: %0d", AURA_dut.gen_pe[1].pe_inst.max_inst.vld_out);
                $display("ready_in: %0b", AURA_dut.gen_pe[1].pe_inst.max_inst.rdy_in);
                $display("ready_out: %0d", AURA_dut.gen_pe[1].pe_inst.max_inst.rdy_out);
                $display("v_in: %9b", AURA_dut.gen_pe[1].pe_inst.max_inst.v_in);
                $display("m_prev_in: %9b", AURA_dut.gen_pe[1].pe_inst.max_inst.m_prev_in);
                $display("s_in: %9b", AURA_dut.gen_pe[1].pe_inst.max_inst.s_in);
                $display("s_out: %9b", AURA_dut.gen_pe[1].pe_inst.max_inst.s_out);
            `endif
            `ifdef EXPMUL_DEBUG
                $display("[EXPMUL_DBG] valid_in: %0b, stage_1_valid: %0b, stage_1_ready: %0b, stage_2_valid: %0b, stage_2_ready: %0b, valid_out: %0b, ready_out: %0b",
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.vld_in,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_o_inst.stage_1_valid,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_o_inst.stage_1_ready,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_o_inst.stage_2_valid,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_o_inst.stage_2_ready,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.vld_out,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.rdy_out
                );
                $display("[EXPMUL_STAGE_DBG] l_hat_o: %5b, x_diff_o: %10b, l_hat_v: %5b, x_diff_v: %10b, a_in_o: %9b, b_in_o: %9b, a_in_v: %9b, b_in_v: %9b",
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_o_inst.l_hat,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_o_inst.x_diff,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_v_inst.l_hat,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_v_inst.x_diff,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_o_inst.a_in,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_o_inst.b_in,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_v_inst.a_in,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_v_inst.b_in
                );
                $display("[EXPMUL_STAGES_O_DBG] stage_1: %02x, stage_2: %02x, stage_3: %03x, stage_4: %04x, stage_5: %05x",
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_o_inst.shift_stage_1_1,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_o_inst.shift_stage_2_1,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_o_inst.shift_stage_3_1, 
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_o_inst.shift_stage_4_1,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_o_inst.shift_stage_5_1
                );
                $display("[EXPMUL_STAGES_V_DBG] stage_1: %02x, stage_2: %02x, stage_3: %03x, stage_4: %04x, stage_5: %05x",
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_v_inst.shift_stage_1_1,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_v_inst.shift_stage_2_1,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_v_inst.shift_stage_3_1, 
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_v_inst.shift_stage_4_1,
                    AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_v_inst.shift_stage_5_1
                );
                $display("expmul_o_in: ");
                foreach (AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_o_inst.v_stage_2[i]) begin
                    $write("%f ", AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_o_inst.v_in[i] / real'(1 << `EXPMUL_VEC_F)); //or %0d for decimal val
                end
                $write("\n");
                $display("expmul_o_out: ");
                foreach (AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_o_inst.v_out[i]) begin
                    $write("%f ", AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_o_inst.v_out[i] / real'(1 << `EXPMUL_VEC_F)); //or %0d for decimal val
                end
                $write("\n");
                $display("expmul_v_in: ");
                foreach (AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_v_inst.v_in[i]) begin
                    $write("%f ", AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_v_inst.v_in[i] / real'(1 << `EXPMUL_VEC_F)); //or %0d for decimal val
                end
                $write("\n");
                $display("expmul_v_out: ");
                foreach (AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_v_inst.v_out[i]) begin
                    $write("%f ", AURA_dut.gen_pe[1].pe_inst.expmul_inst.expmul_v_inst.v_out[i] / real'(1 << `EXPMUL_VEC_F)); //or %0d for decimal val
                end
                $write("\n");
                $display("KV_CNTR: %0d", AURA_dut.gen_pe[1].pe_inst.expmul_inst.kv_counter_1);
            `endif
            `ifdef VEC_DEBUG
                $write("[VEC_DIV_DBG] vec_in: ");
                foreach (AURA_dut.gen_pe[1].pe_inst.vector_division_inst.vec_in[i]) begin
                    $write("%f ", AURA_dut.gen_pe[1].pe_inst.vector_division_inst.vec_in[i] / real'(1 << `EXPMUL_VEC_F)); //or %0d for decimal val
                end
                $write("\n");
            `endif
            `ifdef INT_DIV_DEBUG
                $display("[INT_DIV_DBG] valid_in: %0b, valid_reg: %0b, valid_out: %0b, ready_in: %0b, ready_out: %0b", 
                    AURA_dut.gen_pe[1].pe_inst.vector_division_inst.gen_div[1].div_inst.vld_in,
                    AURA_dut.gen_pe[1].pe_inst.vector_division_inst.gen_div[1].div_inst.valid_reg,
                    AURA_dut.gen_pe[1].pe_inst.vector_division_inst.gen_div[1].div_inst.vld_out,
                    AURA_dut.gen_pe[1].pe_inst.vector_division_inst.gen_div[1].div_inst.rdy_in,
                    AURA_dut.gen_pe[1].pe_inst.vector_division_inst.gen_div[1].div_inst.rdy_out
                );
                $display("numerator_in: %f", AURA_dut.gen_pe[1].pe_inst.vector_division_inst.gen_div[1].div_inst.numerator_in / real'(1 << `DIV_INPUT_F));
                $display("denominator_in: %f", AURA_dut.gen_pe[1].pe_inst.vector_division_inst.gen_div[1].div_inst.denominator_in / real'(1 << `DIV_INPUT_F));
                //$display("abs_num: %f", AURA_dut.gen_pe[1].pe_inst.vector_division_inst.gen_div[1].div_inst.abs_num);
                //$display("abs_den: %f", AURA_dut.gen_pe[1].pe_inst.vector_division_inst.gen_div[1].div_inst.abs_den);
            `endif 
        `endif
    end


    // Show contents of Unified Memory in both hex and decimal
    // Also output the final processor status
    task show_final_mem_and_status;
        
        begin
            
            updated_memory = memory.unified_memory;
            $fdisplay(out_fileno, "\nFinal memory state and exit status:\n");
            $fdisplay(out_fileno, "@@@ Unified Memory contents hex on left, decimal on right: ");
            $fdisplay(out_fileno, "Display starts at Base Addr: %x", O_BASE);
            $fdisplay(out_fileno, "@@@");

            for(int k = 0; k < ROW * `INTEGER_WIDTH; k++) begin
                $fdisplay(out_fileno, "@@@ mem[%5d] = %x : %0d", k*`INTEGER_WIDTH, updated_memory[O_IDX + k], updated_memory[O_IDX + k]);
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