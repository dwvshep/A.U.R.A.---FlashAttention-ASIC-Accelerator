#include <bits/stdc++.h>
using namespace std;

static constexpr int ROWS = 512;
static constexpr int COLS = 64;
static constexpr int LINES_PER_ROW = COLS / 8;

// Acceptable thresholds for 8-bit fixed-point attention ASIC
static constexpr double THRESHOLD_MAE = 3.0;
static constexpr double THRESHOLD_RMSE = 5.0;
static constexpr int THRESHOLD_MAX_ERROR = 15;
static constexpr double THRESHOLD_REL_ERROR = 0.1; // 10%
static constexpr double THRESHOLD_TOP1_MATCH = 0.95; // 95%

// read a packed mem file into ROWS x COLS uint8 matrix
vector<vector<uint8_t>> read_mem_matrix(const string &filename) {
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

// compute precision/error metrics
void compare_outputs(const vector<vector<uint8_t>> &ref,
                     const vector<vector<uint8_t>> &asic) {
    if (ref.size() != asic.size() || ref[0].size() != asic[0].size())
        throw runtime_error("Matrix dimensions do not match");

    double mae = 0.0;
    double rmse = 0.0;
    int max_abs_error = 0;
    int total_elements = 0;

    for (int r = 0; r < ROWS; ++r) {
        for (int c = 0; c < COLS; ++c) {
            int a = asic[r][c];
            int f = ref[r][c];
            int err = abs(a - f);
            mae += err;
            rmse += err * err;
            max_abs_error = max(max_abs_error, err);
            total_elements++;
        }
    }

    mae /= total_elements;
    rmse = sqrt(rmse / total_elements);

    // Relative error
    double sum_rel = 0.0;
    int count_rel = 0;
    for (int r = 0; r < ROWS; ++r) {
        for (int c = 0; c < COLS; ++c) {
            int f = ref[r][c];
            if (f != 0) {
                sum_rel += abs((int)asic[r][c] - f) / (double)f;
                count_rel++;
            }
        }
    }
    double mean_rel_error = (count_rel > 0) ? (sum_rel / count_rel) : 0.0;

    // Top-1 match
    int top1_match = 0;
    for (int r = 0; r < ROWS; ++r) {
        auto ref_max = max_element(ref[r].begin(), ref[r].end()) - ref[r].begin();
        auto asic_max = max_element(asic[r].begin(), asic[r].end()) - asic[r].begin();
        if (ref_max == asic_max) top1_match++;
    }
    double top1_ratio = top1_match / double(ROWS);

    // Print metrics and PASS/FAIL
    cout << "===== Comparison Metrics =====\n";
    cout << "Total elements: " << total_elements << "\n";

    cout << "MAE           : " << mae << "  --> " 
         << ((mae <= THRESHOLD_MAE) ? "PASS" : "FAIL") << "\n";

    cout << "RMSE          : " << rmse << "  --> " 
         << ((rmse <= THRESHOLD_RMSE) ? "PASS" : "FAIL") << "\n";

    cout << "Max abs error : " << max_abs_error << "  --> " 
         << ((max_abs_error <= THRESHOLD_MAX_ERROR) ? "PASS" : "FAIL") << "\n";

    cout << "Mean rel error: " << mean_rel_error << "  --> " 
         << ((mean_rel_error <= THRESHOLD_REL_ERROR) ? "PASS" : "FAIL") << "\n";

    cout << "Top-1 row match: " << top1_match << " / " << ROWS 
         << " (" << (100.0 * top1_ratio) << "%)  --> " 
         << ((top1_ratio >= THRESHOLD_TOP1_MATCH) ? "PASS" : "FAIL") << "\n";
}

int main(int argc, char** argv) {
    if (argc != 3) {
        cerr << "Usage: " << argv[0] << " reference.mem asic_output.mem\n";
        return 1;
    }

    string ref_file = argv[1];
    string asic_file = argv[2];

    auto ref = read_mem_matrix(ref_file);
    auto asic = read_mem_matrix(asic_file);

    compare_outputs(ref, asic);
}
