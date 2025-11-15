module memory_controller(
    input clk,
    input rst,

    // Memory interface signals
    input  MEM_TAG     mem2proc_transaction_tag, // Memory tag for current transaction
    input  MEM_BLOCK   mem2proc_data,            // Data coming back from memory
    input  MEM_TAG     mem2proc_data_tag,        // Tag for which transaction data is for
    output MEM_COMMAND proc2mem_command, // Command sent to memory
    output ADDR        proc2mem_addr,    // Address sent to memory
    output MEM_BLOCK   proc2mem_data,     // Data sent to memory

    // Handshake signals with QSRAM and OSRAM
    input  logic Q_sram_rdy,
    input  logic O_sram_vld,
    output logic ctrl_rdy,
    output logic ctrl_vld,

    // Data signals to/from QSRAM/OSRAM
    input  O_VECTOR_T  drained_O_vector,
    output Q_VECTOR_T  loaded_Q_vector
);


endmodule