#include "MemoryDump.h"

#include <algorithm>
#include <vector>

JJMemoryDumpResult JJStreamMemoryDump(
    uint64_t address,
    size_t length,
    const JJPartialMemoryReader& reader,
    const JJMemoryWriter& writer,
    const JJMemoryDumpCancellation& cancelled,
    const JJMemoryDumpProgress& progress,
    size_t chunkSize) {
    JJMemoryDumpResult result;
    result.failureAddress = address;
    if(length == 0 || !reader || !writer || chunkSize == 0) return result;

    std::vector<uint8_t> buffer(std::min(chunkSize, length));
    while(result.bytesWritten < length) {
        if(cancelled && cancelled()) {
            result.status = JJMemoryDumpStatus::Cancelled;
            return result;
        }

        size_t requested = std::min(buffer.size(), length - result.bytesWritten);
        size_t read = std::min(
            reader(buffer.data(), address + result.bytesWritten, requested),
            requested);
        if(read == 0) {
            result.status = JJMemoryDumpStatus::ReadFailed;
            result.failureAddress = address + result.bytesWritten;
            return result;
        }
        if(!writer(buffer.data(), read)) {
            result.status = JJMemoryDumpStatus::WriteFailed;
            result.failureAddress = address + result.bytesWritten;
            return result;
        }

        result.bytesWritten += read;
        if(progress) progress(result.bytesWritten, length);
    }

    result.status = JJMemoryDumpStatus::Completed;
    return result;
}
