#include <iostream>
#include <fstream>
#include <iomanip>
#include <random>
#include <filesystem>

void generate_mem(const std::string &filename, int rows) {
    std::ofstream outfile(filename);
    if (!outfile) {
        std::cerr << "Error: could not create file " << filename << "\n";
        return;
    }

    std::random_device rd;
    std::mt19937_64 gen(rd());
    std::uniform_int_distribution<uint64_t> dist(0, UINT64_MAX);

    for (int i = 0; i < rows; ++i) {
        uint64_t value = dist(gen);
        outfile << std::uppercase
                << std::hex << std::setw(16) << std::setfill('0')
                << value << std::endl;
    }

    outfile.close();
    std::cout << "Generated " << filename << " with " << rows << " rows.\n";
}

int main() {
    const int ROWS = 512;

    std::filesystem::create_directories("output");

    generate_mem("output/Q.mem", ROWS);
    generate_mem("output/K.mem", ROWS);
    generate_mem("output/V.mem", ROWS);

    return 0;
}