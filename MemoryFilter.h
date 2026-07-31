#ifndef H5GG_MEMORY_FILTER_H
#define H5GG_MEMORY_FILTER_H

#include "MemoryResults.h"

#include <cstddef>
#include <cstdint>
#include <functional>

using JJMemoryReader = std::function<bool(void* output, uint64_t address, size_t length)>;

size_t JJFilterResultSet(Result& results,
                         const char* value,
                         int type,
                         int mode,
                         const JJMemoryReader& reader);

#endif
