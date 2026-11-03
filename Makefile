ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = CriticalOps

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CriticalOpsMenu
CriticalOpsMenu_FILES = Tweak.xm
CriticalOpsMenu_CFLAGS = -fobjc-arc -O2
CriticalOpsMenu_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
