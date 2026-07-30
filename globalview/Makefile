
ARCHS = arm64 arm64e

TARGET = iphone:clang:15.6:15.6

DEBUG=0
STRIP=1
FINALPACKAGE=1
# THEOS_DEVICE_IP = iphoneX.local
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip

include $(THEOS)/makefiles/common.mk

JB_VARIANT = normal
ifneq ($(filter rootless roothide,$(THEOS_PACKAGE_SCHEME)),)
JB_VARIANT = $(THEOS_PACKAGE_SCHEME)
endif

H5GG_COMMON_FLAGS =
ifeq ($(JB_VARIANT),normal)
H5GG_COMMON_FLAGS += -DH5GG_BUILD_NORMAL=1
else ifeq ($(JB_VARIANT),rootless)
H5GG_COMMON_FLAGS += -DH5GG_BUILD_ROOTLESS=1
else ifeq ($(JB_VARIANT),roothide)
H5GG_COMMON_FLAGS += -DH5GG_BUILD_ROOTHIDE=1
else
$(error Unsupported jailbreak build variant '$(JB_VARIANT)'. Use normal, rootless or roothide.)
endif

TWEAK_NAME = libH5GGApp
libH5GGApp_FILES = globalview.mm ContextHostManager.mm ../FloatButton.m ../makeWindow.m
libH5GGApp_CFLAGS = -fobjc-arc
libH5GGApp_CCFLAGS = -fobjc-arc -std=c++17
libH5GGApp_ADDITIONAL_CCFLAGS = $(H5GG_COMMON_FLAGS)

ifneq ($(filter rootless roothide,$(JB_VARIANT)),)
libH5GGApp_LDFLAGS += -L$(THEOS)/vendor/lib -L$(THEOS)/vendor/lib/iphone/rootless
endif
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
	
