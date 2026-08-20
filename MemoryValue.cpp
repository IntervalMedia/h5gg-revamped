#include "MemoryValue.h"

#include <cerrno>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <string>
#include <type_traits>
#include <utility>

const int JJ_Search_Type_Len[] = {0, 8, 8, 8, 4, 4, 4, 2, 2, 1, 1};

static const char* const JJ_Search_Type_Names[] = {
    "", "F64", "U64", "I64", "F32", "U32",
    "I32", "U16", "I16", "U8", "I8",
};

int JJTypeFromName(const char* name) {
    if(!name) return JJ_Search_Type_Error;
    for(int type = JJ_Search_Type_Double; type < JJ_Search_Type_Max; type++) {
        if(std::strcmp(name, JJ_Search_Type_Names[type]) == 0) return type;
    }
    return JJ_Search_Type_Error;
}

const char* JJTypeName(int type) {
    if(type <= JJ_Search_Type_Error || type >= JJ_Search_Type_Max) return "";
    return JJ_Search_Type_Names[type];
}

bool JJParseNonnegativeFloat(const char* text, float& output) {
    if(!text || text[0] == '\0' ||
       std::isspace(static_cast<unsigned char>(text[0]))) {
        return false;
    }

    char* end = nullptr;
    errno = 0;
    float value = std::strtof(text, &end);
    if(!end || *end != '\0' || errno == ERANGE ||
       !std::isfinite(value) || value < 0) {
        return false;
    }
    output = value;
    return true;
}

static std::string trimSearchToken(const std::string& token) {
    size_t start = 0;
    while(start < token.size() &&
          std::isspace(static_cast<unsigned char>(token[start]))) {
        start++;
    }
    size_t end = token.size();
    while(end > start &&
          std::isspace(static_cast<unsigned char>(token[end - 1]))) {
        end--;
    }
    return token.substr(start, end - start);
}

bool JJParseSearchExpression(const char* text,
                             int type,
                             std::vector<JJSearchValue>& values) {
    values.clear();
    if(!text || type <= JJ_Search_Type_Error || type >= JJ_Search_Type_Max) {
        return false;
    }

    std::vector<JJSearchValue> parsed;
    std::string expression(text);
    size_t start = 0;
    while(start <= expression.size()) {
        size_t comma = expression.find(',', start);
        size_t end = comma == std::string::npos ? expression.size() : comma;
        std::string token = trimSearchToken(expression.substr(start, end - start));
        if(token.empty()) return false;

        const std::string wideTilde = "\xEF\xBD\x9E";
        size_t separator = token.find('~');
        size_t separatorLength = 1;
        size_t wideSeparator = token.find(wideTilde);
        if(separator != std::string::npos && wideSeparator != std::string::npos) {
            return false;
        }
        if(separator == std::string::npos) {
            separator = wideSeparator;
            separatorLength = wideTilde.size();
        }

        JJSearchValue value = {};
        int length = JJ_Search_Type_Len[type];
        if(separator == std::string::npos) {
            if(!JJParseValue(token.c_str(), type, value.data())) return false;
            std::memcpy(value.data() + length, value.data(), length);
        } else {
            if(token.find('~', separator + 1) != std::string::npos ||
               token.find(wideTilde, separator + separatorLength) != std::string::npos) {
                return false;
            }
            std::string lower = trimSearchToken(token.substr(0, separator));
            std::string upper = trimSearchToken(
                token.substr(separator + separatorLength));
            if(lower.empty() || upper.empty() ||
               !JJParseValue(lower.c_str(), type, value.data()) ||
               !JJParseValue(upper.c_str(), type, value.data() + length) ||
               JJValueMatchesFilter(value.data() + length, value.data(),
                                    type, JJ_Filter_Less)) {
                return false;
            }
        }
        parsed.push_back(value);

        if(comma == std::string::npos) break;
        start = comma + 1;
    }

    if(parsed.empty()) return false;
    values = std::move(parsed);
    return true;
}

template<typename T>
static bool searchValueMatches(const uint8_t current[8],
                               const JJSearchValue& value,
                               int length,
                               float tolerance) {
    T currentValue;
    T lower;
    T upper;
    std::memcpy(&currentValue, current, sizeof(T));
    std::memcpy(&lower, value.data(), sizeof(T));
    std::memcpy(&upper, value.data() + length, sizeof(T));
    if constexpr (std::is_floating_point_v<T>) {
        lower -= tolerance;
        upper += tolerance;
    }
    return currentValue >= lower && currentValue <= upper;
}

