ARCHS = arm64

TARGET = iphone:16.5:15.0

THEOS_DEVICE_IP = iphoneX.local

THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip

DEBUG=0
STRIP=1
FINALPACKAGE=1

include $(THEOS)/makefiles/common.mk


TWEAK_NAME = H5GG

H5GG_FILES = Tweak.mm h5gg.mm MemScan.mm crossproc.mm FloatMenu.mm FloatButton.m FloatWindow.m TopShow.m ModalShow.m makeDYLIB.mm makeWindow.m ldid-master/ldid.cpp ldid-master/lookup2.c
H5GG_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
H5GG_CCFLAGS = -fobjc-arc -std=c++17 -Wno-deprecated-declarations
H5GG_LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS_MAKE_PATH)/tweak.mk

clean::
	rm -rf ./packages/*

