#include <bits/stdc++.h>
using namespace std;

static constexpr int ROWS = 512;
static constexpr int COLS = 64;
static constexpr int LINES_PER_ROW = COLS / 8;
static constexpr double SCALE = 1.0 / sqrt((double)COLS);

// ---------------------------
// read FP32 matrix from mem file
// ---------------------------
vector<vector<float>> read_fp32_mem(const string &filename) {
    ifstream ifs(filename);
    if (!ifs) throw runtime_error("Cannot open " + filename);

    vector<float> data;
    string line;
    while (getline(ifs, line)) {
        line.erase(remove_if(line.begin(), line.end(), ::isspace), line.end());
        // each float = 8 hex chars
        for (size_t i = 0; i + 8 <= line.size(); i += 8) {
            string hexval = line.substr(i, 8);
            uint32_t intval = stoul(hexval, nullptr, 16);
            float f;
            memcpy(&f, &intval, sizeof(float));
            data.push_back(f);
        }
    }

    if (data.size() != ROWS * COLS)
        throw runtime_error("Unexpected number of FP32 values in " + filename);

    vector<vector<float>> M(ROWS, vector<float>(COLS));
    for (int r = 0; r < ROWS; ++r)
        for (int c = 0; c < COLS; ++c)
            M[r][c] = data[r * COLS + c];

    return M;
}

// ---------------------------
// compute dot product
// ---------------------------
inline float dot64(const vector<float> &a, const vector<float> &b) {
    float s = 0.0f;
    for (int i = 0; i < COLS; ++i) s += a[i] * b[i];
    return s;
}

// ---------------------------
// quantize float matrix to int8
// ---------------------------
vector<vector<int8_t>> quantize_to_int8(const vector<vector<float>> &M) {
    vector<vector<int8_t>> out(ROWS, vector<int8_t>(COLS, 0));

    // find max absolute value (for scaling)
    float max_abs = 0.0f;
    for (auto &row : M)
        for (auto v : row)
            max_abs = max(max_abs, fabs(v));

    if (max_abs == 0.0f) max_abs = 1e-12f; // avoid divide by zero
    float scale = max_abs / 127.0f;

    for (int r = 0; r < ROWS; ++r)
        for (int c = 0; c < COLS; ++c) {
            int val = round(M[r][c] / scale);
            if (val > 127) val = 127;
            if (val < -128) val = -128;
            out[r][c] = (int8_t)val;
        }

    return out;
}

// vector<vector<int8_t>> quantize_to_int8(const vector<vector<float>> &M) {
//     constexpr int OUT_I = 1;  // number of integer bits
//     constexpr int OUT_F = 7;  // number of fractional bits
//     constexpr int W_OUT = OUT_I + OUT_F;

//     vector<vector<int8_t>> out(ROWS, vector<int8_t>(COLS, 0));

//     // precompute max/min representable integers
//     const int32_t MAX_VAL = (1 << (W_OUT - 1)) - 1;   // 127 for 8-bit
//     const int32_t MIN_VAL = -(1 << (W_OUT - 1));      // -128 for 8-bit

//     for (int r = 0; r < ROWS; ++r) {
//         for (int c = 0; c < COLS; ++c) {
//             // scale real to fixed-point
//             float scaled = M[r][c] * (1 << OUT_F);

//             // saturate
//             if (scaled > MAX_VAL) scaled = MAX_VAL;
//             if (scaled < MIN_VAL) scaled = MIN_VAL;

//             // round to nearest integer
//             int32_t q = static_cast<int32_t>(roundf(scaled));

//             out[r][c] = static_cast<int8_t>(q);
//         }
//     }

//     return out;
// }

// ---------------------------
// write int8 matrix to packed mem file (8 bytes per line)
// ---------------------------
void write_int8_mem(const string &filename, const vector<vector<int8_t>> &M) {
    ofstream ofs(filename);
    if (!ofs) throw runtime_error("Cannot open for writing " + filename);

    for (int r = 0; r < ROWS; ++r) {
        for (int l = 0; l < LINES_PER_ROW; ++l) {
            uint64_t packed = 0;
            for (int b = 0; b < 8; ++b) {
                uint8_t byte = (uint8_t)M[r][l*8 + b];
                packed |= (uint64_t(byte) & 0xFFULL) << (8*b); // LSB-first
            }
            ofs << uppercase << hex << setw(16) << setfill('0') << packed << "\n";
        }
    }
}

// ---------------------------
// main
// ---------------------------
int main(int argc, char **argv) {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);

    string qfile = "../mem/Q_32.mem";
    string kfile = "../mem/K_32.mem";
    string vfile = "../mem/V_32.mem";
    string outfile = "../mem/O_32.mem";

    if (argc == 4) {
        qfile = argv[1]; kfile = argv[2]; vfile = argv[3];
    } else if (argc == 5) {
        qfile = argv[1]; kfile = argv[2]; vfile = argv[3]; outfile = argv[4];
    }

    try {
        cerr << "Reading " << qfile << "...\n";
        auto Q = read_fp32_mem(qfile);
        cerr << "Reading " << kfile << "...\n";
        auto K = read_fp32_mem(kfile);
        cerr << "Reading " << vfile << "...\n";
        auto V = read_fp32_mem(vfile);

        // output FP32 matrix
        vector<vector<float>> O(ROWS, vector<float>(COLS, 0.0f));
        vector<float> scores(ROWS), weights(ROWS);

        for (int i = 0; i < ROWS; ++i) {
            // compute attention scores
            float max_score = -numeric_limits<float>::infinity();
            for (int j = 0; j < ROWS; ++j) {
                float s = dot64(Q[i], K[j]) * SCALE;
                scores[j] = s;
                if (s > max_score) max_score = s;
            }

            // softmax
            float sumexp = 0.0f;
            for (int j = 0; j < ROWS; ++j) {
                float e = exp(scores[j] - max_score);
                weights[j] = e;
                sumexp += e;
            }
            if (sumexp == 0.0f) sumexp = 1e-12f;
            for (int j = 0; j < ROWS; ++j)
                weights[j] /= sumexp;

            // weighted sum over V
            vector<float> out(COLS, 0.0f);
            for (int j = 0; j < ROWS; ++j) {
                float w = weights[j];
                const auto &vj = V[j];
                for (int d = 0; d < COLS; ++d)
                    out[d] += w * vj[d];
            }

            O[i] = out;

            if ((i % 64) == 0) cerr << "Computed row " << i << "/" << ROWS << "\n";
        }

        cerr << "Quantizing output to int8...\n";
        auto O_int8 = quantize_to_int8(O);

        cerr << "Writing output to " << outfile << "...\n";
        write_int8_mem(outfile, O_int8);
        cerr << "Done.\n";

    } catch (const exception &e) {
        cerr << "ERROR: " << e.what() << "\n";
        return 1;
    }

    return 0;
}
