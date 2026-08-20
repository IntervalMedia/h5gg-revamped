#include "MemoryReader.h"

#include "MemoryValue.h"

#include <algorithm>
#include <cstring>
#include <utility>

size_t JJMemoryReader::readBytes(void* output,
                                 uint64_t address,
                                 size_t length) {
    if(!output || length == 0) return 0;
    return std::min(performRead(output, address, length), length);
}

bool JJMemoryReader::readExact(void* output,
                               uint64_t address,
                               size_t length) {
    return length > 0 && readBytes(output, address, length) == length;
}

bool JJMemoryReader::readValue(void* output,
                               uint64_t address,
                               int type) {
    if(type <= JJ_Search_Type_Error || type >= JJ_Search_Type_Max) return false;
    return readExact(output, address, static_cast<size_t>(JJ_Search_Type_Len[type]));
}

JJCallbackMemoryReader::JJCallbackMemoryReader(JJMemoryReadCallback callback)
    : callback_(std::move(callback)) {}

size_t JJCallbackMemoryReader::performRead(void* output,
                                           uint64_t address,
                                           size_t length) {
    if(!callback_) return 0;
    return callback_(output, address, length);
}

JJBufferMemoryReader::JJBufferMemoryReader(uint64_t baseAddress,
                                           std::vector<uint8_t> bytes)
    : baseAddress_(baseAddress), bytes_(std::move(bytes)) {}

size_t JJBufferMemoryReader::performRead(void* output,
                                         uint64_t address,
                                         size_t length) {
    if(address < baseAddress_) return 0;
    uint64_t offsetValue = address - baseAddress_;
    if(offsetValue >= bytes_.size()) return 0;

    size_t offset = static_cast<size_t>(offsetValue);
    size_t readable = std::min(length, bytes_.size() - offset);
    std::memcpy(output, bytes_.data() + offset, readable);
    return readable;
}
