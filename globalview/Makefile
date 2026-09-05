
ARCHS = arm64 arm64e

TARGET = iphone:16.5:15.0

DEBUG=0
STRIP=1
FINALPACKAGE=1
THEOS_DEVICE_IP = iphoneX.local
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = libH5GGApp
libH5GGApp_FILES = globalview.mm ContextHostManager.mm
libH5GGApp_CFLAGS = -fobjc-arc
libH5GGApp_CCFLAGS = -fobjc-arc -std=c++17

#libH5GGApp_LDFLAGS += -weak_library libAPAppView.dylib

#libH5GGApp_LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS_MAKE_PATH)/tweak.mk

clean::
	rm -rf ./packages/*
	rm -rf ./layout

before-package::
	find . -name '*.DS_Store' -type f -delete
	cp -R ./H5GGApp_layout/ ./.theos/_/
	ldid -S../app.entitlements ./.theos/_/Applications/h5ggapp.app/h5ggapp
	cd .. && make 
	cp ./.theos/obj/H5GG.dylib ./.theos/_/Applications/h5ggapp.app/
	
