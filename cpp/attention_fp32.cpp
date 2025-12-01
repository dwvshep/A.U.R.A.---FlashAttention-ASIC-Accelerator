#include <bits/stdc++.h>
using namespace std;

static constexpr int ROWS = 512;
static constexpr int COLS = 64;
static constexpr int LINES_PER_ROW = COLS / 8;
static constexpr double SCALE = 1.0 / sqrt((double)COLS);

// -----------------------------------------------------
// Correct FP32 .mem reader (Big-Endian → Little-Endian)
// -----------------------------------------------------
vector<vector<float>> read_fp32_mem(const string &filename) {
    ifstream fin(filename);
    if (!fin) throw runtime_error("Cannot open " + filename);

    vector<float> data;
    string line;
    while (getline(fin, line)) {
        // remove whitespace
        line.erase(remove_if(line.begin(), line.end(), ::isspace), line.end());

        // read 8 hex chars at a time
        for (size_t i = 0; i + 8 <= line.size(); i += 8) {
            string hex_be = line.substr(i, 8); // big-endian hex string

            // swap byte order → little-endian
            string hex_le =
                hex_be.substr(6, 2) +
                hex_be.substr(4, 2) +
                hex_be.substr(2, 2) +
                hex_be.substr(0, 2);

            uint32_t bits = stoul(hex_le, nullptr, 16);

            float f;
            memcpy(&f, &bits, sizeof(float));
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
// write FP32 .mem (no change)
// ---------------------------
void write_fp32_mem(const string &filename, const vector<vector<float>> &M) {
    ofstream ofs(filename);
    if (!ofs) throw runtime_error("Cannot open for writing " + filename);

    for (int r = 0; r < ROWS; ++r) {
        for (int l = 0; l < LINES_PER_ROW; ++l) {
            for (int b = 0; b < 8; ++b) {
                float f = M[r][l*8 + b];
                uint32_t bits;
                memcpy(&bits, &f, sizeof(float));

                // convert to big-endian text (reverse bytes)
                uint32_t be =
                    ((bits & 0x000000FF) << 24) |
                    ((bits & 0x0000FF00) << 8)  |
                    ((bits & 0x00FF0000) >> 8)  |
                    ((bits & 0xFF000000) >> 24);

                ofs << uppercase << setw(8) << setfill('0') << hex << be;
            }
            ofs << "\n";
        }
    }
}

// ---------------------------
// main
// ---------------------------
int main(int argc, char **argv) {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);

    if (argc != 5) {
        cerr << "Usage: " << argv[0]
             << " <Q.mem> <K.mem> <V.mem> <O_float_correct.mem>\n";
        return 1;
    }

    string qfile = argv[1];
    string kfile = argv[2];
    string vfile = argv[3];
    string outfile = argv[4];

    try {
        cerr << "Reading " << qfile << "...\n";
        auto Q = read_fp32_mem(qfile);

        cerr << "Reading " << kfile << "...\n";
        auto K = read_fp32_mem(kfile);

        cerr << "Reading " << vfile << "...\n";
        auto V = read_fp32_mem(vfile);

        vector<vector<float>> O(ROWS, vector<float>(COLS, 0.0f));
        vector<float> scores(ROWS), weights(ROWS);

        for (int i = 0; i < ROWS; ++i) {
            float max_score = -numeric_limits<float>::infinity();
            for (int j = 0; j < ROWS; ++j) {
                float s = dot64(Q[i], K[j]) * SCALE;
                scores[j] = s;
                max_score = max(max_score, s);
            }

            float sumexp = 0.0f;
            for (int j = 0; j < ROWS; ++j) {
                float e = exp(scores[j] - max_score);
                weights[j] = e;
                sumexp += e;
            }
            if (sumexp == 0.0f) sumexp = 1e-12f;
            for (int j = 0; j < ROWS; ++j)
                weights[j] /= sumexp;

            vector<float> out(COLS, 0.0f);
            for (int j = 0; j < ROWS; ++j)
                for (int d = 0; d < COLS; ++d)
                    out[d] += weights[j] * V[j][d];

            O[i] = out;

            if ((i % 64) == 0)
                cerr << "Computed row " << i << "/" << ROWS << "\n";
        }

        cerr << "Writing FP32 output to " << outfile << "...\n";
        write_fp32_mem(outfile, O);
        cerr << "Done.\n";

    } catch (const exception &e) {
        cerr << "ERROR: " << e.what() << "\n";
        return 1;
    }

    return 0;
}

