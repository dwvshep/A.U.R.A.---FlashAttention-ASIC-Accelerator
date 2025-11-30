#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <sstream>
#include <iomanip>
#include <cmath>
#include <algorithm>
#include <cstdint>
#include <stdio.h>
#include <string.h>

using namespace std;

static constexpr int ROWS = 512;      // number of matrix rows
static constexpr int COLS = 64;       // number of datapoints per row
static constexpr int LINES_PER_ROW = COLS / 8; // 8 lines per row
static constexpr double SCALE = 1.0 / sqrt((double)COLS);
static constexpr double Q_FACTOR = 128;

// ---------------------------
// Function to read FP32 mem file
// Each FP32 is stored as 8 hex chars per value (big-endian)
// ---------------------------
std::vector<float> read_fp32_mem(const std::string &filename) {
    std::ifstream fin(filename);
    std::vector<float> data;
    std::string line;
    while (std::getline(fin, line)) {
        // remove whitespace
        line.erase(std::remove_if(line.begin(), line.end(), ::isspace), line.end());
        // read 8 hex chars at a time
        for (size_t i = 0; i + 8 <= line.size(); i += 8) {
            std::string hexval_be = line.substr(i, 8); // big-endian as text

            // --- Convert to little-endian byte order ---
            std::string hexval_le =
                hexval_be.substr(6, 2) +
                hexval_be.substr(4, 2) +
                hexval_be.substr(2, 2) +
                hexval_be.substr(0, 2);

            // parse LE hex into uint32
            uint32_t bits = std::stoul(hexval_le, nullptr, 16);

            float f;
            memcpy(&f, &bits, sizeof(float));  // safe reinterpretation
            data.push_back(f);
        }
    }
    return data;
}

// ---------------------------
// Quantize FP32 -> int8 using symmetric quantization
// ---------------------------
std::vector<int8_t> quantize_fp32_to_int8(const std::vector<float>& data, float &scale_out) {
    
    // float max_abs = 0.0f;
    // for (float x : data) max_abs = std::max(max_abs, std::fabs(x));
    // scale_out = max_abs / 127.0f;

    std::vector<int8_t> result(data.size());
    for (size_t i = 0; i < data.size(); i++) {
        long long q = (long long)lround(data[i] * 128.0);
        if (q > 127) q = 127;
        if (q < -128) q = -128;
        result[i] = static_cast<int8_t>(q);
    }
    return result;
}

// ---------------------------
// Write int8 mem file
// Each row: 8 datapoints = 64 bits
// Print each byte as two-character hex
// ---------------------------


//float 0.708990 -> *128 = 91(rounded to nearest int) = 01011011 = x5B --> interpreted as a Q0.7 = 91/128 = 0.710


// void write_int8_mem(const std::vector<int8_t>& data, const std::string &filename, size_t row_length = 8){
//     std::ofstream fout(filename);

//     for (int r = 0; r < ROWS; ++r) {
//         for (int l = 0; l < LINES_PER_ROW; ++l) {

//             uint64_t packed = 0;
//             for (int b = 0; b < row_length; ++b) {
//                 uint64_t byte = uint64_t(uint8_t(data[r*COLS + l*row_length + b]));
//                 packed |= (byte & 0xFFULL) << (8 * (row_length - 1 - b));  // MSB-first
//             }

//             std::ostringstream ss;
//             ss << std::uppercase << std::hex
//                << std::setw(16) << std::setfill('0') << packed;

//             fout << ss.str() << "\n";
//         }
//     }
// }

void write_int8_mem(const std::vector<int8_t>& data, const std::string &filename, size_t row_length = 8) {
    std::ofstream fout(filename);
    // for (size_t i = 0; i < data.size(); i++) {
    //     fout << std::hex << std::uppercase << std::setw(2) << std::setfill('0') << (int)data[i];
    //     if ((i+1) % row_length == 0) fout << "\n";
    // }
    for (int r = 0; r < ROWS; ++r) {
        int base = 0;
        for (int l = 0; l < LINES_PER_ROW; ++l) {
            uint64_t packed = 0;
            for (int b = 0; b < row_length; ++b) {
                uint64_t byte = (uint64_t(int8_t(data[r*LINES_PER_ROW*row_length + l*row_length + b])));
                packed |= (byte & 0xFFULL) << (8*b); // LSB-first
            }
            // print as 16 hex chars uppercase
            std::ostringstream ss;
            ss << std::uppercase << std::hex << std::setfill('0') << std::setw(16) << packed;
            fout << ss.str() << '\n';
        }
    }
}

// ---------------------------
// Main pipeline
// ---------------------------
int main() {
    struct FilePair { std::string fp32; std::string int8; };
    std::vector<FilePair> files = {
        {"../mem/Q_32.mem", "../mem/Q_8.mem"},
        {"../mem/K_32.mem", "../mem/K_8.mem"},
        {"../mem/V_32.mem", "../mem/V_8.mem"}
    };

    for (auto &fp : files) {
        std::cout << "Processing " << fp.fp32 << " ..." << std::endl;
        auto data_fp32 = read_fp32_mem(fp.fp32);
        //printf("%f   ", data_fp32[0]);

        float scale;
        auto data_int8 = quantize_fp32_to_int8(data_fp32, scale);
        std::cout << "Scale factor used: " << scale << std::endl;

        printf("%d\n", data_int8[0]);
        write_int8_mem(data_int8, fp.int8);
        std::cout << "Written " << fp.int8 << std::endl;
    }

    std::cout << "All files processed!" << std::endl;
    return 0;
}