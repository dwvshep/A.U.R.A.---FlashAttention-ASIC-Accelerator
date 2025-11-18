package math_utils_pkg;

    function automatic int clamp(int x, int lo, int hi);
        if (x < lo) return lo;
        if (x > hi) return hi;
        return x;
    endfunction

    

endpackage