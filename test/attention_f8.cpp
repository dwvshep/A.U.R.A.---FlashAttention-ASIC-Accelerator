#include <bits/stdc++.h>
using namespace std;

static constexpr int ROWS = 512;
static constexpr int COLS = 64;
static constexpr int LINES_PER_ROW = COLS / 8;
static constexpr float SCALE = 1.0f / sqrt((float)COLS);   // same as FP32

// -----------------------------------------------------
// Read INT8 .mem  (MSB-first byte order per line)
// -----------------------------------------------------
vector<vector<int8_t>> read_int8_mem(const string &filename) {
    ifstream fin(filename);
    if (!fin) throw runtime_error("Cannot open " + filename);

    vector<int8_t> data;
    string line;
    while (getline(fin, line)) {
        line.erase(remove_if(line.begin(), line.end(), ::isspace), line.end());
        for (size_t i = 0; i + 2 <= line.size(); i += 2) {
            int val = stoi(line.substr(i, 2), nullptr, 16);
            if (val >= 128) val -= 256;   // convert to signed
            data.push_back((int8_t)val);
        }
    }

    if (data.size() != ROWS * COLS)
        throw runtime_error("Unexpected number of int8 values in " + filename);

    vector<vector<int8_t>> M(ROWS, vector<int8_t>(COLS));
    for (int r = 0; r < ROWS; ++r)
        for (int c = 0; c < COLS; ++c)
            M[r][c] = data[r * COLS + c];

    return M;
}

// -----------------------------------------------------
// Write INT8 .mem (LSB-first in 64-bit word)
// -----------------------------------------------------
void write_int8_mem(const string &filename, const vector<vector<int8_t>> &M) {
    ofstream fout(filename);
    if (!fout) throw runtime_error("Cannot open for writing " + filename);

    for (int r = 0; r < ROWS; ++r) {
        for (int l = 0; l < LINES_PER_ROW; ++l) {
            uint64_t packed = 0;
            for (int b = 0; b < 8; ++b) {
                uint64_t byte = uint64_t(uint8_t(M[r][l*8 + b]));
                packed |= (byte & 0xFFULL) << (8 * b);  // LSB-first packing
            }

            fout << uppercase << hex << setw(16) << setfill('0') << packed << "\n";
        }
    }
}


// Dot product with integer inputs (with float accumulation)
inline float dot64(const vector<int8_t> &a, const vector<int8_t> &b) {
    float s = 0.0f;
    for (int i = 0; i < COLS; ++i)
        s += float(a[i]) * float(b[i]) / 128.f / 128.f;   // convert products to float
    return s;
}

// -----------------------------------------------------
// Main – int8 full attention
// -----------------------------------------------------
int main(int argc, char **argv) {
    ios::sync_with_stdio(false);

    string qfile = "../mem/Q_8.mem";
    string kfile = "../mem/K_8.mem";
    string vfile = "../mem/V_8.mem";
    string outfile = "../mem/O_F_8.mem";

    if (argc == 4) { qfile = argv[1]; kfile = argv[2]; vfile = argv[3]; }
    else if (argc == 5) { qfile = argv[1]; kfile = argv[2]; vfile = argv[3]; outfile = argv[4]; }

    try {
        cerr << "Reading Q...\n";
        auto Q = read_int8_mem(qfile);
        cerr << "Reading K...\n";
        auto K = read_int8_mem(kfile);
        cerr << "Reading V...\n";
        auto V = read_int8_mem(vfile);

        vector<vector<int8_t>> O(ROWS, vector<int8_t>(COLS));
        vector<float> scores(ROWS), weights(ROWS);

        for (int i = 0; i < ROWS; ++i) {
            // attention scores
            float max_score = -numeric_limits<float>::infinity();
            for (int j = 0; j < ROWS; ++j) {
                float s = dot64(Q[i], K[j]) * SCALE;
                scores[j] = s;
                max_score = max(max_score, s);
            }

            // softmax
            float sumexp = 0.0f;
            for (int j = 0; j < ROWS; ++j) {
                float e = exp(scores[j] - max_score);
                weights[j] = e;
                sumexp += e;
            }
            if (sumexp == 0.0f) sumexp = 1e-12f;
            for (int j = 0; j < ROWS; ++j) weights[j] /= sumexp;

            // weighted sum
            vector<float> out(COLS, 0.0f);
            for (int j = 0; j < ROWS; ++j)
                for (int d = 0; d < COLS; ++d)
                    out[d] += weights[j] * (float(V[j][d]) / 128.f);

            // requantize → int8
            for (int d = 0; d < COLS; ++d) {
                float q = round(out[d] * 128.f);
                if (q > 127) q = 127;
                if (q < -128) q = -128;
                O[i][d] = (int8_t)q;
            }

            if (i % 64 == 0)
                cerr << "Computed row " << i << "/" << ROWS << "\n";
        }

        cerr << "Writing output to " << outfile << "...\n";
        write_int8_mem(outfile, O);
        cerr << "Done.\n";

    } catch (const exception &e) {
        cerr << "ERROR: " << e.what() << endl;
        return 1;
    }

    return 0;
}
