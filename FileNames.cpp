#include "FileNames.h"

#include <cstddef>
#include <cctype>
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

bool H5GGNormalizeScriptFileName(const char* name, std::string& normalized) {
    normalized.clear();
    if(!H5GGIsSafeFileName(name)) return false;

    normalized = name;
    std::string lowercase = normalized;
    for(char& value : lowercase) {
        value = static_cast<char>(std::tolower(static_cast<unsigned char>(value)));
    }

    if(lowercase.size() >= 3 &&
       lowercase.compare(lowercase.size() - 3, 3, ".js") == 0) {
        return true;
    }
    if(lowercase.size() >= 5 &&
       lowercase.compare(lowercase.size() - 5, 5, ".html") == 0) {
        return true;
    }
    if(normalized.find('.') != std::string::npos || normalized.size() > 252) {
        normalized.clear();
        return false;
    }

    normalized += ".js";
    return true;
}
