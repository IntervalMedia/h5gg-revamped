#ifndef globalview_h
#define globalview_h

typedef struct {
    BOOL enable;
    BOOL appLoaded;
    BOOL viewHosted;
    BOOL touchableAll;
    CGRect touchableRect;
    CGRect floatMenuRect;
    BOOL floatBtnClick;
    BOOL customButtonAction;
    BOOL followCurrentOrientation;
    UIInterfaceOrientation curOrientation;
    BOOL setWindowVisible;
    BOOL windowVisibleState;
    size_t buttonImageSize;
    Byte buttonImageData[512*1024];
} GVData;

static inline GVData GVDataDefaultMake(void) {
    GVData d = {0};
    d.touchableAll = YES;
    return d;
}

#endif /* globalview_h */
