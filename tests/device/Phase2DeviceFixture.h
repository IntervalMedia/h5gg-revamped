#ifndef H5GG_PHASE2_DEVICE_FIXTURE_H
#define H5GG_PHASE2_DEVICE_FIXTURE_H

#include <cstddef>
#include <cstdint>

constexpr uint64_t H5GGPhase2FixtureMarker = 0x4855474750325638ULL;
constexpr size_t H5GGPhase2FixtureBytes = 128;

struct alignas(8) H5GGPhase2DeviceFixture {
    uint64_t marker;
    int8_t i8;
    uint8_t u8;
    int16_t i16;
    uint16_t u16;
    uint16_t padding14;
    int32_t i32;
    uint32_t u32;
    int64_t i64;
    uint64_t u64;
    float f32;
    uint32_t padding44;
    double f64;
    int32_t groupA;
    int32_t groupB;
    uint64_t pointerToMarker;
    uint64_t boundaryAddress;
    uint64_t pageSize;
    uint64_t dumpAddress;
    uint64_t dumpSize;
    uint64_t cancelAddress;
    uint64_t cancelSize;
    uint8_t hexBytes[8];
};

static_assert(sizeof(H5GGPhase2DeviceFixture) == H5GGPhase2FixtureBytes);
static_assert(offsetof(H5GGPhase2DeviceFixture, i8) == 8);
static_assert(offsetof(H5GGPhase2DeviceFixture, u8) == 9);
static_assert(offsetof(H5GGPhase2DeviceFixture, i16) == 10);
static_assert(offsetof(H5GGPhase2DeviceFixture, u16) == 12);
static_assert(offsetof(H5GGPhase2DeviceFixture, i32) == 16);
static_assert(offsetof(H5GGPhase2DeviceFixture, u32) == 20);
static_assert(offsetof(H5GGPhase2DeviceFixture, i64) == 24);
static_assert(offsetof(H5GGPhase2DeviceFixture, u64) == 32);
static_assert(offsetof(H5GGPhase2DeviceFixture, f32) == 40);
static_assert(offsetof(H5GGPhase2DeviceFixture, f64) == 48);
static_assert(offsetof(H5GGPhase2DeviceFixture, groupA) == 56);
static_assert(offsetof(H5GGPhase2DeviceFixture, groupB) == 60);
static_assert(offsetof(H5GGPhase2DeviceFixture, pointerToMarker) == 64);
static_assert(offsetof(H5GGPhase2DeviceFixture, boundaryAddress) == 72);
static_assert(offsetof(H5GGPhase2DeviceFixture, pageSize) == 80);
static_assert(offsetof(H5GGPhase2DeviceFixture, dumpAddress) == 88);
static_assert(offsetof(H5GGPhase2DeviceFixture, dumpSize) == 96);
static_assert(offsetof(H5GGPhase2DeviceFixture, cancelAddress) == 104);
static_assert(offsetof(H5GGPhase2DeviceFixture, cancelSize) == 112);
static_assert(offsetof(H5GGPhase2DeviceFixture, hexBytes) == 120);

extern "C" volatile H5GGPhase2DeviceFixture H5GGPhase2DeviceFixtureState;

#endif
