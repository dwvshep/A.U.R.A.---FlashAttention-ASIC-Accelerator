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

`define INTEGER_WIDTH 8           // Width of integer data types (4, 8, 16, 32)

`define MAX_EMBEDDING_DIM 64      // Maximum embedding dimension supported

`define MAX_SEQ_LENGTH 512        // Maximum sequence length supported

`define MEM_BLOCK_SIZE_BITS 64    // Size of memory block in bits

`define MEM_BLOCK_SIZE_BYTES (`MEM_BLOCK_SIZE_BITS / 8) // Size of memory block in bytes

`define MAX_NUM_PES ((`MAX_SEQ_LENGTH * `MEM_BLOCK_SIZE_BYTES) / (`MAX_EMBEDDING_DIM * `INTEGER_WIDTH/8)) // Maximum and optimal number of processing elements supported

`define NUM_PES 512        // Number of parallel processing elements

`define SRAM_SIZE_KB  128         // Size of SRAM in KB

`define K_SRAM_BYTES (`MAX_EMBEDDING_DIM * `INTEGER_WIDTH/8) // Bytes needed to store one K row vector in SRAM

`define V_SRAM_BYTES (`MAX_EMBEDDING_DIM * `INTEGER_WIDTH/8) // Bytes needed to store one V row vector in SRAM

`define Q_SRAM_BYTES (`SRAM_SIZE_KB * 1024 - `K_SRAM_BYTES - `V_SRAM_BYTES) // Bytes available to store Q vectors in SRAM

`define Q_SRAM_ROW_BYTES (`MAX_EMBEDDING_DIM * `INTEGER_WIDTH/8) // Bytes needed to store one Q row vector in SRAM

`define Q_SRAM_DEPTH (`Q_SRAM_BYTES/`Q_SRAM_ROW_BYTES) // Number of full length Q row vectors that can be stored in SRAM

`define REDUCTIONS_PER_STAGE 2

`define NUM_REDUCE_STAGES ($clog2(`MAX_EMBEDDING_DIM)/`REDUCTIONS_PER_STAGE)



//////////////////////////////////////
// ---- Q-format helper macros ---- //
//////////////////////////////////////

// Compute the total width of a Qm.n number
`define Q_WIDTH(M, N) ((M) + (N) + 1)   // +1 for sign bit

// Define a packed logic vector representing signed Q-format number
`define Q_TYPE(M, N) logic signed [`Q_WIDTH(M, N)-1:0]

// Returns max signed value of width W
`define MAX_SIGNED(W)  $signed( (1'b0 << ((W)-1)) | ((1<<((W)-1))-1) )

// Returns min signed value of width W
`define MIN_SIGNED(W)  $signed( 1 << ((W)-1) )


////////////////////////////////////////////
// ---- Fixed Point Type Definitions ---- //
////////////////////////////////////////////

//You may choose to increase the precision of the input and/or output vectors depending on
//what fixed point ranges fit your values nicely

//Set this to 1 if you want to round decimals to the nearest value when converting to a narrower bit width
//Leave at 0 if you want simpler truncation with half precision
`define ROUNDING 1

//Input vectors (QKV)
`define INPUT_VEC_I 0
`define INPUT_VEC_F 7
typedef `Q_TYPE(`INPUT_VEC_I, `INPUT_VEC_F) INPUT_VEC_QT;

//Output vectors (O)
`define OUTPUT_VEC_I 0
`define OUTPUT_VEC_F 7
typedef `Q_TYPE(`OUTPUT_VEC_I, `OUTPUT_VEC_F) OUTPUT_VEC_QT;

//Intermediate QTypes defined below have precision widths that
//directly depend on the desired precision of the inputs and outputs
//Fraction bit widths for the type definitions are shown here in 
//reverse order to visualize the dependencies

//Intermediate Fraction bit widths
`define DIV_INPUT_F (`OUTPUT_VEC_F + `ROUNDING)
`define EXPMUL_VEC_F ($clog2(`MAX_SEQ_LENGTH) + `INPUT_VEC_F + `ROUNDING)
`define EXPMUL_SHIFT_STAGE_F `EXPMUL_VEC_F + 6

`define EXPMUL_EXP_F 0
`define EXP_LOG2E_OUT_F (`ROUNDING + 1)
`define EXP_LOG2E_IN_F `EXP_LOG2E_OUT_F
`define EXPMUL_DIFF_OUT_F (`EXP_LOG2E_IN_F + 1 + `ROUNDING)
`define EXPMUL_DIFF_IN_F `EXPMUL_DIFF_OUT_F
`define SCORE_F (`EXPMUL_DIFF_IN_F + `ROUNDING)
`define DOT_F (`SCORE_F + $clog2(`MAX_EMBEDDING_DIM) + `ROUNDING)
`define PRODUCT_F `DOT_F
`define INTERMEDIATE_PRODUCT_F (2*`INPUT_VEC_F)

//Intermediate Integer bit widths (forward flowing dependencies)
`define INTERMEDIATE_PRODUCT_I (2*`INPUT_VEC_I + 1)
`define PRODUCT_I `INTERMEDIATE_PRODUCT_I
`define DOT_I (`PRODUCT_I + $clog2(`MAX_EMBEDDING_DIM))
`define SCORE_I `DOT_I
`define EXPMUL_DIFF_IN_I (`SCORE_I - 3)
`define EXPMUL_DIFF_OUT_I (`EXPMUL_DIFF_IN_I + 1)
`define EXP_LOG2E_IN_I `EXPMUL_DIFF_OUT_I
`define EXP_LOG2E_OUT_I (`EXP_LOG2E_IN_I + 1)
`define EXPMUL_EXP_I 4
`define EXPMUL_SHIFT_STAGE_I ($clog2(`MAX_SEQ_LENGTH) + `INPUT_VEC_I)


`define EXPMUL_VEC_I `EXPMUL_SHIFT_STAGE_I
`define DIV_INPUT_I ($clog2(`MAX_SEQ_LENGTH) + `INPUT_VEC_I)



//Intermediate QTypes
//Default configurations are shown in comments below each typedef

//**Conversion occurs between div output and final output**//

//Division (numerator and denominator)
typedef `Q_TYPE(`DIV_INPUT_I, `DIV_INPUT_F) DIV_INPUT_QT;
//Q9.8

