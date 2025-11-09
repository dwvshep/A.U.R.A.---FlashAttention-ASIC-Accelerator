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

`define SRAM_SIZE_KB  128          // Size of SRAM in KB

`define MAX_EMBEDDING_DIM 64     // Maximum embedding dimension supported

`define MAX_SEQ_LENGTH 1024        // Maximum sequence length supported

`define INTEGER_WIDTH 16          // Width of integer data types (4, 8, 16, 32)

`define Q_TILE_WIDTH 



typedef signed logic [`INTEGER_WIDTH-1:0] INT_T;

typedef INT_T [] Q_VECTOR_T;