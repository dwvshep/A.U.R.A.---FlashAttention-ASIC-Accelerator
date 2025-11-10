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

`define INTEGER_WIDTH 16          // Width of integer data types (4, 8, 16, 32)

`define SRAM_SIZE_KB  128          // Size of SRAM in KB

`define MAX_EMBEDDING_DIM 64     // Maximum embedding dimension supported

`define K_SRAM_BYTES (`MAX_EMBEDDING_DIM * `INTEGER_WIDTH/8) // Bytes needed to store one K row vector in SRAM

`define V_SRAM_BYTES (`MAX_EMBEDDING_DIM * `INTEGER_WIDTH/8) // Bytes needed to store one V row vector in SRAM

//We can support arbitrary sequennce lengths
//`define MAX_SEQ_LENGTH 1024        // Maximum sequence length supported

`define Q_SRAM_BYTES (`SRAM_SIZE_KB * 1024 - `K_SRAM_BYTES - `V_SRAM_BYTES) // Bytes available to store Q vectors in SRAM

`define Q_SRAM_ROW_BYTES (`MAX_EMBEDDING_DIM * `INTEGER_WIDTH/8) // Bytes needed to store one Q row vector in SRAM

`define Q_SRAM_DEPTH (`Q_SRAM_BYTES/`Q_SRAM_ROW_BYTES) // Number of full length Q row vectors that can be stored in SRAM



typedef signed logic [`INTEGER_WIDTH-1:0] INT_T;

typedef INT_T [`MAX_EMBEDDING_DIM-1:0] Q_VECTOR_T;

typedef INT_T [`MAX_EMBEDDING_DIM-1:0] K_VECTOR_T;

typedef INT_T [`MAX_EMBEDDING_DIM-1:0] V_VECTOR_T;

typedef INT_T [`MAX_EMBEDDING_DIM-1:0] O_VECTOR_T;

typedef INT_T [`MAX_EMBEDDING_DIM:0] STAR_VECTOR_T; //Append 1 to the vector to store l in the output