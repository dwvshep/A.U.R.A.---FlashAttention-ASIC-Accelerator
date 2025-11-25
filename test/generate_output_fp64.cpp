#include <bits/stdc++.h>
using namespace std;

static constexpr int ROWS = 512;      // number of matrix rows
static constexpr int COLS = 64;       // number of datapoints per row
static constexpr int LINES_PER_ROW = COLS / 8; // 8 lines per row
static constexpr double SCALE = 1.0 / sqrt((double)COLS);

// read a mem file (lines of 16-hex chars) and return a ROWS x COLS matrix (float)
vector<vector<double>> read_mem_matrix(const string &filename) {
    ifstream ifs(filename);
    if (!ifs) throw runtime_error("Cannot open " + filename);
    // read all lines into vector<uint64_t>
    vector<uint64_t> lines;
    string s;
    while (getline(ifs, s)) {
        // trim whitespace
        auto start = s.find_first_not_of(" \t\r\n");
        if (start == string::npos) continue;
        auto end = s.find_last_not_of(" \t\r\n");
        string tok = s.substr(start, end - start + 1);
        // ignore empty lines
        if (tok.empty()) continue;
        // parse hex (allow both lowercase and uppercase)
        uint64_t v = 0;
        std::stringstream ss;
        ss << std::hex << tok;
        ss >> v;
        lines.push_back(v);
    }
    if ((int)lines.size() != ROWS * LINES_PER_ROW) {
        stringstream msg;
        msg << "Expected " << (ROWS * LINES_PER_ROW) << " lines in " << filename
            << " but found " << lines.size();
        throw runtime_error(msg.str());
    }

    // build matrix
    vector<vector<double>> M(ROWS, vector<double>(COLS));
    for (int r = 0; r < ROWS; ++r) {
        int base_line = r * LINES_PER_ROW;
        int out_index = 0;
        for (int l = 0; l < LINES_PER_ROW; ++l) {
            uint64_t val = lines[base_line + l];
            // extract bytes little-endian: byte0 = LSB
            for (int b = 0; b < 8; ++b) {
                int8_t byte = (int8_t)((val >> (8*b)) & 0xFF);
                M[r][out_index++] = double(byte);
            }
        }
        if (out_index != COLS) throw runtime_error("internal indexing error");
    }
    return M;
}

// write a ROWS x COLS matrix of unsigned bytes into output file (same packed format)
void write_mem_matrix(const string &filename, const vector<vector<int8_t>> &M) {
    ofstream ofs(filename);
    if (!ofs) throw runtime_error("Cannot open for writing " + filename);
    // For each row, write LINES_PER_ROW lines, packing 8 bytes per line with LSB-first byte0
    for (int r = 0; r < ROWS; ++r) {
        int base = 0;
        for (int l = 0; l < LINES_PER_ROW; ++l) {
            uint64_t packed = 0;
            for (int b = 0; b < 8; ++b) {
                uint64_t byte = M[r][l*8 + b];
                packed |= (byte & 0xFFULL) << (8*b); // LSB-first
            }
            // print as 16 hex chars uppercase
            std::ostringstream ss;
            ss << std::uppercase << std::hex << std::setfill('0') << std::setw(16) << packed;
            ofs << ss.str() << '\n';
        }
    }
    ofs.close();
}

// pretty-print a matrix in human readable format
void print_matrix(const vector<vector<double>> &M, const string &name) {
    cout << "===== Matrix: " << name << " (" << M.size() << " x " << M[0].size() << ") =====\n";
    for (size_t r = 0; r < M.size(); ++r) {
        for (size_t c = 0; c < M[r].size(); ++c) {
            cout << (int)M[r][c];
            if (c + 1 != M[r].size()) cout << ", ";
        }
        cout << "\n";
    }
    cout << endl;
}

