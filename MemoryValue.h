#ifndef H5GG_MEMORY_VALUE_H
#define H5GG_MEMORY_VALUE_H

#include <cstdint>
#include <vector>

enum JJ_Search_Type {
    JJ_Search_Type_Error,

    JJ_Search_Type_Double,
    JJ_Search_Type_ULong,
    JJ_Search_Type_SLong,
    JJ_Search_Type_Float,
    JJ_Search_Type_UInt,
    JJ_Search_Type_SInt,
    JJ_Search_Type_UShort,
    JJ_Search_Type_SShort,
    JJ_Search_Type_UByte,
    JJ_Search_Type_SByte,

    JJ_Search_Type_Max,
};

enum JJ_Filter_Mode {
    JJ_Filter_Equal = 0,
    JJ_Filter_Greater = 2,
    JJ_Filter_Less = 3,
};

extern const int JJ_Search_Type_Len[];

bool JJParseValue(const char* text, int type, uint8_t output[8]);
bool JJParseAddress(const char* text, int base, uint64_t& output);
bool JJValueMatchesFilter(const uint8_t current[8],
                          const uint8_t target[8],
                          int type,
                          int mode);
bool JJParseHexPattern(const char* text, std::vector<uint8_t>& bytes);

#endif
