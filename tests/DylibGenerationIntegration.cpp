#include "../DylibTemplate.h"

#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <vector>

static std::vector<uint8_t> readFile(const char* path) {
    std::ifstream input(path, std::ios::binary);
    return std::vector<uint8_t>(
        std::istreambuf_iterator<char>(input),
        std::istreambuf_iterator<char>());
}

int main(int argc, char** argv) {
    if(argc != 7) {
        std::cerr << "usage: tool input icon-template menu-template icon menu output\n";
        return 2;
    }

    std::vector<uint8_t> binary = readFile(argv[1]);
    std::vector<uint8_t> iconTemplate = readFile(argv[2]);
    std::vector<uint8_t> menuTemplate = readFile(argv[3]);
    std::vector<uint8_t> icon = readFile(argv[4]);
    std::vector<uint8_t> menu = readFile(argv[5]);
    if(binary.empty() || iconTemplate.empty() || menuTemplate.empty() ||
       icon.empty() || menu.empty()) {
        std::cerr << "unable to read integration fixture\n";
        return 3;
    }

    size_t iconCount = H5GGReplaceAllTemplates(binary, iconTemplate, icon);
    size_t menuCount = H5GGReplaceAllTemplates(binary, menuTemplate, menu);
    if(iconCount == 0 || iconCount != menuCount ||
       H5GGReplaceAllTemplates(binary, iconTemplate, icon) != 0 ||
       H5GGReplaceAllTemplates(binary, menuTemplate, menu) != 0) {
        std::cerr << "template replacement count mismatch: "
                  << iconCount << "/" << menuCount << "\n";
        return 4;
    }

    std::ofstream output(argv[6], std::ios::binary | std::ios::trunc);
    output.write(reinterpret_cast<const char*>(binary.data()),
                 static_cast<std::streamsize>(binary.size()));
    if(!output) return 5;

    std::cout << "replaced " << iconCount << " architecture templates\n";
    return 0;
}