//**Conversion occurs between expmul vector output and div input**//

//Expmul vectors (accumulated over the sequence length)
typedef `Q_TYPE(`EXPMUL_VEC_I, `EXPMUL_VEC_F) EXPMUL_VEC_QT;
//Q9.17

typedef `Q_TYPE(`EXPMUL_SHIFT_STAGE_I, `EXPMUL_SHIFT_STAGE_F) EXPMUL_SHIFT_STAGE_QT;
//Q9.23

//Expmul clipped exponent (clipped to a reasonable integer range [-16, 0])
typedef `Q_TYPE(`EXPMUL_EXP_I, `EXPMUL_EXP_F) EXPMUL_EXP_QT;
//Q4.0

//**Conversion occurs between expmul product and clipped exponent**//

//Expmul x*log2e product result
typedef `Q_TYPE(`EXP_LOG2E_OUT_I, `EXP_LOG2E_OUT_F) EXPMUL_LOG2E_OUT_QT;
//Q6.2

//Expmul x*log2e product inputs
typedef `Q_TYPE(`EXP_LOG2E_IN_I, `EXP_LOG2E_IN_F) EXPMUL_LOG2E_IN_QT;
//Q5.2


//**Conversion occurs between expmul difference and approximate product inputs**//
//Use the type above for intermediate shifted values for (x + x >> 1 - x >> 4)

//Expmul difference output
typedef `Q_TYPE(`EXPMUL_DIFF_OUT_I, `EXPMUL_DIFF_OUT_F) EXPMUL_DIFF_OUT_QT;
//Q5.4

//Expmul difference inputs
typedef `Q_TYPE(`EXPMUL_DIFF_IN_I, `EXPMUL_DIFF_IN_F) EXPMUL_DIFF_IN_QT;
//Q4.4

//**Conversion occurs between shifted sum and expmul difference**//

//Dot Product sum
typedef `Q_TYPE(`DOT_I, `DOT_F) DOT_QT;
//Q7.12

//Dot Product products
typedef `Q_TYPE(`PRODUCT_I, `PRODUCT_F) PRODUCT_QT;
//Q1.12

//Dot Product intermediate products
typedef `Q_TYPE(`INTERMEDIATE_PRODUCT_I, `INTERMEDIATE_PRODUCT_F) INTERMEDIATE_PRODUCT_QT;
//Q1.14


////////////////////////////////////
// ---- I/O Type Definitions ---- //
////////////////////////////////////

typedef INPUT_VEC_QT [`MAX_EMBEDDING_DIM] Q_VECTOR_T;

typedef INPUT_VEC_QT [`MAX_EMBEDDING_DIM] K_VECTOR_T;

typedef INPUT_VEC_QT [`MAX_EMBEDDING_DIM] V_VECTOR_T;

typedef OUTPUT_VEC_QT [`MAX_EMBEDDING_DIM] O_VECTOR_T;

typedef EXPMUL_VEC_QT [`MAX_EMBEDDING_DIM+1] STAR_VECTOR_T;

typedef EXPMUL_SHIFT_STAGE_QT [`MAX_EMBEDDING_DIM+1] EXPMUL_SHIFT_VECTOR_T;



//////////////////////////////////
// ---- Memory Definitions ---- //
//////////////////////////////////

typedef logic [31:0] ADDR;

//Base Addresses
parameter ADDR K_BASE = 32'h0000_0000;   // 0
parameter ADDR V_BASE = 32'h0000_8000;   // +32 KB
parameter ADDR Q_BASE = 32'h0001_0000;   // +64 KB
parameter ADDR O_BASE = 32'h0001_8000;   // +96 KB

`define MEM_LATENCY_IN_CYCLES (100.0/`CLOCK_PERIOD+0.49999)
// the 0.49999 is to force ceiling(100/period). The default behavior for
// float to integer conversion is rounding to nearest

// memory tags represent a unique id for outstanding mem transactions
// 0 is a sentinel value and is not a valid tag
`define NUM_MEM_TAGS 15
typedef logic [3:0] MEM_TAG;

`define MEM_SIZE_IN_BYTES (64*1024*2)

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


///////////////////////////
// ---- DEBUG FLAGS ---- //
///////////////////////////

//Comment out when synthesizing
`define AURA_DEBUG 
// `define KSRAM_DEBUG
// `define VSRAM_DEBUG
// `define QSRAM_DEBUG
`define OSRAM_DEBUG
`define INT_DIV_DEBUG
`define VEC_DEBUG
`define DOT_PRODUCT_DEBUG
`define EXPMUL_DEBUG
`define MAX_DEBUG
`define MEM_CTRL_DEBUG

`endif