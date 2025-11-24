#include <bits/stdc++.h>
using namespace std;

static constexpr int ROWS = 512;
static constexpr int COLS = 64;
static constexpr int LINES_PER_ROW = COLS / 8;

// scale for Q*K dot product (like your FP64 SCALE)
static constexpr int32_t DOT_SCALE = 1 << 14;  // adjust for precision

// softmax scale factor (to keep sum <= 255)
static constexpr int32_t SOFTMAX_SCALE = 1 << 8;

vector<vector<uint8_t>> read_mem_matrix_u8(const string &filename) {
    ifstream ifs(filename);
    if (!ifs) throw runtime_error("Cannot open " + filename);
    vector<uint64_t> lines;
    string s;
    while (getline(ifs, s)) {
        auto start = s.find_first_not_of(" \t\r\n");
        if (start == string::npos) continue;
        auto end = s.find_last_not_of(" \t\r\n");
        string tok = s.substr(start, end - start + 1);
        if (tok.empty()) continue;
        uint64_t v = 0;
        stringstream ss;
        ss << std::hex << tok;
        ss >> v;
        lines.push_back(v);
    }
    if ((int)lines.size() != ROWS * LINES_PER_ROW)
        throw runtime_error("Incorrect line count");

    vector<vector<uint8_t>> M(ROWS, vector<uint8_t>(COLS));
    for (int r = 0; r < ROWS; ++r) {
        int base_line = r * LINES_PER_ROW;
        int out_index = 0;
        for (int l = 0; l < LINES_PER_ROW; ++l) {
            uint64_t val = lines[base_line + l];
            for (int b = 0; b < 8; ++b) {
                uint8_t byte = (uint8_t)((val >> (8*b)) & 0xFF);
                M[r][out_index++] = byte;
            }
        }
    }
    return M;
}

void write_mem_matrix(const string &filename, const vector<vector<uint8_t>> &M) {
    ofstream ofs(filename);
    if (!ofs) throw runtime_error("Cannot open " + filename);
    for (int r = 0; r < ROWS; ++r) {
        for (int l = 0; l < LINES_PER_ROW; ++l) {
            uint64_t packed = 0;
            for (int b = 0; b < 8; ++b) {
                uint64_t byte = M[r][l*8 + b];
                packed |= (byte & 0xFFULL) << (8*b);
            }
            ofs << hex << uppercase << setw(16) << setfill('0') << packed << "\n";
        }
    }
}

// fixed-point dot product: Q[i]*K[j], accumulate in int32
inline int32_t dot8(const vector<uint8_t> &a, const vector<uint8_t> &b) {
    int32_t s = 0;
    for (int i = 0; i < COLS; ++i)
        s += ((int32_t)a[i]) * ((int32_t)b[i]);
    s = (s * DOT_SCALE) / COLS; // scale down like FP64 SCALE
    return s;
}

// fixed-point softmax
void softmax_fixed(const vector<int32_t> &scores, vector<uint16_t> &weights) {
    int32_t max_s = *max_element(scores.begin(), scores.end());
    vector<uint32_t> exp_scores(scores.size());
    uint64_t sum_exp = 0;

    for (size_t j = 0; j < scores.size(); ++j) {
        int32_t diff = scores[j] - max_s; // diff <= 0
        // integer exp approximation
        if (diff < -1024*8) exp_scores[j] = 0;
        else exp_scores[j] = 65536 >> (-diff / 1024);
        sum_exp += exp_scores[j];
    }
    if (sum_exp == 0) sum_exp = 1;

    for (size_t j = 0; j < scores.size(); ++j)
        weights[j] = (uint16_t)((exp_scores[j] * 255) / sum_exp);
}


int main() {
    auto Q = read_mem_matrix_u8("../mem/random_test1/Q.mem");
    auto K = read_mem_matrix_u8("../mem/random_test1/K.mem");
    auto V = read_mem_matrix_u8("../mem/random_test1/V.mem");

    vector<vector<uint8_t>> O_bytes(ROWS, vector<uint8_t>(COLS,0));

    vector<int32_t> scores(ROWS);
    vector<uint16_t> weights(ROWS);

    for (int i = 0; i < ROWS; ++i) {
        // compute Q*K dot
        for (int j = 0; j < ROWS; ++j)
            scores[j] = dot8(Q[i], K[j]);

        softmax_fixed(scores, weights);

        // weighted sum V
        for (int j = 0; j < ROWS; ++j) {
            int w = weights[j]; // 0..255
            for (int d = 0; d < COLS; ++d) {
                int32_t tmp = w * V[j][d];
                O_bytes[i][d] = min(255, O_bytes[i][d] + (tmp >> 8)); // scale back
            }
        }

        if ((i%64)==0) cerr<<"Row "<<i<<"\n";
    }

    write_mem_matrix("../mem/random_test1/O_correct.mem", O_bytes);
}
