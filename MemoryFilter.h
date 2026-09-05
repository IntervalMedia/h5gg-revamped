#ifndef H5GG_MEMORY_FILTER_H
#define H5GG_MEMORY_FILTER_H

#include "MemoryResults.h"
#include "MemoryReader.h"
#include "MemoryValue.h"

#include <cstddef>
#include <cstdint>

size_t JJFilterResultSet(Result& results,
                         const char* value,
                         int type,
                         int mode,
                         JJMemoryReader& reader);
size_t JJFilterHexResultSet(Result& results,
                            const JJHexPattern& pattern,
                            JJMemoryReader& reader,
                            uint64_t rangeStart,
                            uint64_t rangeEnd);

#endif
