#include "../DylibBuilder.h"

#include <algorithm>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <spawn.h>
#include <string>
#include <sys/wait.h>
#include <vector>

extern char** environ;

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

    std::vector<uint8_t> iconTemplate = readFile(argv[2]);
    std::vector<uint8_t> menuTemplate = readFile(argv[3]);
    if(iconTemplate.empty() || menuTemplate.empty()) {
        std::cerr << "unable to read integration fixture\n";
        return 3;
    }

    DylibBuilder builder(
        std::move(iconTemplate), std::move(menuTemplate),
        [](const std::vector<uint8_t>& icon, std::string& error) {
            static const uint8_t pngSignature[] = {
                0x89, 'P', 'N', 'G', '\r', '\n', 0x1A, '\n',
            };
            if(icon.size() >= sizeof(pngSignature) &&
               std::equal(std::begin(pngSignature), std::end(pngSignature),
                          icon.begin())) {
                return true;
            }
            error = "integration icon is not PNG data";
            return false;
        },
        [](const std::string& path, std::string& error) {
            pid_t process = 0;
            char* arguments[] = {
                const_cast<char*>("ldid"),
                const_cast<char*>("-S"),
                const_cast<char*>(path.c_str()),
                nullptr,
            };
            int spawnResult = posix_spawnp(
                &process, "ldid", nullptr, nullptr, arguments, environ);
            if(spawnResult != 0) {
                error = "unable to start ldid";
                return false;
            }
            int status = 0;
            if(waitpid(process, &status, 0) < 0 || !WIFEXITED(status) ||
               WEXITSTATUS(status) != 0) {
                error = "ldid failed";
                return false;
            }
            return true;
        });

    H5GGDylibBuildResult result = builder.build({
        argv[1], argv[4], argv[5], argv[6],
    });
    if(!result.completed()) {
        std::cerr << "dylib build failed with status "
                  << static_cast<int>(result.status) << ": "
                  << result.detail << "\n";
        return 4;
    }

    std::cout << "replaced and signed " << result.architectureCount
              << " architecture templates\n";
    return 0;
}
