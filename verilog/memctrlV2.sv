//This mem controller assumes full uninterupted access to the memline during processing

`include "include/sys_defs.svh"

module memory_controller #(
    // Addressing: base addresses for K, V, Q inputs and O outputs
    parameter ADDR K_BASE          = K_BASE,
    parameter ADDR V_BASE          = V_BASE,
    parameter ADDR Q_BASE          = Q_BASE,
    parameter ADDR O_BASE          = O_BASE,
    parameter int  VECTOR_BYTES    = (`MEM_BLOCKS_PER_VECTOR*8)
)(
    input clk,
    input rst,

    // Memory interface signals
    input  MEM_TAG     mem2proc_transaction_tag, // Memory tag for current transaction
    input  MEM_BLOCK   mem2proc_data,            // Data coming back from memory
    input  MEM_TAG     mem2proc_data_tag,        // Tag for which transaction data is for
    output MEM_COMMAND proc2mem_command, // Command sent to memory
    output ADDR        proc2mem_addr,    // Address sent to memory
    output MEM_BLOCK   proc2mem_data,     // Data sent to memory

    // Handshake signals with Q K V and O SRAMs
    input  logic Q_sram_rdy,
    input  logic K_sram_rdy,
    input  logic V_sram_rdy,
    input  logic O_sram_vld,
    output logic ctrl_O_rdy,
    output logic ctrl_Q_vld,
    output logic ctrl_K_vld,
    output logic ctrl_V_vld,

    // Data signals to/from Q K V and O SRAMs
    input  O_VECTOR_T  drained_vector,
    output Q_VECTOR_T  loaded_vector,

    output logic       done
);

    // -----------------------------
    // Phases
    // -----------------------------
    typedef enum logic [2:0] {
        PH_RESET,
        PH_LOAD_K,
        PH_LOAD_V,
        PH_LOAD_Q,
        PH_DRAIN_O,
        PH_DONE
    } phase_e;

    phase_e phase, next_phase;


    // -----------------------------
    // Internal vector buffer/state
    // -----------------------------
    Q_VECTOR_T vector_buffer, next_vector_buffer;
    logic [$clog2(`MAX_SEQ_LENGTH)-1:0]      vec_index, next_vec_index, vec_to_fetch, next_vec_to_fetch;     // which vector within the phase
    logic [$clog2(`MEM_BLOCKS_PER_VECTOR):0] blk_count, next_blk_count;             // 0..BLOCKS_PER_VEC
    logic [$clog2(`MEM_BLOCKS_PER_VECTOR)-1:0] blk_to_fetch, next_blk_to_fetch;     // 0..BLOCKS_PER_VEC-1
    logic [$clog2(VECTOR_BYTES)-1:0] write_index, next_write_index;
    logic have_full_vec; // flag: internal buffer contains a complete vector
    logic buffer_empty;
    logic next_last_blk_handled_for_current_phase, last_blk_handled_for_current_phase;

    assign have_full_vec = (blk_count == `MEM_BLOCKS_PER_VECTOR);
    assign buffer_empty = (blk_count == 0);


    // -----------------------------
    // Output handshake/data signal computation
    // ----------------------------- 
    assign ctrl_K_vld = have_full_vec && (phase == PH_LOAD_K);
    assign ctrl_V_vld = have_full_vec && (phase == PH_LOAD_V);
    assign ctrl_Q_vld = have_full_vec && (phase == PH_LOAD_Q);
    assign ctrl_O_rdy = buffer_empty && (phase == PH_DRAIN_O); //if we want to not lose a cycle for refilling the buffer we can check when there is only one blk left
    assign loaded_vector = vector_buffer;
    assign done = (phase == PH_DONE);


    // -----------------------------
    // Memory Helper Signals
    // -----------------------------
    ADDR mem_base_addr;
    MEM_TAG expected_tag_fifo [`NUM_MEM_TAGS+1];
    MEM_TAG next_expected_tag_fifo [`NUM_MEM_TAGS+1];
    logic [$clog2(`NUM_MEM_TAGS+1)-1:0] tag_head, next_tag_head, tag_tail, next_tag_tail;
    logic tags_empty; //should never be full since we have an extra slot

    assign tags_empty = (tag_head == tag_tail);


    always_comb begin
        mem_base_addr = '0;
        proc2mem_addr = '0;
        proc2mem_data = '0;
        proc2mem_command = MEM_NONE;
        next_phase = phase;
        next_vector_buffer = vector_buffer;
        next_vec_index = vec_index;
        next_blk_count = blk_count;
        next_write_index = write_index;
        next_tag_head = tag_head;
        next_last_blk_handled_for_current_phase = last_blk_handled_for_current_phase;
        next_blk_to_fetch = blk_to_fetch;
        next_vec_to_fetch = vec_to_fetch;
        next_expected_tag_fifo = expected_tag_fifo;
        next_tag_tail = tag_tail;

        unique case (phase)
            PH_RESET: begin
                next_phase = PH_LOAD_K;
            end
            PH_LOAD_K: begin
                // Memory address computation
                mem_base_addr  = K_BASE + vec_to_fetch*VECTOR_BYTES;
                proc2mem_addr = mem_base_addr + blk_to_fetch*`MEM_BLOCK_SIZE_BYTES;

                // Memory command computation and tag/blk/vec updates
                if(!last_blk_handled_for_current_phase) begin
                    proc2mem_command = MEM_LOAD;
                    next_expected_tag_fifo[tag_tail] = mem2proc_transaction_tag;
                    next_tag_tail = tag_tail + 1;
                    next_blk_to_fetch = blk_to_fetch + 1; //Auto wraps back to zero on every full vector loaded
                    if(blk_to_fetch == `MEM_BLOCKS_PER_VECTOR - 1) begin
                        next_vec_to_fetch = vec_to_fetch + 1; //auto wraps
                        if(vec_to_fetch == `MAX_SEQ_LENGTH - 1) begin
                            next_last_blk_handled_for_current_phase = 1;
                        end
                    end
                end

                // Reset internal buffer on handshake and advance to next phase after all K vectors produced to SRAM
                if(have_full_vec && K_sram_rdy) begin
                    next_blk_count = 0;
                    next_vector_buffer = '0;
                    next_vec_index = vec_index + 1; //Auto wraps on phase transition
                    if(vec_index == `MAX_SEQ_LENGTH-1) begin
                        next_phase = PH_LOAD_V;
                        next_last_blk_handled_for_current_phase = 0;
                    end
                end

                // Receiving a mem blk
                if(!tags_empty && (mem2proc_data_tag == expected_tag_fifo[tag_head])) begin
                    //ASSERT NEXT BLK COUNT < MEM_BLOCKS_PER_VECTOR

                    //insert mem2proc_data into vector buffer
                    //THIS FOR LOOP IS HARD CODED BASED ON OUR ASSUMED INT WIDTH AND DK, MAKE IT GENERALIZABLE LATER
                    for(int i = 0; i < 8; i++) begin
                        next_vector_buffer[write_index+i] = mem2proc_data.byte_level[i];
                    end
                    next_write_index = write_index + 8; //Auto wraps
                    next_blk_count = next_blk_count + 1; //if currently full, this should be 1

                    next_tag_head = tag_head + 1;
                end
            end
            PH_LOAD_V: begin
                // Memory address computation
                mem_base_addr  = V_BASE + vec_to_fetch*VECTOR_BYTES;
                proc2mem_addr = mem_base_addr + blk_to_fetch*`MEM_BLOCK_SIZE_BYTES;

                // Memory command computation and tag/blk updates
                if(!last_blk_handled_for_current_phase) begin
                    proc2mem_command = MEM_LOAD;
                    next_expected_tag_fifo[tag_tail] = mem2proc_transaction_tag;
                    next_tag_tail = tag_tail + 1;
                    next_blk_to_fetch = blk_to_fetch + 1; //Auto wraps back to zero on every full vector loaded
                    if(blk_to_fetch == `MEM_BLOCKS_PER_VECTOR - 1) begin
                        next_vec_to_fetch = vec_to_fetch + 1; //auto wraps
                        if(vec_to_fetch == `MAX_SEQ_LENGTH - 1) begin
                            next_last_blk_handled_for_current_phase = 1;
                        end
                    end
                end

                // Reset internal buffer on handshake and advance to next phase after all V vectors produced to SRAM
                if(have_full_vec && V_sram_rdy) begin
                    next_blk_count = 0;
                    next_vector_buffer = '0;
                    next_vec_index = vec_index + 1; //Auto wraps on phase transition
                    if(vec_index == `MAX_SEQ_LENGTH-1) begin
                        next_phase = PH_LOAD_Q;
                        next_last_blk_handled_for_current_phase = 0;
                    end
                end

                // Receiving a mem blk
                if(!tags_empty && (mem2proc_data_tag == expected_tag_fifo[tag_head])) begin
                    //ASSERT NEXT BLK COUNT < MEM_BLOCKS_PER_VECTOR

                    //insert mem2proc_data into vector buffer
                    //THIS FOR LOOP IS HARD CODED BASED ON OUR ASSUMED INT WIDTH AND DK, MAKE IT GENERALIZABLE LATER
                    for(int i = 0; i < 8; i++) begin
                        next_vector_buffer[write_index+i] = mem2proc_data.byte_level[i];
                    end
                    next_write_index = write_index + 8; //Auto wraps
                    next_blk_count = next_blk_count + 1; //if currently full, this should be 1

                    next_tag_head = tag_head + 1;
                end
            end
            PH_LOAD_Q: begin
                // Memory address computation
                mem_base_addr  = Q_BASE + vec_to_fetch*VECTOR_BYTES;
                proc2mem_addr = mem_base_addr + blk_to_fetch*`MEM_BLOCK_SIZE_BYTES;

                // Memory command computation and tag/blk/vec updates
                if(!last_blk_handled_for_current_phase) begin
                    proc2mem_command = MEM_LOAD;
                    next_expected_tag_fifo[tag_tail] = mem2proc_transaction_tag;
                    next_tag_tail = tag_tail + 1;
                    next_blk_to_fetch = blk_to_fetch + 1; //Auto wraps back to zero on every full vector loaded
                    if(blk_to_fetch == `MEM_BLOCKS_PER_VECTOR - 1) begin
                        next_vec_to_fetch = vec_to_fetch + 1; //auto wraps
                        if(vec_to_fetch == `MAX_SEQ_LENGTH - 1) begin
                            next_last_blk_handled_for_current_phase = 1;
                        end
                    end
                end

                //reset internal buffer on handshake and advance to next phase after all Q vectors produced to SRAM
                if(have_full_vec && Q_sram_rdy) begin
                    next_blk_count = 0;
                    next_vector_buffer = '0;
                    next_vec_index = vec_index + 1; //Auto wraps on phase transition
                    if(vec_index == `MAX_SEQ_LENGTH-1) begin
                        next_phase = PH_DRAIN_O;
                        next_last_blk_handled_for_current_phase = 0;
                    end
                end

                //receiving a mem blk
                if(!tags_empty && (mem2proc_data_tag == expected_tag_fifo[tag_head])) begin
                    //ASSERT NEXT BLK COUNT < MEM_BLOCKS_PER_VECTOR

                    //insert mem2proc_data into vector buffer
                    //THIS FOR LOOP IS HARD CODED BASED ON OUR ASSUMED INT WIDTH AND DK, MAKE IT GENERALIZABLE LATER
                    for(int i = 0; i < 8; i++) begin
                        next_vector_buffer[write_index+i] = mem2proc_data.byte_level[i];
                    end
                    next_write_index = write_index + 8; //Auto wraps
                    next_blk_count = next_blk_count + 1; //if currently full, this should be 1

                    next_tag_head = tag_head + 1;
                end
            end
            PH_DRAIN_O: begin
                // Memory address computation
                mem_base_addr  = O_BASE + vec_to_fetch*VECTOR_BYTES;
                proc2mem_addr = mem_base_addr + blk_to_fetch*`MEM_BLOCK_SIZE_BYTES;
            
                // Memory write data computation
                for(int i = 0; i < 8; i++) begin
                    proc2mem_data.byte_level[i] = vector_buffer[write_index+i];
                end

                // Memory command computation and blk/vec updates
                if(buffer_empty) begin
                    next_blk_to_fetch = '0;
                end else begin
                    proc2mem_command = MEM_STORE;
                    if(blk_to_fetch == `MEM_BLOCKS_PER_VECTOR - 1) begin
                        next_blk_to_fetch = '0;
                        next_vec_to_fetch = vec_to_fetch + 1; //auto wraps
                    end else begin
                        next_blk_to_fetch = blk_to_fetch + 1;
                    end
                    next_write_index = write_index + 8; //Auto wraps
                    next_blk_count = blk_count - 1; //Auto wraps back to 512
                    if(blk_count == 1) begin
                        next_vec_index = vec_index + 1;
                    end
                end

                //fill internal buffer with drained vector on handshake
                if(buffer_empty && O_sram_vld) begin
                    next_write_index = 0; //Should be unnecessary
                    next_blk_count = `MEM_BLOCKS_PER_VECTOR;
                    next_vector_buffer = drained_vector;
                end

                // Advance to next phase after all O vectors written back to memory
                if ((vec_index == `MAX_SEQ_LENGTH-1) && (blk_count == 1)) begin
                    //When blk count is 1 we guarantee the buffer will drain at the end of that cycle
                    next_phase = PH_DONE;
                end
            end
            PH_DONE: ; //do nothing
            default: ; //do nothing
        endcase
    end

    //latch all sequential elements
    always_ff @(posedge clk) begin
        if(rst) begin
            phase             <= '0;
            vector_buffer     <= '0;
            vec_index         <= '0;
            blk_count         <= '0;
            blk_to_fetch      <= '0;
            vec_to_fetch      <= '0;
            write_index       <= '0;
            
            //latch tag fifo one by one since it doesnt like packed dims
            for (int i = 0; i < `NUM_MEM_TAGS+1; i++) begin
                expected_tag_fifo[i] <= '0;
            end

            tag_head          <= '0;
            tag_tail          <= '0;
            last_blk_handled_for_current_phase <= '0;
        end else begin
            phase             <= next_phase;
            vector_buffer     <= next_vector_buffer;
            vec_index         <= next_vec_index;
            blk_count         <= next_blk_count;
            blk_to_fetch      <= next_blk_to_fetch;
            vec_to_fetch      <= next_vec_to_fetch;
            write_index       <= next_write_index;

            //latch tag fifo one by one since it doesnt like packed dims
            for (int i = 0; i < `NUM_MEM_TAGS+1; i++) begin
                expected_tag_fifo[i] <= next_expected_tag_fifo[i];
            end

            tag_head          <= next_tag_head;
            tag_tail          <= next_tag_tail;
            last_blk_handled_for_current_phase <= next_last_blk_handled_for_current_phase;
        end
        `ifdef MEM_CTRL_DEBUG
            $display("PHASE: %s", phase.name());
            $display("BLK_CNT = %0d", blk_count);
            $display("VEC_INDEX = %0d", vec_index);
            $display("BLK_FETCH = %0d", blk_to_fetch);
            $display("VEC_FETCH = %0d", vec_to_fetch);
            $display("NEXT_TAG = %0d", expected_tag_fifo[tag_head]);
            $display("KSRAM_RDY = %0d", K_sram_rdy);
            $display("VSRAM_RDY = %0d", V_sram_rdy);
            $display("QSRAM_RDY = %0d", Q_sram_rdy);
            $display("OSRAM_VLD = %0d", O_sram_vld);
            $display("LAST_BLK_FLAG = %0d", last_blk_handled_for_current_phase);
            $write("MEM_CTRL_VEC_BUF: ");
            foreach (vector_buffer[i]) begin
                $write("%02x ", vector_buffer[i]); //or %0d for decimal val
            end
            $write("\n");
        `endif
    end

endmodule