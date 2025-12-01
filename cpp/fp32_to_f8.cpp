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
static constexpr int LINES_PER_ROW = COLS / 8;
static constexpr double Q_FACTOR = 128;

// ---------------------------
// Read FP32 .mem (big-endian text -> little endian bits -> float)
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

            // big-endian text -> little-endian machine float
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
// Quantize FP32 to int8 (Q0.7)
// ---------------------------
vector<int8_t> quantize_fp32_to_int8(const vector<float>& data) {
    vector<int8_t> result(data.size());

    for (size_t i = 0; i < data.size(); i++) {
        long q = lround(data[i] * Q_FACTOR);
        if (q > 127) q = 127;
        if (q < -128) q = -128;
        result[i] = static_cast<int8_t>(q);
    }
    return result;
}

// ---------------------------
// Write int8 .mem file
// ---------------------------
void write_int8_mem(const vector<int8_t>& data, const string &filename) {
    ofstream fout(filename);
    if (!fout) throw runtime_error("Cannot open for writing " + filename);

    for (int r = 0; r < ROWS; ++r) {
        for (int l = 0; l < LINES_PER_ROW; ++l) {
            uint64_t packed = 0;

            for (int b = 0; b < 8; ++b) {
                uint64_t byte = uint8_t(data[r * COLS + l * 8 + b]);
                packed |= (byte << (8 * b)); // little-endian
            }

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
        cerr << "Usage: " << argv[0] << " <input_fp32.mem> <output_int8.mem>\n";
        return 1;
    }

    string input = argv[1];
    string output = argv[2];

    cout << "Reading: " << input << "\n";
    auto fp32 = read_fp32_mem(input);

    cout << "Quantizing to int8...\n";
    auto int8data = quantize_fp32_to_int8(fp32);

    cout << "Writing: " << output << "\n";
    write_int8_mem(int8data, output);

    cout << "Done.\n";
    return 0;
}
