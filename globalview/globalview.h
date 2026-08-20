#ifndef H5GG_GLOBALVIEW_H
#define H5GG_GLOBALVIEW_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define GV_PROTOCOL_MAGIC UINT32_C(0x48354756)
#define GV_PROTOCOL_VERSION UINT16_C(1)
#define GV_IMAGE_MAX_PAYLOAD (UINT32_C(512) * UINT32_C(1024))

#define GV_CAPABILITY_TOUCH_REGIONS       (UINT64_C(1) << 0)
#define GV_CAPABILITY_ORIENTATION_SYNC    (UINT64_C(1) << 1)
#define GV_CAPABILITY_WINDOW_VISIBILITY   (UINT64_C(1) << 2)
#define GV_CAPABILITY_CUSTOM_BUTTON       (UINT64_C(1) << 3)
#define GV_CAPABILITY_IMAGE_TRANSFER      (UINT64_C(1) << 4)
#define GV_CAPABILITY_ALL                 \
    (GV_CAPABILITY_TOUCH_REGIONS | GV_CAPABILITY_ORIENTATION_SYNC | \
     GV_CAPABILITY_WINDOW_VISIBILITY | GV_CAPABILITY_CUSTOM_BUTTON | \
     GV_CAPABILITY_IMAGE_TRANSFER)

typedef struct {
    uint32_t magic;
    uint16_t version;
    uint16_t headerSize;
    uint32_t totalSize;
    uint32_t reserved;
    uint64_t capabilities;
} GVProtocolHeader;

typedef struct {
    double x;
    double y;
    double width;
    double height;
} GVRect;

typedef struct {
    GVProtocolHeader header;
    uint8_t enable;
    uint8_t appLoaded;
    uint8_t viewHosted;
    uint8_t touchableAll;
    uint8_t floatBtnClick;
    uint8_t customButtonAction;
    uint8_t followCurrentOrientation;
    uint8_t setWindowVisible;
    uint8_t windowVisibleState;
    uint8_t reservedFlags[7];
    int32_t curOrientation;
    uint32_t reservedState;
    GVRect touchableRect;
    GVRect floatMenuRect;
} GVData;

typedef enum {
    GVImageTransferIdle = 0,
    GVImageTransferWriting = 1,
    GVImageTransferReady = 2
} GVImageTransferState;

typedef struct {
    GVProtocolHeader header;
    uint32_t state;
    uint32_t payloadSize;
    uint8_t payload[GV_IMAGE_MAX_PAYLOAD];
} GVImageTransfer;

#ifdef __cplusplus
static_assert(sizeof(GVProtocolHeader) == 24, "GVProtocolHeader ABI changed");
static_assert(sizeof(GVData) == 112, "GVData ABI changed");
static_assert(sizeof(GVImageTransfer) == 524320, "GVImageTransfer ABI changed");
#else
_Static_assert(sizeof(GVProtocolHeader) == 24, "GVProtocolHeader ABI changed");
_Static_assert(sizeof(GVData) == 112, "GVData ABI changed");
_Static_assert(sizeof(GVImageTransfer) == 524320, "GVImageTransfer ABI changed");
#endif

#ifdef __cplusplus
extern "C" {
#endif

GVData GVDataDefaultMake(void);
GVImageTransfer GVImageTransferDefaultMake(void);

bool GVDataIsCompatible(const GVData* data,
                        size_t availableSize,
                        uint64_t requiredCapabilities);
bool GVImageTransferIsCompatible(const GVImageTransfer* transfer,
                                 size_t availableSize);

bool GVImageTransferPublish(GVImageTransfer* transfer,
                            const void* payload,
                            uint32_t payloadSize);
uint32_t GVImageTransferConsume(GVImageTransfer* transfer,
                                void* output,
                                uint32_t outputCapacity);

#ifdef __cplusplus
}
#endif

#if defined(__OBJC__)
#import <CoreGraphics/CoreGraphics.h>

static inline GVRect GVRectFromCGRect(CGRect rect) {
    GVRect value = {
        rect.origin.x,
        rect.origin.y,
        rect.size.width,
        rect.size.height
    };
    return value;
}

static inline CGRect CGRectFromGVRect(GVRect rect) {
    return CGRectMake(rect.x, rect.y, rect.width, rect.height);
}
#endif

#endif /* H5GG_GLOBALVIEW_H */
