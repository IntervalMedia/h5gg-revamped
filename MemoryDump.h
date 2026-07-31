#ifndef H5GG_MEMORY_DUMP_H
#define H5GG_MEMORY_DUMP_H

#include "MemoryPage.h"

#include <cstddef>
#include <cstdint>
#include <functional>

enum class JJMemoryDumpStatus {
    Completed,
    Cancelled,
    ReadFailed,
    WriteFailed,
    InvalidInput,
};

struct JJMemoryDumpResult {
    JJMemoryDumpStatus status = JJMemoryDumpStatus::InvalidInput;
    size_t bytesWritten = 0;
    uint64_t failureAddress = 0;
};

using JJMemoryWriter = std::function<bool(const void* bytes, size_t length)>;
using JJMemoryDumpCancellation = std::function<bool()>;
using JJMemoryDumpProgress = std::function<void(size_t written, size_t total)>;

JJMemoryDumpResult JJStreamMemoryDump(
    uint64_t address,
    size_t length,
    const JJPartialMemoryReader& reader,
    const JJMemoryWriter& writer,
    const JJMemoryDumpCancellation& cancelled = {},
    const JJMemoryDumpProgress& progress = {},
    size_t chunkSize = 64 * 1024);

#endif
