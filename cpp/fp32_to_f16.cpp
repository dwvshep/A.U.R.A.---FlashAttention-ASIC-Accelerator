#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <sstream>
#include <iomanip>
#include <cmath>
#include <algorithm>
#include <cstdint>
#include <string.h>

using namespace std;

static constexpr int ROWS = 512;
static constexpr int COLS = 64;

static constexpr int BYTES_PER_ELT = 2;     // int16
static constexpr int ELTS_PER_LINE = 4;     // pack 4 int16 → 8 bytes → 64 bits
static constexpr int LINES_PER_ROW = COLS / ELTS_PER_LINE;

static constexpr double Q_FACTOR = 32768.0; // Q0.15 scaling

// ---------------------------
// Read FP32 .mem (big-endian text → little endian bits → float)
// ---------------------------
vector<float> read_fp32_mem(const string &filename) {
    ifstream fin(filename);
    if (!fin) throw runtime_error("Cannot open " + filename);

    vector<float> data;
    string line;

    while (getline(fin, line)) {
        line.erase(remove_if(line.begin(), line.end(), ::isspace), line.end());

        for (size_t i = 0; i + 8 <= line.size(); i += 8) {
            string hex_be = line.substr(i, 8);

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

    return data;
}

// ---------------------------
// Quantize FP32 → int16 (Q0.15)
// ---------------------------
vector<int16_t> quantize_fp32_to_int16(const vector<float>& data) {
    vector<int16_t> result(data.size());

    for (size_t i = 0; i < data.size(); i++) {
        long q = lround(data[i] * Q_FACTOR);

        if (q > 32767)  q = 32767;
        if (q < -32768) q = -32768;

        result[i] = static_cast<int16_t>(q);
    }
    return result;
}

// ---------------------------
// Write int16 .mem file (pack 8 × int16 = 16 bytes per line)
// ---------------------------
void write_int16_mem(const vector<int16_t>& data, const string &filename) {
    ofstream fout(filename);
    if (!fout) throw runtime_error("Cannot open for writing " + filename);

    for (int r = 0; r < ROWS; ++r) {
        for (int l = 0; l < LINES_PER_ROW; ++l) {

            uint64_t packed = 0;

            for (int e = 0; e < ELTS_PER_LINE; ++e) {
                uint16_t val = uint16_t(data[r * COLS + l * ELTS_PER_LINE + e]);
                packed |= (uint64_t(val) << (16 * e)); // little-endian packing
            }

            // Output 64 bits = 16 hex chars
            ostringstream ss;
            ss << uppercase << hex << setfill('0') << setw(16) << packed;
            fout << ss.str() << "\n";
        }
    }
}

// ---------------------------
// Main
// ---------------------------
int main(int argc, char **argv) {

    if (argc != 3) {
        cerr << "Usage: " << argv[0] << " <input_fp32.mem> <output_int16.mem>\n";
        return 1;
    }

    string input = argv[1];
    string output = argv[2];

    cout << "Reading: " << input << "\n";
    auto fp32 = read_fp32_mem(input);

    cout << "Quantizing to int16...\n";
    auto int16data = quantize_fp32_to_int16(fp32);

    cout << "Writing: " << output << "\n";
    write_int16_mem(int16data, output);

    cout << "Done.\n";
    return 0;
}
