#include <bits/stdc++.h>
using namespace std;

static constexpr int ROWS = 512;
static constexpr int COLS = 64;

// Each line = 8 bytes = 64 bits = 4 × int16 elements
static constexpr int ELTS_PER_LINE = 4;
static constexpr int LINES_PER_ROW = COLS / ELTS_PER_LINE;

// ----- Same thresholds as before -----
static constexpr double THRESHOLD_MAE = 3.0;
static constexpr double THRESHOLD_RMSE = 5.0;
static constexpr int THRESHOLD_MAX_ERROR = 15;
static constexpr double THRESHOLD_REL_ERROR = 0.1;
static constexpr double THRESHOLD_TOP1_MATCH = 0.95;

// ======================================================
// Read 16-bit packed .mem file → ROWS × COLS matrix
// ======================================================
vector<vector<int16_t>> read_mem_matrix(const string &filename) {
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
        ss << hex << tok;
        ss >> v;

        lines.push_back(v);
    }

    if ((int)lines.size() != ROWS * LINES_PER_ROW)
        throw runtime_error("Incorrect line count");

    vector<vector<int16_t>> M(ROWS, vector<int16_t>(COLS));

    for (int r = 0; r < ROWS; ++r) {
        int base_line = r * LINES_PER_ROW;
        int out_index = 0;

        for (int l = 0; l < LINES_PER_ROW; ++l) {
            uint64_t val = lines[base_line + l];

            // unpack 4 × int16_t per 64-bit line (little-endian)
            for (int e = 0; e < ELTS_PER_LINE; ++e) {
                uint16_t raw = (val >> (16 * e)) & 0xFFFF;
                int16_t signed_val = static_cast<int16_t>(raw);
                M[r][out_index++] = signed_val;
            }
        }
    }

    return M;
}

// ======================================================
// Compute precision/error metrics
// ======================================================
void compare_outputs(const vector<vector<int16_t>> &ref,
                     const vector<vector<int16_t>> &asic)
{
    if (ref.size() != asic.size() || ref[0].size() != asic[0].size())
        throw runtime_error("Matrix dimensions do not match");

    double mae = 0.0;
    double rmse = 0.0;
    int max_abs_error = 0;
    int total_elements = ROWS * COLS;

    for (int r = 0; r < ROWS; ++r) {
        for (int c = 0; c < COLS; ++c) {
            int a = asic[r][c];
            int f = ref[r][c];
            int err = abs(a - f);
            mae += err;
            rmse += err * err;
            max_abs_error = max(max_abs_error, err);
        }
    }

    mae /= total_elements;
    rmse = sqrt(rmse / total_elements);

    // relative error
    double sum_rel = 0.0;
    int count_rel = 0;

    for (int r = 0; r < ROWS; ++r) {
        for (int c = 0; c < COLS; ++c) {
            int f = ref[r][c];
            if (f != 0) {
                int16_t a = asic[r][c];
                sum_rel += abs(a - f) / abs(double(f)); //max(abs(f), abs(a));
                count_rel++;
            }
        }
    }

    double mean_rel_error = (count_rel > 0) ? (sum_rel / count_rel) : 0.0;

    // top-1 match
    int top1_match = 0;
    for (int r = 0; r < ROWS; ++r) {
        int ref_idx = max_element(ref[r].begin(), ref[r].end()) - ref[r].begin();
        int asic_idx = max_element(asic[r].begin(), asic[r].end()) - asic[r].begin();
        if (ref_idx == asic_idx) top1_match++;
    }
    double top1_ratio = top1_match / double(ROWS);

    // ---- Print summary ----
    cout << "===== Comparison Metrics =====\n";
    cout << "MAE            : " << mae
         << "  --> " << ((mae <= THRESHOLD_MAE) ? "PASS" : "FAIL") << "\n";

    cout << "RMSE           : " << rmse
         << "  --> " << ((rmse <= THRESHOLD_RMSE) ? "PASS" : "FAIL") << "\n";

    cout << "Max abs error  : " << max_abs_error
         << "  --> " << ((max_abs_error <= THRESHOLD_MAX_ERROR) ? "PASS" : "FAIL") << "\n";

    cout << "Mean rel error : " << mean_rel_error
         << "  --> " << ((mean_rel_error <= THRESHOLD_REL_ERROR) ? "PASS" : "FAIL") << "\n";

    cout << "Top-1 match    : " << top1_match << " / " << ROWS
         << " (" << (100.0 * top1_ratio) << "%)"
         << "  --> " << ((top1_ratio >= THRESHOLD_TOP1_MATCH) ? "PASS" : "FAIL") << "\n";
}

int main(int argc, char** argv) {
    if (argc != 3) {
        cerr << "Usage: " << argv[0] << " reference.mem asic_output.mem\n";
        return 1;
    }

    auto ref  = read_mem_matrix(argv[1]);
    auto asic = read_mem_matrix(argv[2]);

    compare_outputs(ref, asic);
}
