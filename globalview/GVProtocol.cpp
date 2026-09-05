#include "globalview.h"

#include <cstring>

namespace {

GVProtocolHeader makeHeader(uint32_t totalSize, uint64_t capabilities) {
    GVProtocolHeader header = {};
    header.magic = GV_PROTOCOL_MAGIC;
    header.version = GV_PROTOCOL_VERSION;
    header.headerSize = sizeof(GVProtocolHeader);
    header.totalSize = totalSize;
    header.capabilities = capabilities;
    return header;
}

bool headerIsCompatible(const GVProtocolHeader& header,
                        size_t availableSize,
                        uint32_t expectedSize,
                        uint64_t requiredCapabilities) {
    return header.magic == GV_PROTOCOL_MAGIC &&
        header.version == GV_PROTOCOL_VERSION &&
        header.headerSize == sizeof(GVProtocolHeader) &&
        header.totalSize == expectedSize &&
        header.totalSize <= availableSize &&
        (header.capabilities & requiredCapabilities) == requiredCapabilities;
}

} // namespace

extern "C" GVData GVDataDefaultMake(void) {
    GVData data = {};
    data.header = makeHeader(sizeof(GVData), GV_CAPABILITY_ALL);
    data.touchableAll = 1;
    return data;
}

extern "C" GVImageTransfer GVImageTransferDefaultMake(void) {
    GVImageTransfer transfer = {};
    transfer.header = makeHeader(sizeof(GVImageTransfer),
                                 GV_CAPABILITY_IMAGE_TRANSFER);
    return transfer;
}

extern "C" bool GVDataIsCompatible(const GVData* data,
                                    size_t availableSize,
                                    uint64_t requiredCapabilities) {
    return data && availableSize >= sizeof(GVProtocolHeader) &&
        headerIsCompatible(data->header,
                           availableSize,
                           sizeof(GVData),
                           requiredCapabilities);
}

extern "C" bool GVImageTransferIsCompatible(const GVImageTransfer* transfer,
                                             size_t availableSize) {
    return transfer && availableSize >= sizeof(GVProtocolHeader) &&
        headerIsCompatible(transfer->header,
                           availableSize,
                           sizeof(GVImageTransfer),
                           GV_CAPABILITY_IMAGE_TRANSFER);
}

extern "C" bool GVImageTransferPublish(GVImageTransfer* transfer,
                                        const void* payload,
                                        uint32_t payloadSize) {
    if(!GVImageTransferIsCompatible(transfer, sizeof(*transfer)) ||
       !payload || payloadSize == 0 || payloadSize > GV_IMAGE_MAX_PAYLOAD) {
        return false;
    }

    uint32_t expected = GVImageTransferIdle;
    if(!__atomic_compare_exchange_n(&transfer->state,
                                    &expected,
                                    GVImageTransferWriting,
                                    false,
                                    __ATOMIC_ACQ_REL,
                                    __ATOMIC_ACQUIRE)) {
        return false;
    }

    std::memcpy(transfer->payload, payload, payloadSize);
    transfer->payloadSize = payloadSize;
    __atomic_store_n(&transfer->state, GVImageTransferReady, __ATOMIC_RELEASE);
    return true;
}

extern "C" uint32_t GVImageTransferConsume(GVImageTransfer* transfer,
                                            void* output,
                                            uint32_t outputCapacity) {
    if(!GVImageTransferIsCompatible(transfer, sizeof(*transfer)) || !output ||
       __atomic_load_n(&transfer->state, __ATOMIC_ACQUIRE) != GVImageTransferReady) {
        return 0;
    }

    uint32_t payloadSize = transfer->payloadSize;
    if(payloadSize == 0 || payloadSize > GV_IMAGE_MAX_PAYLOAD ||
       payloadSize > outputCapacity) {
        transfer->payloadSize = 0;
        __atomic_store_n(&transfer->state, GVImageTransferIdle, __ATOMIC_RELEASE);
        return 0;
    }

    std::memcpy(output, transfer->payload, payloadSize);
    transfer->payloadSize = 0;
    __atomic_store_n(&transfer->state, GVImageTransferIdle, __ATOMIC_RELEASE);
    return payloadSize;
}
