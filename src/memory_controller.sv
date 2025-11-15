module memory_controller #(
    // Addressing: base addresses for K, V, Q inputs and O outputs
    parameter ADDR K_BASE          = 'h0000_1000,
    parameter ADDR V_BASE          = 'h0000_2000,
    parameter ADDR Q_BASE          = 'h0000_3000,
    parameter ADDR O_BASE          = 'h0000_4000,
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
    input  O_VECTOR_T  drained_O_vector,
    output Q_VECTOR_T  loaded_Q_vector,
    output K_VECTOR_T  loaded_K_vector,
    output V_VECTOR_T  loaded_V_vector,

    output logic       done
);


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
                if ((vec_index == `MAX_SEQ_LEN-1) && have_full_vec && ctrl_K_vld && K_sram_rdy) begin
                    next_phase = PH_LOAD_V;
                end
            end

            PH_LOAD_V: begin
                // Advance to next phase after all V vectors produced to SRAM
                if ((vec_index == `MAX_SEQ_LEN-1) && have_full_vec && ctrl_V_vld && V_sram_rdy) begin
                    next_phase = PH_LOAD_Q;
                end
            end

            PH_LOAD_Q: begin
                // Advance to next phase after all Q vectors produced to SRAM
                if ((vec_index == `MAX_SEQ_LEN-1) && have_full_vec && ctrl_Q_vld && Q_sram_rdy) begin
                    next_phase = PH_DRAIN_O;
                end
            end

            PH_DRAIN_O: begin
                // Advance to next phase after all O vectors written back to memory
                if ((vec_index == `MAX_SEQ_LEN-1) && have_full_vec && write_confirmed??) begin
                    next_phase = PH_DONE;
                end
            end

            default: next_phase = PH_RESET;
        endcase
    end

    assign done = (phase == PH_DONE);

    // -----------------------------
    // Vector assembly state
    // -----------------------------
    logic [$clog2(`MAX_SEQ_LEN)-1:0]         vec_index;     // which vector within the phase
    logic [$clog2(`MEM_BLOCKS_PER_VECTOR):0] blk_count;     // 0..BLOCKS_PER_VEC
    logic                                    have_full_vec; // flag: internal buffer contains a complete vector

    // Internal vector buffer
    Q_VECTOR_T vector_buffer;


    // memory address computation
    ADDR mem_base_addr;
    always_comb begin
        // base addresses per phase
        unique case (phase)
            PH_LOAD_K:  mem_base_addr  = K_BASE + vec_index*VECTOR_BYTES;
            PH_LOAD_V:  mem_base_addr  = V_BASE + vec_index*VECTOR_BYTES;
            PH_LOAD_Q:  mem_base_addr  = Q_BASE + vec_index*VECTOR_BYTES;
            PH_DRAIN_O: mem_base_addr  = O_BASE + vec_index*VECTOR_BYTES;
            default:    mem_base_addr  = '0;
        endcase

        // full addresses per vector/block
        proc2mem_addr = mem_base_addr + blk_count*`MEM_BLOCK_SIZE_BYTES;
    end

    // memory data computation
    always_comb begin
        unique case (phase)
            PH_DRAIN_O: proc2mem_data = vector_buffer[write_index];
            default:    proc2mem_data = '0;
        endcase
    end

    // memory command computation
    always_comb begin
        unique case (phase)
            PH_LOAD_K:  proc2mem_command  = MEM_LOAD;
            PH_LOAD_V:  proc2mem_command  = MEM_LOAD;
            PH_LOAD_Q:  proc2mem_command  = MEM_LOAD;
            PH_DRAIN_O: proc2mem_command  = MEM_STORE;
            default:    proc2mem_command  = MEM_NONE;
        endcase
    end




endmodule