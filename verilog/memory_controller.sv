//This mem controller assumes full uninterupted access to the memline during processing

`include "include/sys_defs.svh"

module memory_controller #(
    // Addressing: base addresses for K, V, Q inputs and O outputs
    parameter ADDR K_BASE          = K_BASE,
    parameter ADDR V_BASE          = V_BASE,
    parameter ADDR Q_BASE          = Q_BASE,
    parameter ADDR O_BASE          = O_BASE,
    parameter int  VECTOR_BYTES    = (`MEM_BLOCKS_PER_VECTOR*8),
    parameter int  TILE_SIZE       = `NUM_PES, // # of vectors per tile
    parameter int  TILE_BYTES      = TILE_SIZE * VECTOR_BYTES,
    parameter int ELEMENTS_PER_MEMBLOCK = `MEM_BLOCK_SIZE_BITS / `INTEGER_WIDTH
)(
    input clock,
    input reset,

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
        PH_COMPUTE,
        PH_DONE
    } phase_e;

    phase_e phase, next_phase;

    // Memory modes for compute phase
    typedef enum logic [1:0] {
        CMP_IDLE,
        CMP_LOAD_Q,
        CMP_DRAIN_O
    } cmp_mode_e;

    cmp_mode_e mode, next_mode;


    // -----------------------------
    // Internal vector buffer/state
    // -----------------------------

    //KV Vector counters
    Q_VECTOR_T vector_buffer, next_vector_buffer;
    logic [$clog2(`MAX_SEQ_LENGTH)-1:0] vec_index, next_vec_index, vec_to_fetch, next_vec_to_fetch;     // which vector within the phase
    logic [$clog2(`MEM_BLOCKS_PER_VECTOR):0] blk_count, next_blk_count;             // 0..BLOCKS_PER_VEC
    logic [$clog2(`MEM_BLOCKS_PER_VECTOR)-1:0] blk_to_fetch, next_blk_to_fetch;     // 0..BLOCKS_PER_VEC-1
    logic [$clog2(`MAX_EMBEDDING_DIM)-1:0] write_index, next_write_index;
    logic have_full_vec; // flag: internal buffer contains a complete vector
    logic buffer_empty;
    logic next_last_blk_handled_for_current_phase, last_blk_handled_for_current_phase;

    //new compute phase QO counters
    logic [$clog2(`NUM_TILES):0] q_tiles_loaded_cnt, next_q_tiles_loaded_cnt;
    logic [$clog2(`NUM_TILES):0] o_tiles_drained_cnt, next_o_tiles_drained_cnt;  
    logic [$clog2(TILE_SIZE)-1:0] q_vec_index, next_q_vec_index, q_vec_to_fetch, next_q_vec_to_fetch;
    logic [$clog2(TILE_SIZE)-1:0] o_vec_to_drain, next_o_vec_to_drain;

    assign have_full_vec = (blk_count == `MEM_BLOCKS_PER_VECTOR);
    assign buffer_empty = (blk_count == 0);


    // -----------------------------
    // Output handshake/data signal computation
    // ----------------------------- 
    assign ctrl_K_vld = have_full_vec && (phase == PH_LOAD_K);
    assign ctrl_V_vld = have_full_vec && (phase == PH_LOAD_V);
    assign ctrl_Q_vld = have_full_vec && (phase == PH_COMPUTE) && (mode == CMP_LOAD_Q);
    //assign ctrl_O_rdy = buffer_empty && (phase == PH_COMPUTE) && (mode == CMP_DRAIN_O); //if we want to not lose a cycle for refilling the buffer we can check when there is only one blk left
    assign loaded_vector = vector_buffer;
    assign done = (phase == PH_DONE);


    // -----------------------------
    // Memory Helper Signals
    // -----------------------------
    ADDR mem_base_addr;
    MEM_TAG expected_tag_fifo [0:`NUM_MEM_TAGS];
    MEM_TAG next_expected_tag_fifo [0:`NUM_MEM_TAGS];
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

        next_mode = mode;
        next_q_tiles_loaded_cnt = q_tiles_loaded_cnt;
        next_q_vec_index = q_vec_index;
        next_q_vec_to_fetch = q_vec_to_fetch;
        next_o_tiles_drained_cnt = o_tiles_drained_cnt;
        next_o_vec_to_drain = o_vec_to_drain;

        ctrl_O_rdy = 0;

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
                    for(int i = 0; i < ELEMENTS_PER_MEMBLOCK; i++) begin
                        next_vector_buffer[write_index+i] = mem2proc_data.byte_level[i];
                    end
                    next_write_index = write_index + ELEMENTS_PER_MEMBLOCK; //Auto wraps
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
                        next_phase = PH_COMPUTE;
                        next_last_blk_handled_for_current_phase = 0;
                    end
                end

                // Receiving a mem blk
                if(!tags_empty && (mem2proc_data_tag == expected_tag_fifo[tag_head])) begin
                    //ASSERT NEXT BLK COUNT < MEM_BLOCKS_PER_VECTOR

                    //insert mem2proc_data into vector buffer
                    //THIS FOR LOOP IS HARD CODED BASED ON OUR ASSUMED INT WIDTH AND DK, MAKE IT GENERALIZABLE LATER
                    for(int i = 0; i < ELEMENTS_PER_MEMBLOCK; i++) begin
                        next_vector_buffer[write_index+i] = mem2proc_data.byte_level[i];
                    end
                    next_write_index = write_index + ELEMENTS_PER_MEMBLOCK; //Auto wraps
                    next_blk_count = next_blk_count + 1; //if currently full, this should be 1

                    next_tag_head = tag_head + 1;
                end
            end
            PH_COMPUTE: begin
                //------------------------------------------
                // PRIORITY 1: If idle, choose action:
                //------------------------------------------

                if (mode == CMP_IDLE) begin
                    if (O_sram_vld && o_tiles_drained_cnt < `NUM_TILES) begin
                        // Begin draining an O tile
                        ctrl_O_rdy = 1;
                        next_mode = CMP_DRAIN_O;
                        next_vector_buffer = drained_vector;
                        next_blk_count = `MEM_BLOCKS_PER_VECTOR;
                        next_write_index = 0;
                        next_blk_to_fetch = 0;
                    end
                    else if (Q_sram_rdy && q_tiles_loaded_cnt < `NUM_TILES) begin
                        // Begin loading a Q tile
                        next_mode = CMP_LOAD_Q;
                        next_blk_to_fetch = 0;
                        next_q_vec_to_fetch = 0;
                        next_write_index  = 0;
                        next_blk_count = 0;
                        next_last_blk_handled_for_current_phase = 0;
                    end
                    else begin
                        // Check for termination
                        if (o_tiles_drained_cnt == `NUM_TILES)
                            next_phase = PH_DONE;
                    end
                end

                //------------------------------------------
                // PRIORITY 2: Execute current mode
                //------------------------------------------

                case (mode)

                    //--------------------------------------
                    // MODE: DRAIN O TILE
                    //--------------------------------------
                    CMP_DRAIN_O: begin
                        proc2mem_command = MEM_STORE;

                        mem_base_addr = O_BASE
                                        + (o_tiles_drained_cnt * TILE_BYTES)   // global tile start
                                        + (o_vec_to_drain * VECTOR_BYTES);  // vector offset inside tile

                        proc2mem_addr = mem_base_addr + blk_to_fetch * `MEM_BLOCK_SIZE_BYTES;

                        // Store data from buffer
                        for (int i = 0; i < ELEMENTS_PER_MEMBLOCK; i++) begin
                            proc2mem_data.byte_level[i] = vector_buffer[write_index+i];
                        end

                        // Counter Updates
                        next_write_index = write_index + ELEMENTS_PER_MEMBLOCK;
                        next_blk_count = blk_count - 1;
                        next_blk_to_fetch = blk_to_fetch + 1;

                        // Last block of vector?
                        if (blk_count == 1) begin
                            next_o_vec_to_drain = o_vec_to_drain + 1;
                            if (O_sram_vld && o_vec_to_drain < TILE_SIZE-1) begin
                                // Latch next O vector in the current tile
                                ctrl_O_rdy = 1;
                                next_vector_buffer = drained_vector;
                                next_blk_count = `MEM_BLOCKS_PER_VECTOR;
                            end
                            if (o_vec_to_drain == TILE_SIZE-1) begin
                                // Finished draining the entire tile (all vectors)
                                next_o_tiles_drained_cnt = o_tiles_drained_cnt + 1;
                                next_mode = CMP_IDLE;
                            end
                        end
                    end

                    //--------------------------------------
                    // MODE: LOAD Q TILE
                    //--------------------------------------
                    CMP_LOAD_Q: begin
                        // Memory address computation
                        mem_base_addr = Q_BASE
                                        + (q_tiles_loaded_cnt * TILE_BYTES)   // global vector index
                                        + (q_vec_to_fetch * VECTOR_BYTES); // offset inside tile

                        proc2mem_addr = mem_base_addr + blk_to_fetch * `MEM_BLOCK_SIZE_BYTES;

                        if(!last_blk_handled_for_current_phase) begin
                            proc2mem_command = MEM_LOAD;
                            next_expected_tag_fifo[tag_tail] = mem2proc_transaction_tag;
                            next_tag_tail = tag_tail + 1;
                            next_blk_to_fetch = blk_to_fetch + 1;
                            if(blk_to_fetch == `MEM_BLOCKS_PER_VECTOR - 1) begin
                                next_q_vec_to_fetch = q_vec_to_fetch + 1; //auto wraps
                                if(q_vec_to_fetch == TILE_SIZE - 1) begin
                                    next_last_blk_handled_for_current_phase = 1;
                                end
                            end
                        end

                        // One full vector in the buffer?
                        if (have_full_vec && Q_sram_rdy) begin
                            next_blk_count = 0;
                            next_vector_buffer = '0;
                            next_write_index = 0;
                            next_q_vec_index = q_vec_index + 1;

                            if (q_vec_index == TILE_SIZE-1) begin
                                // Tile complete
                                next_last_blk_handled_for_current_phase = 0;
                                next_q_tiles_loaded_cnt  = q_tiles_loaded_cnt + 1; 
                                next_mode = CMP_IDLE;
                            end
                        end

                        // If a mem block returned this cycle:
                        if (!tags_empty && mem2proc_data_tag == expected_tag_fifo[tag_head]) begin
                            for (int i = 0; i < ELEMENTS_PER_MEMBLOCK; i++) begin
                                next_vector_buffer[write_index+i] = mem2proc_data.byte_level[i];
                            end
                            next_write_index = write_index + ELEMENTS_PER_MEMBLOCK;
                            next_blk_count   = next_blk_count + 1;
                            next_tag_head    = tag_head + 1;
                        end
                    end

                    default: ;//do nothing

                endcase

            end
            PH_DONE: ; //do nothing
            default: ; //do nothing
        endcase
    end

    //latch all sequential elements
    always_ff @(posedge clock) begin
        if(reset) begin
            phase             <= '0;
            vector_buffer     <= '0;
            vec_index         <= '0;
            blk_count         <= '0;
            blk_to_fetch      <= '0;
            vec_to_fetch      <= '0;
            write_index       <= '0;

            mode                <= CMP_IDLE;
            q_tiles_loaded_cnt  <= '0;
            q_vec_index         <= '0;
            q_vec_to_fetch      <= '0;
            o_tiles_drained_cnt <= '0;
            o_vec_to_drain      <= '0;

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

            mode                <= next_mode;
            q_tiles_loaded_cnt  <= next_q_tiles_loaded_cnt;
            q_vec_index         <= next_q_vec_index;
            q_vec_to_fetch      <= next_q_vec_to_fetch;
            o_tiles_drained_cnt <= next_o_tiles_drained_cnt;
            o_vec_to_drain      <= next_o_vec_to_drain;

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
            $display("CMP MODE = %0d", mode);
            $display("BLK_CNT = %0d", blk_count);
            $display("VEC_INDEX = %0d", vec_index);
            $display("BLK_FETCH = %0d", blk_to_fetch);
            $display("[KV] VEC_FETCH = %0d", vec_to_fetch);
            $display("[Q] VEC_FETCH = %0d", q_vec_to_fetch);
            $display("[Q] VEC_INDEX = %0d", q_vec_index);
            $display("[Q] TILES_LOADED = %0d", q_tiles_loaded_cnt);
            $display("[O] TILES_DRAINED = %0d", o_tiles_drained_cnt);
            $display("[O] VEC_TO_DRAIN = %0d", o_vec_to_drain);
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