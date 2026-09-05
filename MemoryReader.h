#ifndef H5GG_MEMORY_READER_H
#define H5GG_MEMORY_READER_H

#include <cstddef>
#include <cstdint>
#include <functional>
#include <vector>

class JJMemoryReader {
public:
    virtual ~JJMemoryReader() = default;

    size_t readBytes(void* output, uint64_t address, size_t length);
    bool readExact(void* output, uint64_t address, size_t length);
    bool readValue(void* output, uint64_t address, int type);

protected:
    virtual size_t performRead(void* output,
                               uint64_t address,
                               size_t length) = 0;
};

using JJMemoryReadCallback =
    std::function<size_t(void* output, uint64_t address, size_t length)>;

class JJCallbackMemoryReader final : public JJMemoryReader {
public:
    explicit JJCallbackMemoryReader(JJMemoryReadCallback callback);

private:
    size_t performRead(void* output,
                       uint64_t address,
                       size_t length) override;
    JJMemoryReadCallback callback_;
};

class JJBufferMemoryReader final : public JJMemoryReader {
public:
    JJBufferMemoryReader(uint64_t baseAddress, std::vector<uint8_t> bytes);

private:
    size_t performRead(void* output,
                       uint64_t address,
                       size_t length) override;
    uint64_t baseAddress_;
    std::vector<uint8_t> bytes_;
};

#endif