// pretty-print a matrix in hex (each entry is a byte 0..255)
void print_matrix_hex(const vector<vector<double>> &M, const string &name) {
    cout << "===== Matrix: " << name << " (" << M.size() << " x " << M[0].size() << ") =====\n";
    for (size_t r = 0; r < M.size(); ++r) {
        for (size_t c = 0; c < M[r].size(); ++c) {
            int8_t v = (int8_t)M[r][c];       // convert back to byte
            cout << "0x" << uppercase << hex << setw(2) << setfill('0') << (int)v;
            if (c + 1 != M[r].size()) cout << ", ";
        }
        cout << "\n";
    }
    cout << dec << endl;   // reset stream back to decimal
}

// compute dot product of length COLS vectors
inline double dot64(const vector<double> &a, const vector<double> &b) {
    double s = 0.0;
    for (int i = 0; i < COLS; ++i) s += a[i] * b[i];
    return s;
}

int main(int argc, char **argv) {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);

    string qfile = "../mem/random_test1/Q.mem";
    string kfile = "../mem/random_test1/K.mem";
    string vfile = "../mem/random_test1/V.mem";
    string outfile = "../mem/random_test1/O_float_correct.out";

    if (argc == 4) {
        qfile = argv[1];
        kfile = argv[2];
        vfile = argv[3];
    } else if (argc == 5) {
        qfile = argv[1]; kfile = argv[2]; vfile = argv[3]; outfile = argv[4];
    } else if (argc != 1) {
        cerr << "Usage: " << argv[0] << " [Q.mem K.mem V.mem [O.out]]\n";
        return 1;
    }

    try {
        cerr << "Reading " << qfile << " ...\n";
        auto Q = read_mem_matrix(qfile); // 512 x 64 doubles (0..255)
        cerr << "Reading " << kfile << " ...\n";
        auto K = read_mem_matrix(kfile);
        cerr << "Reading " << vfile << " ...\n";
        auto V = read_mem_matrix(vfile);

        print_matrix_hex(Q, "Q");

        // Precompute nothing else; run attention: for each i in 0..ROWS-1
        vector<vector<int8_t>> O_bytes(ROWS, vector<int8_t>(COLS, 0));

        // temp buffers
        vector<double> scores(ROWS);
        vector<double> weights(ROWS);

        for (int i = 0; i < ROWS; ++i) {
            // compute scores (Q[i] dot K[j]) * SCALE
            double max_score = -numeric_limits<double>::infinity();
            for (int j = 0; j < ROWS; ++j) {
                double s = dot64(Q[i], K[j]) * SCALE;
                scores[j] = s;
                if (s > max_score) max_score = s;
            }
            // softmax (numerically stable)
            double sumexp = 0.0;
            for (int j = 0; j < ROWS; ++j) {
                double e = exp(scores[j] - max_score);
                weights[j] = e;
                sumexp += e;
            }
            if (sumexp == 0.0) sumexp = 1e-12;
            for (int j = 0; j < ROWS; ++j) weights[j] /= sumexp;

            // weighted sum over V rows to form output vector of length COLS
            vector<double> out(COLS, 0.0);
            for (int j = 0; j < ROWS; ++j) {
                double w = weights[j];
                if (w == 0.0) continue;
                const auto &vj = V[j];
                for (int d = 0; d < COLS; ++d) out[d] += w * vj[d];
            }

            // quantize to [-128...127], round to nearest
            for (int d = 0; d < COLS; ++d) {
                double v = out[d];
                long long iv = (long long)llround(v);
                if (iv < -128) iv = -128;
                if (iv > 127) iv = 127;
                O_bytes[i][d] = (int8_t)iv;
            }

            if ((i % 64) == 0) cerr << "Computed row " << i << "/" << ROWS << "\n";
        }

        cerr << "Writing " << outfile << " ...\n";
        write_mem_matrix(outfile, O_bytes);
        cerr << "Done. Output written to " << outfile << "\n";
    } catch (const exception &e) {
        cerr << "ERROR: " << e.what() << "\n";
        return 2;
    }

    return 0;
}