#include "MemoryPage.h"

#include <algorithm>
#include <vector>

size_t JJMemoryPage::readableCount() const {
    return static_cast<size_t>(
        std::count_if(bytes.begin(), bytes.end(), [](int16_t value) {
            return value >= 0;
        }));
}

bool JJMemoryPage::complete() const {
    return readableCount() == bytes.size();
}

JJMemoryPage JJReadMemoryPage(uint64_t address,
                              size_t length,
                              const JJPartialMemoryReader& reader,
                              size_t chunkSize) {
    JJMemoryPage page;
    page.address = address;
    page.bytes.assign(length, -1);
    if(!reader || length == 0) return page;
    if(chunkSize == 0) chunkSize = 1;

    std::vector<uint8_t> buffer(chunkSize);
    for(size_t offset = 0; offset < length;) {
        size_t requested = std::min(chunkSize, length - offset);
        size_t read = std::min(reader(buffer.data(), address + offset, requested), requested);
        for(size_t index = 0; index < read; index++) {
            page.bytes[offset + index] = buffer[index];
        }

        for(size_t index = read; index < requested; index++) {
            uint8_t byte = 0;
            if(reader(&byte, address + offset + index, 1) == 1) {
                page.bytes[offset + index] = byte;
            }
        }
        offset += requested;
    }
    return page;
}
