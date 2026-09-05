#include "../globalview/globalview.h"

#include <array>
#include <cassert>
#include <cstdint>
#include <cstring>

namespace {

void versionedHeaderIsValidated() {
    static_assert(sizeof(GVProtocolHeader) == 24, "protocol header layout changed");
    static_assert(sizeof(GVData) == 112, "shared-state layout changed");
    static_assert(sizeof(GVImageTransfer) == 524320,
                  "image-transfer layout changed");
    static_assert(sizeof(GVData) < sizeof(GVImageTransfer),
                  "large payload must stay outside GVData");

    GVData data = GVDataDefaultMake();
    assert(GVDataIsCompatible(&data, sizeof(data), GV_CAPABILITY_ALL));
    assert(data.header.magic == GV_PROTOCOL_MAGIC);
    assert(data.header.version == GV_PROTOCOL_VERSION);
    assert(data.header.headerSize == sizeof(GVProtocolHeader));
    assert(data.header.totalSize == sizeof(GVData));
    assert(data.touchableAll == 1);

    assert(!GVDataIsCompatible(&data,
                               sizeof(GVProtocolHeader) - 1,
                               GV_CAPABILITY_ALL));

    GVData invalid = data;
    invalid.header.magic ^= 1;
    assert(!GVDataIsCompatible(&invalid, sizeof(invalid), 0));

    invalid = data;
    invalid.header.version++;
    assert(!GVDataIsCompatible(&invalid, sizeof(invalid), 0));

    invalid = data;
    invalid.header.headerSize--;
    assert(!GVDataIsCompatible(&invalid, sizeof(invalid), 0));

    invalid = data;
    invalid.header.totalSize--;
    assert(!GVDataIsCompatible(&invalid, sizeof(invalid), 0));

    invalid = data;
    invalid.header.capabilities &= ~GV_CAPABILITY_IMAGE_TRANSFER;
    assert(!GVDataIsCompatible(&invalid,
                               sizeof(invalid),
                               GV_CAPABILITY_IMAGE_TRANSFER));
    assert(GVDataIsCompatible(&invalid,
                              sizeof(invalid),
                              GV_CAPABILITY_TOUCH_REGIONS));
}

void imageTransferIsBoundedAndSingleSlot() {
    GVImageTransfer transfer = GVImageTransferDefaultMake();
    assert(GVImageTransferIsCompatible(&transfer, sizeof(transfer)));

    const std::array<uint8_t, 5> first = {1, 3, 5, 7, 9};
    const std::array<uint8_t, 3> second = {2, 4, 6};
    assert(GVImageTransferPublish(&transfer, first.data(), first.size()));
    assert(!GVImageTransferPublish(&transfer, second.data(), second.size()));

    std::array<uint8_t, 8> output = {};
    assert(GVImageTransferConsume(&transfer, output.data(), output.size()) ==
           first.size());
    assert(std::memcmp(output.data(), first.data(), first.size()) == 0);
    assert(transfer.state == GVImageTransferIdle);
    assert(transfer.payloadSize == 0);
    assert(GVImageTransferConsume(&transfer, output.data(), output.size()) == 0);

    assert(GVImageTransferPublish(&transfer, second.data(), second.size()));
    assert(GVImageTransferConsume(&transfer, output.data(), 2) == 0);
    assert(transfer.state == GVImageTransferIdle);

    assert(!GVImageTransferPublish(&transfer, nullptr, 1));
    assert(!GVImageTransferPublish(&transfer, first.data(), 0));
    assert(!GVImageTransferPublish(&transfer,
                                   first.data(),
                                   GV_IMAGE_MAX_PAYLOAD + 1));

    transfer.header.version++;
    assert(!GVImageTransferPublish(&transfer, first.data(), first.size()));
    assert(GVImageTransferConsume(&transfer, output.data(), output.size()) == 0);
}

} // namespace

int main() {
    versionedHeaderIsValidated();
    imageTransferIsBoundedAndSingleSlot();
    return 0;
}
