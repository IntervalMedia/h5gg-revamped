ARCHS = arm64 arm64e

TARGET = iphone:clang:15.6:15.0

# THEOS_DEVICE_IP = iphoneX.local

THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip

DEBUG=0
STRIP=1
FINALPACKAGE=1

include $(THEOS)/makefiles/common.mk

JB_VARIANT = normal
ifneq ($(filter rootless roothide,$(THEOS_PACKAGE_SCHEME)),)
JB_VARIANT = $(THEOS_PACKAGE_SCHEME)
endif

TWEAK_NAME = H5GG

H5GG_FILES = Tweak.mm h5gg.mm MemScan.mm MemoryResults.cpp MemoryValue.cpp MemoryFilter.cpp BridgeMethods.cpp FileNames.cpp crossproc.mm FloatMenu.mm FloatButton.m FloatWindow.m TopShow.m ModalShow.m makeDYLIB.mm makeWindow.m ldid-master/ldid.cpp ldid-master/lookup2.c
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

H5GG_CFLAGS = -fobjc-arc -Wno-deprecated-declarations $(H5GG_COMMON_FLAGS)
H5GG_CCFLAGS = -fobjc-arc -std=c++17 -Wno-deprecated-declarations $(H5GG_COMMON_FLAGS)

ifneq ($(filter rootless roothide,$(JB_VARIANT)),)
H5GG_LDFLAGS += -L$(THEOS)/vendor/lib -L$(THEOS)/vendor/lib/iphone/rootless
endif

H5GG_LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS_MAKE_PATH)/tweak.mk

.PHONY: package-normal package-rootless package-roothide package-all

package-normal:
	$(MAKE) clean package FINALPACKAGE=$(FINALPACKAGE)

package-rootless:
	$(MAKE) clean package FINALPACKAGE=$(FINALPACKAGE) THEOS_PACKAGE_SCHEME=rootless

package-roothide:
	$(MAKE) clean package FINALPACKAGE=$(FINALPACKAGE) THEOS_PACKAGE_SCHEME=roothide

package-all: package-normal package-rootless package-roothide

clean::
	rm -rf ./packages/*
