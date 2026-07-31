#include "DylibTemplate.h"

#include <algorithm>

size_t H5GGReplaceAllTemplates(std::vector<uint8_t>& binary,
                               const std::vector<uint8_t>& placeholder,
                               const std::vector<uint8_t>& payload) {
    if(binary.empty() || placeholder.empty() || payload.empty() ||
       payload.size() >= placeholder.size()) {
        return 0;
    }

    std::vector<uint8_t> replacement(placeholder.size(), 0);
    std::copy(payload.begin(), payload.end(), replacement.begin());

    size_t replacements = 0;
    auto cursor = binary.begin();
    while(cursor != binary.end()) {
        auto found = std::search(cursor, binary.end(),
                                 placeholder.begin(), placeholder.end());
        if(found == binary.end()) break;
        std::copy(replacement.begin(), replacement.end(), found);
        cursor = found + replacement.size();
        replacements++;
    }
    return replacements;
}