bool JJSearchValueMatchesAny(const uint8_t current[8],
                             const std::vector<JJSearchValue>& values,
                             int type,
                             float tolerance) {
    if(!current || values.empty() || type <= JJ_Search_Type_Error ||
       type >= JJ_Search_Type_Max || tolerance < 0) {
        return false;
    }

    int length = JJ_Search_Type_Len[type];
    for(const JJSearchValue& value : values) {
        bool matches = false;
        switch(type) {
            case JJ_Search_Type_Double:
                matches = searchValueMatches<double>(current, value, length, tolerance); break;
            case JJ_Search_Type_ULong:
                matches = searchValueMatches<uint64_t>(current, value, length, tolerance); break;
            case JJ_Search_Type_SLong:
                matches = searchValueMatches<int64_t>(current, value, length, tolerance); break;
            case JJ_Search_Type_Float:
                matches = searchValueMatches<float>(current, value, length, tolerance); break;
            case JJ_Search_Type_UInt:
                matches = searchValueMatches<uint32_t>(current, value, length, tolerance); break;
            case JJ_Search_Type_SInt:
                matches = searchValueMatches<int32_t>(current, value, length, tolerance); break;
            case JJ_Search_Type_UShort:
                matches = searchValueMatches<uint16_t>(current, value, length, tolerance); break;
            case JJ_Search_Type_SShort:
                matches = searchValueMatches<int16_t>(current, value, length, tolerance); break;
            case JJ_Search_Type_UByte:
                matches = searchValueMatches<uint8_t>(current, value, length, tolerance); break;
            case JJ_Search_Type_SByte:
                matches = searchValueMatches<int8_t>(current, value, length, tolerance); break;
            default:
                break;
        }
        if(matches) return true;
    }
    return false;
}

template<typename T>
static void storeValue(uint8_t output[8], T value) {
    std::memset(output, 0, 8);
    std::memcpy(output, &value, sizeof(value));
}

template<typename T>
static T loadValue(const uint8_t input[8]) {
    T value;
    std::memcpy(&value, input, sizeof(value));
    return value;
}

template<typename T>
static bool parseSigned(const char* text, uint8_t output[8]) {
    char* end = nullptr;
    errno = 0;
    long long value = std::strtoll(text, &end, 10);
    if(!text || text[0] == '\0' || !end || *end != '\0' || errno == ERANGE ||
       value < std::numeric_limits<T>::min() ||
       value > std::numeric_limits<T>::max()) {
        return false;
    }
    storeValue(output, static_cast<T>(value));
    return true;
}

template<typename T>
static bool parseUnsigned(const char* text, uint8_t output[8]) {
    if(!text || text[0] == '\0' || text[0] == '-') {
        return false;
    }

    char* end = nullptr;
    errno = 0;
    unsigned long long value = std::strtoull(text, &end, 10);
    if(!end || *end != '\0' || errno == ERANGE ||
       value > std::numeric_limits<T>::max()) {
        return false;
    }
    storeValue(output, static_cast<T>(value));
    return true;
}

bool JJParseValue(const char* text, int type, uint8_t output[8]) {
    if(!text || !output || type <= JJ_Search_Type_Error || type >= JJ_Search_Type_Max) {
        return false;
    }

    switch(type) {
        case JJ_Search_Type_Double: {
            char* end = nullptr;
            errno = 0;
            double value = std::strtod(text, &end);
            if(text[0] == '\0' || !end || *end != '\0' || errno == ERANGE ||
               !std::isfinite(value)) {
                return false;
            }
            storeValue(output, value);
            return true;
        }
        case JJ_Search_Type_ULong:
            return parseUnsigned<uint64_t>(text, output);
        case JJ_Search_Type_SLong:
            return parseSigned<int64_t>(text, output);
        case JJ_Search_Type_Float: {
            char* end = nullptr;
            errno = 0;
            float value = std::strtof(text, &end);
            if(text[0] == '\0' || !end || *end != '\0' || errno == ERANGE ||
               !std::isfinite(value)) {
                return false;
            }
            storeValue(output, value);
            return true;
        }
        case JJ_Search_Type_UInt:
            return parseUnsigned<uint32_t>(text, output);
        case JJ_Search_Type_SInt:
            return parseSigned<int32_t>(text, output);
        case JJ_Search_Type_UShort:
            return parseUnsigned<uint16_t>(text, output);
        case JJ_Search_Type_SShort:
            return parseSigned<int16_t>(text, output);
        case JJ_Search_Type_UByte:
            return parseUnsigned<uint8_t>(text, output);
        case JJ_Search_Type_SByte:
            return parseSigned<int8_t>(text, output);
        default:
            return false;
    }
}

