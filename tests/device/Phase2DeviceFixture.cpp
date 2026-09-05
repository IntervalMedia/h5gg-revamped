#include "Phase2DeviceFixture.h"

#include <sys/mman.h>
#include <unistd.h>

#include <cstdint>
#include <cstring>

extern "C" __attribute__((used, visibility("default")))
volatile H5GGPhase2DeviceFixture H5GGPhase2DeviceFixtureState = {
    H5GGPhase2FixtureMarker,
    -101,
    211,
    -23456,
    54321,
    0,
    -123456789,
    3456789012U,
    -5124095576030430LL,
    18364758544493064720ULL,
    1234.25F,
    0,
    -98765.125,
    135791357,
    246802468,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    {0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xB0, 0x0B},
};

namespace {

void* boundaryMapping = MAP_FAILED;
void* dumpMapping = MAP_FAILED;
void* cancelMapping = MAP_FAILED;
size_t boundaryMappingSize = 0;
size_t dumpMappingSize = 0;
size_t cancelMappingSize = 0;

__attribute__((constructor)) void setupPhase2DeviceFixture() {
    const long configuredPageSize = sysconf(_SC_PAGESIZE);
    if(configuredPageSize <= 0) return;
    const size_t pageSize = static_cast<size_t>(configuredPageSize);

    boundaryMappingSize = pageSize * 2;
    boundaryMapping = mmap(nullptr, boundaryMappingSize, PROT_READ | PROT_WRITE,
                           MAP_PRIVATE | MAP_ANON, -1, 0);
    if(boundaryMapping != MAP_FAILED) {
        std::memset(boundaryMapping, 0x5A, pageSize);
        if(mprotect(static_cast<uint8_t*>(boundaryMapping) + pageSize,
                    pageSize, PROT_NONE) == 0) {
            H5GGPhase2DeviceFixtureState.boundaryAddress =
                reinterpret_cast<uint64_t>(boundaryMapping) + pageSize - 128;
            H5GGPhase2DeviceFixtureState.pageSize = pageSize;
        }
    }

    dumpMappingSize = pageSize;
    dumpMapping = mmap(nullptr, dumpMappingSize, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANON, -1, 0);
    if(dumpMapping != MAP_FAILED) {
        uint8_t* bytes = static_cast<uint8_t*>(dumpMapping);
        for(size_t index = 0; index < dumpMappingSize; index++) {
            bytes[index] = static_cast<uint8_t>('A' + index % 26);
        }
        H5GGPhase2DeviceFixtureState.dumpAddress =
            reinterpret_cast<uint64_t>(dumpMapping);
        H5GGPhase2DeviceFixtureState.dumpSize = dumpMappingSize;
    }

    cancelMappingSize = 32ULL * 1024ULL * 1024ULL;
    cancelMapping = mmap(nullptr, cancelMappingSize, PROT_READ | PROT_WRITE,
                         MAP_PRIVATE | MAP_ANON, -1, 0);
    if(cancelMapping != MAP_FAILED) {
        H5GGPhase2DeviceFixtureState.cancelAddress =
            reinterpret_cast<uint64_t>(cancelMapping);
        H5GGPhase2DeviceFixtureState.cancelSize = cancelMappingSize;
    }

    H5GGPhase2DeviceFixtureState.pointerToMarker =
        reinterpret_cast<uint64_t>(&H5GGPhase2DeviceFixtureState.marker);
}

__attribute__((destructor)) void teardownPhase2DeviceFixture() {
    if(boundaryMapping != MAP_FAILED) munmap(boundaryMapping, boundaryMappingSize);
    if(dumpMapping != MAP_FAILED) munmap(dumpMapping, dumpMappingSize);
    if(cancelMapping != MAP_FAILED) munmap(cancelMapping, cancelMappingSize);
}

} // namespace
