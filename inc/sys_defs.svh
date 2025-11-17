/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  sys_defs.svh                                        //
//                                                                     //
//  Description :  This file defines macros and data structures used   //
//                 throughout the processor.                           //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`ifndef __SYS_DEFS_SVH__
`define __SYS_DEFS_SVH__


// all files should `include "sys_defs.svh" to at least define the timescale
`timescale 1ns/100ps


///////////////////////////////////
// ---- Starting Parameters ---- //
///////////////////////////////////

//Comment out when synthesizing
//`define DEBUG 

`define INTEGER_WIDTH 8           // Width of integer data types (4, 8, 16, 32)

`define MAX_EMBEDDING_DIM 64      // Maximum embedding dimension supported

`define MAX_SEQ_LENGTH 512        // Maximum sequence length supported

`define MEM_BLOCK_SIZE_BITS 64    // Size of memory block in bits

`define MEM_BLOCK_SIZE_BYTES (`MEM_BLOCK_SIZE_BITS / 8) // Size of memory block in bytes

`define MAX_NUM_PE ((`MAX_SEQ_LENGTH * `MEM_BLOCK_SIZE_BYTES) / (`MAX_EMBEDDING_DIM * `INTEGER_WIDTH/8)) // Maximum and optimal number of processing elements supported

`define NUM_PE `MAX_NUM_PE        // Number of parallel processing elements

`define SRAM_SIZE_KB  128         // Size of SRAM in KB

`define K_SRAM_BYTES (`MAX_EMBEDDING_DIM * `INTEGER_WIDTH/8) // Bytes needed to store one K row vector in SRAM

`define V_SRAM_BYTES (`MAX_EMBEDDING_DIM * `INTEGER_WIDTH/8) // Bytes needed to store one V row vector in SRAM

`define Q_SRAM_BYTES (`SRAM_SIZE_KB * 1024 - `K_SRAM_BYTES - `V_SRAM_BYTES) // Bytes available to store Q vectors in SRAM

`define Q_SRAM_ROW_BYTES (`MAX_EMBEDDING_DIM * `INTEGER_WIDTH/8) // Bytes needed to store one Q row vector in SRAM

`define Q_SRAM_DEPTH (`Q_SRAM_BYTES/`Q_SRAM_ROW_BYTES) // Number of full length Q row vectors that can be stored in SRAM



///////////////////////////////////
// ---- Bit Width Parameters ---- //
///////////////////////////////////

`define INPUT_SIZE 8

`define EXPMUL_OUTPUT_SIZE 30

`define DOT_PRODUCT_SIZE 22



`define 



typedef signed logic [`INTEGER_WIDTH-1:0] INT_T;

typedef INT_T [`MAX_EMBEDDING_DIM] Q_VECTOR_T;

typedef INT_T [`MAX_EMBEDDING_DIM] K_VECTOR_T;

typedef INT_T [`MAX_EMBEDDING_DIM] V_VECTOR_T;

typedef INT_T [`MAX_EMBEDDING_DIM] O_VECTOR_T;

typedef  [`MAX_EMBEDDING_DIM+1][`DOT_PRODUCT_SIZE-1:0] STAR_VECTOR_T_IN; //Input to expmul

typedef  [`MAX_EMBEDDING_DIM+1][`EXPMUL_OUTPUT_SIZE-1:0] STAR_VECTOR_T_OUT; //Append 1 to the vector to store l in the output, output from expmul




//////////////////////////////////
// ---- Memory Definitions ---- //
//////////////////////////////////

typedef union packed {
    logic [31:0] addr;
    //?? other fields as needed
} ADDR;

`define MEM_LATENCY_IN_CYCLES (100.0/`CLOCK_PERIOD+0.49999)
// the 0.49999 is to force ceiling(100/period). The default behavior for
// float to integer conversion is rounding to nearest

// memory tags represent a unique id for outstanding mem transactions
// 0 is a sentinel value and is not a valid tag
`define NUM_MEM_TAGS 15
typedef logic [3:0] MEM_TAG;

`define MEM_SIZE_IN_BYTES (64*1024)

`define MEM_64BIT_LINES   (`MEM_SIZE_IN_BYTES/8)

`define MEM_BLOCKS_PER_VECTOR ((`MAX_EMBEDDING_DIM*`INTEGER_WIDTH/8)/`MEM_BLOCK_SIZE_BYTES)

// A memory or cache block
typedef union packed {
    logic [7:0][7:0]  byte_level;
    logic [3:0][15:0] half_level;
    logic [1:0][31:0] word_level;
    logic      [63:0] dbbl_level;
} MEM_BLOCK;

typedef enum logic [1:0] {
    BYTE   = 2'h0,
    HALF   = 2'h1,
    WORD   = 2'h2,
    DOUBLE = 2'h3
} MEM_SIZE;

// Memory bus commands
typedef enum logic [1:0] {
    MEM_NONE   = 2'h0,
    MEM_LOAD   = 2'h1,
    MEM_STORE  = 2'h2
} MEM_COMMAND;




