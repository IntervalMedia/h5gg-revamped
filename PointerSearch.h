#ifndef H5GG_POINTER_SEARCH_H
#define H5GG_POINTER_SEARCH_H

#include "MemoryReader.h"

#include <cstddef>
#include <cstdint>
#include <utility>
#include <vector>

struct JJPointerSearchRegion {
    uint64_t base = 0;
    uint64_t size = 0;
};

struct JJPointerSearchOptions {
    size_t maxResults = 4096;
    uint64_t maxScannedBytes = 512ULL * 1024ULL * 1024ULL;
    size_t chunkBytes = 64 * 1024;
};

std::vector<std::pair<uint64_t, uint64_t>> JJFindExactPointers(
    uint64_t targetAddress,
    uint64_t rangeStart,
    uint64_t rangeEnd,
    std::vector<JJPointerSearchRegion> regions,
    JJMemoryReader& reader,
    const JJPointerSearchOptions& options = {});

#endif
