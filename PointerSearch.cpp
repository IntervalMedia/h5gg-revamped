#include "PointerSearch.h"

#include <algorithm>
#include <cstring>
#include <limits>

namespace {

constexpr uint64_t PointerWidth = sizeof(uint64_t);
constexpr size_t MaximumChunkBytes = 1024 * 1024;

bool alignPointerAddress(uint64_t address, uint64_t& aligned) {
    constexpr uint64_t mask = PointerWidth - 1;
    if(address > std::numeric_limits<uint64_t>::max() - mask) return false;
    aligned = (address + mask) & ~mask;
    return true;
}

} // namespace

std::vector<std::pair<uint64_t, uint64_t>> JJFindExactPointers(
    uint64_t targetAddress,
    uint64_t rangeStart,
    uint64_t rangeEnd,
    std::vector<JJPointerSearchRegion> regions,
    JJMemoryReader& reader,
    const JJPointerSearchOptions& options) {
    std::vector<std::pair<uint64_t, uint64_t>> results;
    if(rangeStart >= rangeEnd || options.maxResults == 0 ||
       options.maxScannedBytes < PointerWidth || options.chunkBytes < PointerWidth) {
        return results;
    }

    size_t chunkBytes = std::min(options.chunkBytes, MaximumChunkBytes);
    chunkBytes -= chunkBytes % PointerWidth;
    if(chunkBytes == 0) return results;
    std::vector<uint8_t> buffer(chunkBytes);
    std::sort(regions.begin(), regions.end(),
              [](const JJPointerSearchRegion& left, const JJPointerSearchRegion& right) {
        return left.base < right.base;
    });

    uint64_t scannedBytes = 0;
    for(const JJPointerSearchRegion& region : regions) {
        if(region.size == 0 || region.base >= rangeEnd) continue;
        uint64_t regionEnd = region.size > std::numeric_limits<uint64_t>::max() - region.base
            ? std::numeric_limits<uint64_t>::max()
            : region.base + region.size;
        if(regionEnd <= rangeStart) continue;

        uint64_t cursor = 0;
        if(!alignPointerAddress(std::max(region.base, rangeStart), cursor)) continue;
        uint64_t scanEnd = std::min(regionEnd, rangeEnd);
        while(cursor < scanEnd && scannedBytes < options.maxScannedBytes) {
            uint64_t available = scanEnd - cursor;
            uint64_t budget = options.maxScannedBytes - scannedBytes;
            uint64_t requestValue = std::min<uint64_t>(available, chunkBytes);
            requestValue = std::min(requestValue, budget);
            requestValue -= requestValue % PointerWidth;
            if(requestValue < PointerWidth) break;

            size_t requestLength = static_cast<size_t>(requestValue);
            size_t bytesRead = reader.readBytes(buffer.data(), cursor, requestLength);
            scannedBytes += requestValue;
            size_t pointerCount = bytesRead / sizeof(uint64_t);
            for(size_t index = 0; index < pointerCount; index++) {
                uint64_t value = 0;
                std::memcpy(&value, buffer.data() + index * sizeof(uint64_t), sizeof(value));
                if(value == targetAddress) {
                    results.emplace_back(cursor + index * sizeof(uint64_t), value);
                    if(results.size() >= options.maxResults) return results;
                }
            }
            cursor += requestValue;
        }
        if(scannedBytes >= options.maxScannedBytes) break;
    }
    return results;
}
