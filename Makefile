# H5GG root tweak build
#
# Compile the current (rootful) variant:
#   make clean all
#
# Build one release package:
#   make package-normal FINALPACKAGE=1
#   make package-rootless FINALPACKAGE=1
#   make package-roothide FINALPACKAGE=1
#
# Build and publish every supported release variant:
#   ./build.sh all

JB_VARIANT := normal
ifneq ($(strip $(THEOS_PACKAGE_SCHEME)),)
JB_VARIANT := $(THEOS_PACKAGE_SCHEME)
endif

ifeq ($(filter normal rootless roothide,$(JB_VARIANT)),)
$(error Unsupported jailbreak build variant '$(JB_VARIANT)'. Use normal, rootless or roothide.)
endif

ARCHS = arm64 arm64e
ifeq ($(JB_VARIANT),normal)
TARGET = iphone:clang:15.6:15.0
else
TARGET = iphone:clang:16.5:15.0
endif

THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip

DEBUG ?= 0
STRIP ?= 1
FINALPACKAGE ?= 0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = H5GG

H5GG_FILES = \
    Tweak.mm \
    h5gg.mm \
    MemScan.mm \
    MemoryResults.cpp \
    MemoryValue.cpp \
    MemoryReader.cpp \
    PointerSearch.cpp \
    MemoryFilter.cpp \
    MemoryPage.cpp \
    MemoryDump.cpp \
    globalview/GVProtocol.cpp \
    DylibTemplate.cpp \
    DylibBuilder.cpp \
    TextEncoding.cpp \
    BridgeMethods.cpp \
    FileNames.cpp \
    TargetSession.cpp \
    RuntimeCoordinator.m \
    FreezerController.mm \
    FilePickerRequest.m \
    PreferencesStore.m \
    DumpController.mm \
    ModalRequestQueue.cpp \
    ScriptStore.cpp \
    PluginLoader.m \
    crossproc.mm \
    FloatMenu.mm \
    FloatButton.m \
    FloatWindow.m \
    TopShow.m \
    ModalShow.mm \
    makeDYLIB.mm \
    makeWindow.m \
    ldid-master/ldid.cpp \
    ldid-master/lookup2.c
H5GG_COMMON_FLAGS =

ifeq ($(JB_VARIANT),normal)
H5GG_COMMON_FLAGS += -DH5GG_BUILD_NORMAL=1
else ifeq ($(JB_VARIANT),rootless)
H5GG_COMMON_FLAGS += -DH5GG_BUILD_ROOTLESS=1
else ifeq ($(JB_VARIANT),roothide)
H5GG_COMMON_FLAGS += -DH5GG_BUILD_ROOTHIDE=1
endif

H5GG_CFLAGS = -fobjc-arc -Wno-deprecated-declarations $(H5GG_COMMON_FLAGS)
H5GG_CCFLAGS = -std=c++17
H5GG_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore JavaScriptCore CoreFoundation

H5GG_LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS_MAKE_PATH)/tweak.mk

.PHONY: test package-normal package-rootless package-roothide package-all
.NOTPARALLEL: package-all

H5GG_PACKAGE_ARCH_normal = iphoneos-arm
H5GG_PACKAGE_ARCH_rootless = iphoneos-arm64
H5GG_PACKAGE_ARCH_roothide = iphoneos-arm64e
H5GG_TOP_LEVEL_MAKE = env -u MAKELEVEL -u _THEOS_TOP_INVOCATION_DONE $(MAKE) -j1

test:
	bash tests/run_tests.sh

package-normal package-rootless package-roothide: package-%:
	$(H5GG_TOP_LEVEL_MAKE) clean THEOS_PACKAGE_SCHEME=$(if $(filter normal,$*),,$*)
	$(H5GG_TOP_LEVEL_MAKE) package FINALPACKAGE=$(FINALPACKAGE) \
		THEOS_PACKAGE_ARCH=$(H5GG_PACKAGE_ARCH_$*) \
		THEOS_PACKAGE_SCHEME=$(if $(filter normal,$*),,$*)

package-all: package-normal package-rootless package-roothide
