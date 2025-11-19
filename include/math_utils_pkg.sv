package math_utils_pkg;

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
    function automatic logic signed [W_OUT-1:0]
    q_sign_extend #(int W_IN, int W_OUT)
    (
        input logic signed [W_IN-1:0] x
    );
        begin
            q_sign_extend = {{(W_OUT-W_IN){x[W_IN-1]}}, x};
        end
    endfunction


    // ------------------------------------------------------------
    // SATURATE an arbitrary-width signed number to a smaller width
    // ------------------------------------------------------------
    function automatic logic signed [W_OUT-1:0]
    q_saturate #(int W_OUT, int W_IN)
    (
        input logic signed [W_IN-1:0] x
    );
        localparam logic signed [W_OUT-1:0] MAXV = {1'b0, {(W_OUT-1){1'b1}}};
        localparam logic signed [W_OUT-1:0] MINV = {1'b1, {(W_OUT-1){1'b0}}};

        begin
            if (x > MAXV)
                q_saturate = MAXV;
            else if (x < MINV)
                q_saturate = MINV;
            else
                q_saturate = x[W_OUT-1:0];  // truncation is safe
        end
    endfunction


    // ------------------------------------------------------------
    // FRACTIONAL ALIGNMENT: convert Q(IN_I).(IN_F) → Q(IN_I).(OUT_F)
    // Does safe left or right shifts.
    // ------------------------------------------------------------
    function automatic logic signed [W_OUT-1:0]
    q_align_frac #(
        int IN_I, int IN_F,
        int OUT_F
    )
    (
        input logic signed [W_IN-1:0] x
    );
        localparam int W_IN  = `Q_WIDTH(IN_I, IN_F);
        localparam int W_OUT = `Q_WIDTH(IN_I, OUT_F);

        logic signed [W_OUT-1:0] temp;

        begin
            // Same number of fractional bits → sign extend only
            if (OUT_F == IN_F) begin
                temp = x;

            // Need MORE fractional bits → LEFT SHIFT
            end else if (OUT_F > IN_F) begin
                temp = {x, {(OUT_F-IN_F){1'b0}}};

            // Need FEWER fractional bits → RIGHT SHIFT
            end else begin // OUT_F < IN_F
                temp = (x >>> (IN_F-OUT_F));
            end

            q_align_frac = temp;
        end
    endfunction

    // ------------------------------------------------------------
    // INTEGER ALIGNMENT: convert Q(IN_I).(IN_F) → Q(IN_I).(OUT_F)
    // Does safe left or right shifts.
    // ------------------------------------------------------------
    function automatic logic signed [W_OUT-1:0]
    q_align_int #(
        int IN_I, int IN_F
        int OUT_I, int OUT_F
    )
    (
        input logic signed [W_IN-1:0] x
    );
        localparam int W_IN  = `Q_WIDTH(IN_I, IN_F);
        localparam int W_OUT = `Q_WIDTH(IN_I, OUT_F);

        logic signed [W_OUT-1:0] temp;

        begin
            // Same number of fractional bits → sign extend only
            if (IN_T == OUT_I) begin
                temp = x;

            // Need MORE fractional bits → LEFT SHIFT
            end else if (IN_I > OUT_I) begin
                temp = q_saturate  #(W_OUT, W_IN)(x);

            // Need FEWER fractional bits → RIGHT SHIFT
            end else begin // OUT_F < IN_F
                temp = q_sign_extend(x, W_IN, W_OUT)
            end

            q_align_int = temp;
        end
    endfunction


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
    function automatic logic signed [W_OUT-1:0]
    q_convert #(
        int IN_I, int IN_F,
        int OUT_I, int OUT_F
    )
    (
        input logic signed [W_IN-1:0] x
    );

        localparam int W_IN  = `Q_WIDTH(IN_I, IN_F);
        localparam int W_MID = `Q_WIDTH(IN_I, OUT_F);
        localparam int W_OUT = `Q_WIDTH(OUT_I, OUT_F);

        logic signed [W_MID-1:0] frac_aligned;
        logic signed [W_OUT-1:0] int_aligned;

        begin
            frac_aligned   = q_align_frac #(IN_I, IN_F, OUT_F)(x);
            int_aligned    = q_align_int #(IN_I, OUT_I)(frac_aligned);
            q_convert = int_aligned;
        end
    endfunction


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

    //Since we know the denominator should be at least 1, 
    //Chat math says we should only need one extra fractional bit in the
    //numerator and denominator to prevent and errors in the output Q0.7
    typedef `Q_TYPE(9, 8) EXPMUL_VSHIFT_QT;

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

endpackage