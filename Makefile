# ARCHS = arm64

# TARGET = iphone:clang:15.6:15.0


JB_VARIANT := normal
ifneq ($(strip $(THEOS_PACKAGE_SCHEME)),)
JB_VARIANT := $(THEOS_PACKAGE_SCHEME)
endif

ifeq ($(filter normal rootless roothide,$(JB_VARIANT)),)
$(error Unsupported jailbreak build variant '$(JB_VARIANT)'. Use normal, rootless or roothide.)
endif

ifeq ($(JB_VARIANT),normal)
	ARCHS = arm64 arm64e
	TARGET = iphone:clang:15.6:15.0
else ifeq ($(JB_VARIANT),rootless)
	ARCHS = arm64 arm64e
	TARGET = iphone:clang:16.5:15.0
else ifeq ($(JB_VARIANT),roothide)
	ARCHS = arm64 arm64e
	TARGET = iphone:clang:16.5:15.0
endif

THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip

DEBUG=0
STRIP=0
FINALPACKAGE=0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = H5GG

H5GG_FILES = Tweak.mm h5gg.mm MemScan.mm MemoryResults.cpp MemoryValue.cpp MemoryFilter.cpp MemoryPage.cpp MemoryDump.cpp DylibTemplate.cpp BridgeMethods.cpp FileNames.cpp crossproc.mm FloatMenu.mm FloatButton.m FloatWindow.m TopShow.m ModalShow.m makeDYLIB.mm makeWindow.m ldid-master/ldid.cpp ldid-master/lookup2.c
H5GG_COMMON_FLAGS =

ifeq ($(JB_VARIANT),normal)
H5GG_COMMON_FLAGS += -DH5GG_BUILD_NORMAL=1
else ifeq ($(JB_VARIANT),rootless)
H5GG_COMMON_FLAGS += -DH5GG_BUILD_ROOTLESS=1
else ifeq ($(JB_VARIANT),roothide)
H5GG_COMMON_FLAGS += -DH5GG_BUILD_ROOTHIDE=1
endif

H5GG_CFLAGS = -fobjc-arc -Wno-deprecated-declarations $(H5GG_COMMON_FLAGS)
H5GG_CCFLAGS = -fobjc-arc -std=c++17 -Wno-deprecated-declarations $(H5GG_COMMON_FLAGS)
H5GG_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore JavaScriptCore CoreFoundation

ifneq ($(filter rootless roothide,$(JB_VARIANT)),)
H5GG_LDFLAGS += -L$(THEOS)/vendor/lib -L$(THEOS)/vendor/lib/iphone/rootless
endif

H5GG_LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS_MAKE_PATH)/tweak.mk

.PHONY: package-normal package-rootless package-roothide package-all
.NOTPARALLEL: package-all

package-normal package-rootless package-roothide: package-%:
	$(MAKE) -j1 clean THEOS_PACKAGE_SCHEME=$(if $(filter normal,$*),,$*)
	$(MAKE) -j1 all THEOS_PACKAGE_SCHEME=$(if $(filter normal,$*),,$*)
	$(MAKE) -j1 package FINALPACKAGE=$(FINALPACKAGE) THEOS_PACKAGE_SCHEME=$(if $(filter normal,$*),,$*)

package-all: package-normal package-rootless package-roothide
