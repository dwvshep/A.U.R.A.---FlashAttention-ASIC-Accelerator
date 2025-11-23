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
    // Memory Helper Signals
    // -----------------------------
    MEM_TAG expected_tag_fifo [`NUM_MEM_TAGS+1];
    MEM_TAG next_expected_tag_fifo [`NUM_MEM_TAGS+1];
    logic [$clog2(`NUM_MEM_TAGS+1)-1:0] tag_head, next_tag_head, tag_tail, next_tag_tail;
    logic tags_empty; //should never be full

    assign tags_empty = (tag_head == tag_tail);

    // -----------------------------
    // Vector assembly state
    // -----------------------------
    logic [$clog2(`MAX_SEQ_LENTH)-1:0]       vec_index, next_vec_index, vec_to_fetch, next_vec_to_fetch;     // which vector within the phase
    logic [$clog2(`MEM_BLOCKS_PER_VECTOR):0] blk_count, next_blk_count, blk_to_fetch, next_blk_to_fetch;     // 0..BLOCKS_PER_VEC
    logic                                    have_full_vec; // flag: internal buffer contains a complete vector

    // Internal vector buffer
    Q_VECTOR_T vector_buffer, next_vector_buffer;
    logic buffer_empty;

    assign have_full_vec = (blk_count == `MEM_BLOCKS_PER_VECTOR)
    assign buffer_empty = (blk_count == 0);

    // -----------------------------
    // Phase FSM
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

    always_comb begin
        next_phase = phase;

        unique case (phase)
            PH_RESET:   next_phase = PH_LOAD_K;

            PH_LOAD_K: begin
                // Advance to next phase after all K vectors produced to SRAM
                if ((vec_index == `MAX_SEQ_LENTH-1) && have_full_vec && K_sram_rdy) begin
                    next_phase = PH_LOAD_V;
                end
            end

            PH_LOAD_V: begin
                // Advance to next phase after all V vectors produced to SRAM
                if ((vec_index == `MAX_SEQ_LENTH-1) && have_full_vec && V_sram_rdy) begin
                    next_phase = PH_LOAD_Q;
                end
            end

            PH_LOAD_Q: begin
                // Advance to next phase after all Q vectors produced to SRAM
                if ((vec_index == `MAX_SEQ_LENTH-1) && have_full_vec && Q_sram_rdy) begin
                    next_phase = PH_DRAIN_O;
                end
            end

            PH_DRAIN_O: begin
                // Advance to next phase after all O vectors written back to memory
                if ((vec_index == `MAX_SEQ_LENTH-1) && buffer_empty && write_confirmed??) begin
                    next_phase = PH_DONE;
                end
            end

            default: next_phase = PH_RESET;
        endcase
    end

    assign have_full_vec = (blk_count == `MEM_BLOCKS_PER_VECTOR);

    assign ctrl_K_vld = have_full_vec && (phase == PH_LOAD_K);
    assign ctrl_V_vld = have_full_vec && (phase == PH_LOAD_V);
    assign ctrl_Q_vld = have_full_vec && (phase == PH_LOAD_Q);

    assign ctrl_O_rdy = buffer_empty && (phase == PH_DRAIN_O);

    assign loaded_vector = vector_buffer;

    assign done = (phase == PH_DONE);



    // -----------------------------
    // Memory signal computation
    // -----------------------------    

    // memory address computation
    ADDR mem_base_addr;
    always_comb begin
        // base addresses per phase
        unique case (phase)
            PH_LOAD_K:  mem_base_addr  = K_BASE + vec_to_fetch*VECTOR_BYTES;
            PH_LOAD_V:  mem_base_addr  = V_BASE + vec_to_fetch*VECTOR_BYTES;
            PH_LOAD_Q:  mem_base_addr  = Q_BASE + vec_to_fetch*VECTOR_BYTES;
            PH_DRAIN_O: mem_base_addr  = O_BASE + vec_to_fetch*VECTOR_BYTES;
            default:    mem_base_addr  = '0;
        endcase

        // full addresses per vector/block
        proc2mem_addr = mem_base_addr + blk_to_fetch*`MEM_BLOCK_SIZE_BYTES;
    end

    // memory data computation
    always_comb begin
        unique case (phase)
            PH_DRAIN_O: begin
                //THIS FOR LOOP IS HARD CODED BASED ON OUR ASSUMED INT WIDTH AND DK, MAKE IT GENERALIZABLE LATER
                for(int i = 0; i < 8; i++) begin
                    proc2mem_data.byte_level[i] = vector_buffer[write_index+i]
                end
            end
            default: proc2mem_data = '0;
        endcase
    end

    // memory command computation
    logic last_blk_fetched_for_load_phase;
    assign last_blk_fetched_for_load_phase = //??;
    always_comb begin
        next_blk_to_fetch = blk_to_fetch;
        next_vec_to_fetch = vec_to_fetch;
        unique case (phase)
            //THIS SCHEME SHOULD ASSUME WE CAN CONTINUOUSLY PREFETCH WITHOUT RISK OF STALLS
            //CURRENTLY CODED THE OTHER WAY BUT SHOULD FIX LATER (NO CHECKS FOR EMPTY/FULL BEFORE LOADING/STORING)
            //checks should be based on vec/blk to fetch state (last blk fetched or no?)

            PH_LOAD_K, PH_LOAD_V, PH_LOAD_Q: begin
                if(last_blk_fetched_for_load_phase) begin
                    proc2mem_command = MEM_NONE;
                end else begin
                    proc2mem_command = MEM_LOAD;
                    next_blk_to_fetch = blk_to_fetch + 1; //Auto wraps back to zero on every full vector loaded
                    if(blk_to_fetch == `MEM_BLOCKS_PER_VECTOR - 1) 
                end
            end
            PH_DRAIN_O: begin
                proc2mem_command = buffer_empty ? MEM_NONE ; MEM_STORE;
            end
            default: proc2mem_command = MEM_NONE;

            // PH_LOAD_K, PH_LOAD_V, PH_LOAD_Q: proc2mem_command = have_full_vec ? MEM_NONE : MEM_LOAD;
            // PH_DRAIN_O:                      proc2mem_command = buffer_empty ? MEM_NONE ; MEM_STORE;
            // default:                         proc2mem_command = MEM_NONE;
        endcase
    end


    // vector buffer assembly/draining and internal state updates
    always_comb begin
        //DEFINITELY NEED CHECKS BEFORE JUST INCREMENTING BLK TO FETCH
        // next_blk_to_fetch = blk_to_fetch;
        // next_vec_to_fetch = vec_to_fetch;

        next_expected_tag_fifo = expected_tag_fifo;
        next_tag_tail = tag_tail;
        //DEFINITELY NEED GUARDS HERE FOR END OF PHASE CHECKS
        // next_expected_tag_fifo[tag_tail] = mem2proc_transaction_tag;
        // next_tag_tail = tag_tail + 1;

        next_vector_buffer = vector_buffer;
        next_vec_index = vec_index;
        next_blk_count = blk_count;
        next_write_index = write_index;
        next_tag_head = tag_head;

        //pulling vector from buffer to sram or pulling from Osram to buffer
        unique case (phase)
            PH_LOAD_K: begin
                if(have_full_vec && K_sram_rdy) begin
                    next_blk_count = 0;
                    next_vector_buffer = '0;
                end
            end
            PH_LOAD_V: begin
                if(have_full_vec && V_sram_rdy) begin
                    next_blk_count = 0;
                    next_vector_buffer = '0;
                end
            end
            PH_LOAD_Q: begin
                if(have_full_vec && Q_sram_rdy) begin
                    next_blk_count = 0;
                    next_vector_buffer = '0;
                end
            end
            PH_DRAIN_O: begin
                //fill internal buffer with drained vector on handshake
                if(buffer_empty && O_sram_vld) begin
                    next_blk_count = `MEM_BLOCKS_PER_VECTOR;
                    next_vector_buffer = drained_vector;
                end
            end
            default: //do nothing
        endcase

        //receiving loaded mem block or writing drained mem block
        unique case (phase)
            PH_LOAD_K, PH_LOAD_V, PH_LOAD_Q: begin
                //receiving a mem blk
                if(!tags_empty && (mem2proc_data_tag == expected_tag_fifo[tag_head])) begin
                    //ASSERT NEXT BLK COUNT != MEM_BLOCKS_PER_VECTOR

                    //insert mem2proc_data into vector buffer
                    //THIS FOR LOOP IS HARD CODED BASED ON OUR ASSUMED INT WIDTH AND DK, MAKE IT GENERALIZABLE LATER
                    for(int i = 0; i < 8; i++) begin
                        next_vector_buffer[write_index+i] = mem2proc_data.byte_level[i];
                    end
                    next_write_index = write_index + 8; //Auto wraps
                    next_blk_count = next_blk_count + 1; //if currently full, this should be 1
                    
                    //THIS IS WRONG CURRENTLY - DOES NOT ALIGN WITH PHASE TRANSITION CHECKS
                    if(blk_count == `MEM_BLOCKS_PER_VECTOR - 1) begin //receiving the last blk in the vec
                        next_vec_index = vec_index + 1; //Auto wraps
                    end

                    next_tag_head = tag_head + 1;
                end
            end
            PH_DRAIN_O: begin
                //write to mem already handled, update blk index

            end
            default: //do nothing
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
            write_index       <= '0;
            expected_tag_fifo <= '0;
            tag_head          <= '0;
            tag_tail          <= '0;
        end else begin
            phase <= next_phase;
            vector_buffer <= next_vector_buffer;
            vec_index <= next_vec_index;
            blk_count <= next_blk_count;
            blk_to_fetch <= next_blk_to_fetch;
            write_index <= next_write_index;
            expected_tag_fifo <= next_expected_tag_fifo
            tag_head <= next_tag_head;
            tag_tail <= next_tag_tail;
        end
    end


endmodule