bool JJParseAddress(const char* text, int base, uint64_t& output) {
    if(!text || text[0] == '\0' || (base != 10 && base != 16) ||
       text[0] == '-' || text[0] == '+' ||
       std::isspace(static_cast<unsigned char>(text[0]))) {
        return false;
    }

    char* end = nullptr;
    errno = 0;
    unsigned long long value = std::strtoull(text, &end, base);
    if(!end || *end != '\0' || errno == ERANGE) {
        return false;
    }

    output = static_cast<uint64_t>(value);
    return true;
}

template<typename T>
static bool compareValues(const uint8_t current[8],
                          const uint8_t target[8],
                          int mode) {
    T currentValue = loadValue<T>(current);
    T targetValue = loadValue<T>(target);
    switch(mode) {
        case JJ_Filter_Equal:
            return currentValue == targetValue;
        case JJ_Filter_Greater:
            return currentValue > targetValue;
        case JJ_Filter_Less:
            return currentValue < targetValue;
        default:
            return false;
    }
}

bool JJValueMatchesFilter(const uint8_t current[8],
                          const uint8_t target[8],
                          int type,
                          int mode) {
    if(!current || !target) {
        return false;
    }

    switch(type) {
        case JJ_Search_Type_Double:
            return compareValues<double>(current, target, mode);
        case JJ_Search_Type_ULong:
            return compareValues<uint64_t>(current, target, mode);
        case JJ_Search_Type_SLong:
            return compareValues<int64_t>(current, target, mode);
        case JJ_Search_Type_Float:
            return compareValues<float>(current, target, mode);
        case JJ_Search_Type_UInt:
            return compareValues<uint32_t>(current, target, mode);
        case JJ_Search_Type_SInt:
            return compareValues<int32_t>(current, target, mode);
        case JJ_Search_Type_UShort:
            return compareValues<uint16_t>(current, target, mode);
        case JJ_Search_Type_SShort:
            return compareValues<int16_t>(current, target, mode);
        case JJ_Search_Type_UByte:
            return compareValues<uint8_t>(current, target, mode);
        case JJ_Search_Type_SByte:
            return compareValues<int8_t>(current, target, mode);
        default:
            return false;
    }
}

static int hexDigitValue(char value) {
    if(value >= '0' && value <= '9') return value - '0';
    if(value >= 'a' && value <= 'f') return value - 'a' + 10;
    if(value >= 'A' && value <= 'F') return value - 'A' + 10;
    return -1;
}

bool JJParseHexPattern(const char* text, std::vector<uint8_t>& bytes) {
    JJHexPattern pattern;
    if(!JJParseMaskedHexPattern(text, pattern)) {
        bytes.clear();
        return false;
    }

    for(uint8_t mask : pattern.masks) {
        if(mask != 0xFF) {
            bytes.clear();
            return false;
        }
    }
    bytes = std::move(pattern.values);
    return true;
}

bool JJParseMaskedHexPattern(const char* text, JJHexPattern& pattern) {
    pattern.values.clear();
    pattern.masks.clear();
    if(!text) return false;

    std::vector<char> digits;
    for(const char* current = text; *current; current++) {
        unsigned char value = static_cast<unsigned char>(*current);
        if(std::isspace(value)) continue;
        if(!std::isxdigit(value) && value != '?') return false;
        digits.push_back(*current);
    }

    if(digits.empty() || digits.size() % 2 != 0) return false;

    pattern.values.reserve(digits.size() / 2);
    pattern.masks.reserve(digits.size() / 2);
    for(size_t index = 0; index < digits.size(); index += 2) {
        int high = digits[index] == '?' ? 0 : hexDigitValue(digits[index]);
        int low = digits[index + 1] == '?' ? 0 : hexDigitValue(digits[index + 1]);
        uint8_t mask = (digits[index] == '?' ? 0 : 0xF0) |
                       (digits[index + 1] == '?' ? 0 : 0x0F);
        pattern.values.push_back(static_cast<uint8_t>((high << 4) | low));
        pattern.masks.push_back(mask);
    }
    return true;
}

bool JJHexPatternMatches(const uint8_t* bytes, size_t length, const JJHexPattern& pattern) {
    if(!bytes || pattern.empty() || pattern.values.size() != pattern.masks.size() ||
       length < pattern.size()) {
        return false;
    }

    for(size_t index = 0; index < pattern.size(); index++) {
        if((bytes[index] & pattern.masks[index]) !=
           (pattern.values[index] & pattern.masks[index])) {
            return false;
        }
    }
    return true;
}
