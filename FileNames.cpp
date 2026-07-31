#include "FileNames.h"

#include <cstddef>
#include <cstring>

bool H5GGIsSafeFileName(const char* name) {
    if(!name) {
        return false;
    }

    size_t length = std::strlen(name);
    if(length == 0 || length > 255 ||
       std::strcmp(name, ".") == 0 || std::strcmp(name, "..") == 0) {
        return false;
    }

    for(size_t index = 0; index < length; index++) {
        unsigned char value = static_cast<unsigned char>(name[index]);
        if(value < 0x20 || value == 0x7F ||
           value == '/' || value == '\\' || value == ':') {
            return false;
        }
    }
    return true;
}
