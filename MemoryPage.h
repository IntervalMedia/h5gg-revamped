#ifndef H5GG_MEMORY_PAGE_H
#define H5GG_MEMORY_PAGE_H

#include "MemoryReader.h"

#include <cstddef>
#include <cstdint>
#include <vector>

struct JJMemoryPage {
    uint64_t address = 0;
    std::vector<int16_t> bytes;

    size_t readableCount() const;
    bool complete() const;
};

JJMemoryPage JJReadMemoryPage(uint64_t address,
                              size_t length,
                              JJMemoryReader& reader,
                              size_t chunkSize = 16);

#endif
