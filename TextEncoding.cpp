#include "TextEncoding.h"

#include <cstddef>
#include <cstdint>

bool H5GGIsValidUTF8(const std::string& text,
                     H5GGUTF8NullPolicy nullPolicy) {
    size_t index = 0;
    while(index < text.size()) {
        uint8_t first = static_cast<uint8_t>(text[index]);
        if(first <= 0x7F) {
            if(first == 0 && nullPolicy == H5GGUTF8NullPolicy::Reject) {
                return false;
            }
            index++;
            continue;
        }

        size_t continuationCount = 0;
        uint32_t codePoint = 0;
        uint32_t minimum = 0;
        if((first & 0xE0) == 0xC0) {
            continuationCount = 1;
            codePoint = first & 0x1F;
            minimum = 0x80;
        } else if((first & 0xF0) == 0xE0) {
            continuationCount = 2;
            codePoint = first & 0x0F;
            minimum = 0x800;
        } else if((first & 0xF8) == 0xF0) {
            continuationCount = 3;
            codePoint = first & 0x07;
            minimum = 0x10000;
        } else {
            return false;
        }

        if(index + continuationCount >= text.size()) return false;
        for(size_t offset = 1; offset <= continuationCount; offset++) {
            uint8_t continuation = static_cast<uint8_t>(text[index + offset]);
            if((continuation & 0xC0) != 0x80) return false;
            codePoint = (codePoint << 6) | (continuation & 0x3F);
        }
        if(codePoint < minimum || codePoint > 0x10FFFF ||
           (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
            return false;
        }
        index += continuationCount + 1;
    }
    return true;
}
