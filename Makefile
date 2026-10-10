TARGET := iphone:clang:7.1:6.0
ARCHS = armv7
INSTALL_TARGET_PROCESSES = MetroLegacy

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = MetroLegacy
MetroLegacy_FILES = main.m $(shell find src -name '*.m' | LC_ALL=C sort)
MetroLegacy_FRAMEWORKS = UIKit CoreGraphics QuartzCore AVFoundation CoreMedia MediaPlayer Foundation ImageIO Security CFNetwork
MetroLegacy_CFLAGS = -fobjc-arc -fblocks -Wall -Wno-unused-parameter -Wno-deprecated-declarations -DML_APP_VERSION=\"1.0\" \
	-Isrc/Core -Isrc/UI -Isrc/App -Isrc/InnerTube -Isrc/Player

include $(THEOS_MAKE_PATH)/application.mk
