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



////////////////////////////////////
// ---- Bit Width Parameters ---- //
////////////////////////////////////

//These are currently irrelevant
`define INPUT_SIZE 8

`define TWO_PRODUCT_SIZE 1 + 2*(`INPUT_SIZE-1)

`define DOT_PRODUCT_SIZE $clog2(`MAX_EMBEDDING_DIM) + `TWO_PRODUCT_SIZE

`define EXPMUL_OUTPUT_SIZE 30



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


// ------------------------------------------------------------
// SIGN EXTENSION to arbitrary width
// ------------------------------------------------------------
// function automatic logic signed [W_OUT-1:0]
// q_sign_extend (
//     input int W_IN, 
//     input int W_OUT,
//     input logic signed [W_IN-1:0] x
// );
//     begin
//         q_sign_extend = {{(W_OUT-W_IN){x[W_IN-1]}}, x};
//     end
// endfunction


// ------------------------------------------------------------
// SATURATE an arbitrary-width signed number to a smaller width
// ------------------------------------------------------------
// function automatic logic signed [W_OUT-1:0]
// q_saturate (
//     input int W_OUT, 
//     input int W_IN,
//     input logic signed [W_IN-1:0] x
// );
//     localparam logic signed [W_OUT-1:0] MAXV = {1'b0, {(W_OUT-1){1'b1}}};
//     localparam logic signed [W_OUT-1:0] MINV = {1'b1, {(W_OUT-1){1'b0}}};

//     begin
//         if (x > MAXV)
//             q_saturate = MAXV;
//         else if (x < MINV)
//             q_saturate = MINV;
//         else
//             q_saturate = x[W_OUT-1:0];  // truncation is safe
//     end
// endfunction


// ------------------------------------------------------------
// FRACTIONAL ALIGNMENT: convert Q(IN_I).(IN_F) → Q(IN_I).(OUT_F)
// Does safe left or right shifts.
// ------------------------------------------------------------
// function automatic logic signed [W_OUT-1:0]
// q_align_frac (
//     input int IN_I, 
//     input int IN_F,
//     input int OUT_F,
//     input logic signed [W_IN-1:0] x
// );
//     localparam int W_IN  = `Q_WIDTH(IN_I, IN_F);
//     localparam int W_OUT = `Q_WIDTH(IN_I, OUT_F);

//     logic signed [W_OUT-1:0] temp;

//     begin
//         // Same number of fractional bits → sign extend only
//         if (OUT_F == IN_F) begin
//             temp = x;

//         // Need MORE fractional bits → LEFT SHIFT
//         end else if (OUT_F > IN_F) begin
//             temp = {x, {(OUT_F-IN_F){1'b0}}};

//         // Need FEWER fractional bits → RIGHT SHIFT
//         end else begin // OUT_F < IN_F
//             temp = (x >>> (IN_F-OUT_F));
//         end

//         q_align_frac = temp;
//     end
// endfunction

// ------------------------------------------------------------
// INTEGER ALIGNMENT: convert Q(IN_I).(IN_F) → Q(IN_I).(OUT_F)
// Does safe left or right shifts.
// ------------------------------------------------------------
// function automatic logic signed [W_OUT-1:0]
// q_align_int (
//     input int IN_I, 
//     input int IN_F,
//     input int OUT_I, 
//     input int OUT_F,
//     input logic signed [W_IN-1:0] x
// );
//     localparam int W_IN  = `Q_WIDTH(IN_I, IN_F);
//     localparam int W_OUT = `Q_WIDTH(IN_I, OUT_F);

//     logic signed [W_OUT-1:0] temp;

//     begin
//         // Same number of fractional bits → sign extend only
//         if (IN_T == OUT_I) begin
//             temp = x;

//         // Need MORE fractional bits → LEFT SHIFT
//         end else if (IN_I > OUT_I) begin
//             temp = q_saturate  #(W_OUT, W_IN)(x);

//         // Need FEWER fractional bits → RIGHT SHIFT
//         end else begin // OUT_F < IN_F
//             temp = q_sign_extend(x, W_IN, W_OUT)
//         end

//         q_align_int = temp;
//     end
// endfunction


// ------------------------------------------------------------
// FULL Q FORMAT CONVERSION:
//
//    Input  : Q(IN_I).IN_F   (stored in x)
//    Output : Q(OUT_I).OUT_F
//
// Steps:
//   1. Align fractional bits (shifts)
//   2. Saturate to target width
//   3. Return clipped result
// ------------------------------------------------------------
// function automatic logic signed [W_OUT-1:0]
// q_convert (
//     input int IN_I, 
//     input int IN_F,
//     input int OUT_I, 
//     input int OUT_F,
//     input logic signed [W_IN-1:0] x
// );

//     localparam int W_IN  = `Q_WIDTH(IN_I, IN_F);
//     localparam int W_MID = `Q_WIDTH(IN_I, OUT_F);
//     localparam int W_OUT = `Q_WIDTH(OUT_I, OUT_F);

//     logic signed [W_MID-1:0] frac_aligned;
//     logic signed [W_OUT-1:0] int_aligned;

//     begin
//         frac_aligned   = q_align_frac #(IN_I, IN_F, OUT_F)(x);
//         int_aligned    = q_align_int #(IN_I, OUT_I)(frac_aligned);
//         q_convert = int_aligned;
//     end
// endfunction



////////////////////////////////////////////
// ---- Fixed Point Type Definitions ---- //
////////////////////////////////////////////

// We can reduce the fractional bits based on the most needed precision to keep the true Q0.7 at the output

//---------------------------
// Weights and Outputs QTypes
//---------------------------

// In-memory storage: Q0.7  (Q/K/V/O vectors)
typedef `Q_TYPE(0, 7) MEM_QT;


//-------------------
// Dot-Product QTypes
//-------------------

//IDK THE BEST WAY TO STORE INTERMEDIATES IN A PROGRAMMABLE WAY FOR THE LOG FOR LOOP
// Product of two qmem_t's
//typedef `Q_TYPE(1, 14) PRODUCT_QT;

// Dot-product output: Q6.14 (64-wide dot products)
//typedef `Q_TYPE(7, 14) DOT_QT;

// Logits (QKᵀ scaled by 1/√d a.k.a >>> 3): Q4.17
//typedef `Q_TYPE(4, 17) DOT_SCALED_QT;


//-------------------
// Expmul QTypes
//-------------------

// Difference of the two Q4.17 inputs
//typedef `Q_TYPE(5, 17) EXPMUL_DIFF_QT

// Product of Q4.17 with log2e via approximation (x + x >> 1 - x >> 4)
//typedef `Q_TYPE(6, 21) EXPMUL_LOG2E_QT

// Clipped exponent based on the Q6.21 to the range (-16, 15) **Guaranteed to be negative
//typedef `Q_TYPE(4, 0) EXPMUL_EXPONENT_QT

// 2^-L * V output format (right shift by 0-16 bits): Q0.23
// Must cast input V weights to this many fractional bits plus 1 int bit for representing "1" appended to the beginning 
// and plus another 9 for the 512 accumulations into the output vetor
// If we are considering 1 as a value in the V vector, technically each value is a Q1.7, and the output would be a Q1.23
// Once we add 512 of these together we will add 9 bits to the integer portion and therefore
// The output would be Q10.23, but we can assume we will never really hit that max and just keep it at Q9.23
//typedef `Q_TYPE(9, 23) EXPMUL_VSHIFT_QT;

//All inputs to the div module are therefore Q9.23's (33 bits)
//The outputs should be back to Q0.7s, and this should not require an integer bit clipping since the 
//output values should all be less than 1 after division

//If we know we only need 7 fractional bits of precision at the end of the day,
//We can throw away some fractional bits in the middle of the pipeline if they cannot
//possibly effect the value of the final output

//Now we work backwards from division
typedef `Q_TYPE(9, 7) DIV_INPUT_QT;

//Since we know the denominator should be at least 1, 
//Chat math says we should only need one extra fractional bit in the
//numerator and denominator to prevent and errors in the output Q0.7
typedef `Q_TYPE(9, 16) EXPMUL_VSHIFT_QT;

// Keep the possible shift exponent rang (-16, 15) this is almost overkill
typedef `Q_TYPE(4, 0) EXPMUL_EXPONENT_QT;

//Since we clip to an int, we only need to keep one fractional bit from the Q6.21
typedef `Q_TYPE(6, 1) EXPMUL_LOG2E_QT;

//The same goes for the difference which gets multiplied by 1.43, but we can keep an extra bit for fun (8 bits total)
typedef `Q_TYPE(5, 2) EXPMUL_DIFF_QT;

//For linear ops like subtraction, just keep adding one more frac bit
typedef `Q_TYPE(4, 3) SCORE_QT;

//Before the shift of dividing by root(dk) we just need 7 int bits if we want to get a Q4.3 out
typedef `Q_TYPE(7, 6) DOT_QT;

//Need partial sum support here
typedef `Q_TYPE(4, 6) PARTIAL_DOT_QT;

//Since the above output comes from an essential shift by 6 we can say:
typedef `Q_TYPE(1, 6) PRODUCT_QT;

//Interemediate result for products
typedef `Q_TYPE(1, 14) INTERMEDIATE_PRODUCT_QT;


////////////////////////////////////
// ---- I/O Type Definitions ---- //
////////////////////////////////////

typedef MEM_QT [`MAX_EMBEDDING_DIM] Q_VECTOR_T;

typedef MEM_QT [`MAX_EMBEDDING_DIM] K_VECTOR_T;

typedef MEM_QT [`MAX_EMBEDDING_DIM] V_VECTOR_T;

typedef MEM_QT [`MAX_EMBEDDING_DIM] O_VECTOR_T;

typedef EXPMUL_VSHIFT_QT [`MAX_EMBEDDING_DIM+1] STAR_VECTOR_T;



//////////////////////////////////
// ---- Memory Definitions ---- //
//////////////////////////////////

typedef logic [31:0] ADDR;

//Base Addresses
parameter ADDR K_BASE = 'h0000_1000;
parameter ADDR V_BASE = 'h0000_2000;
parameter ADDR Q_BASE = 'h0000_3000;
parameter ADDR O_BASE = 'h0000_4000;

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

`endif