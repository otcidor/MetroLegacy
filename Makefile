ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
TARGET := iphone:clang:15.6:14.0
ARCHS := arm64
else
TARGET := iphone:clang:9.3:6.0
ARCHS := armv7 arm64
endif
INSTALL_TARGET_PROCESSES = MetroLegacy

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = MetroLegacy
MetroLegacy_FILES = main.m $(shell find src -name '*.m' | LC_ALL=C sort)
MetroLegacy_FRAMEWORKS = UIKit CoreGraphics QuartzCore AVFoundation CoreMedia MediaPlayer Foundation ImageIO Security CFNetwork MediaToolbox AudioToolbox Accelerate
MetroLegacy_WEAK_FRAMEWORKS = WebKit
MetroLegacy_CFLAGS = -fobjc-arc -fblocks -Wall -Wno-unused-parameter -Wno-deprecated-declarations -Wno-objc-missing-super-calls -DML_APP_VERSION=\"$(THEOS_PACKAGE_BASE_VERSION)\" \
	-Isrc/Core -Isrc/UI -Isrc/App -Isrc/InnerTube -Isrc/Player -Isrc/Account -Isrc/Storage

include $(THEOS_MAKE_PATH)/application.mk

after-package::
	@mkdir -p packages .theos/ipa_payload/Payload
	@rm -rf .theos/ipa_payload/Payload/*
	@cp -a $(THEOS_STAGING_DIR)/Applications/MetroLegacy.app .theos/ipa_payload/Payload/
	@rm -f $(THEOS_PROJECT_DIR)/packages/MetroLegacy.ipa $(THEOS_PROJECT_DIR)/packages/win.otcidor.metrolegacy_*.ipa
	@cd .theos/ipa_payload && zip -q -r9 $(THEOS_PROJECT_DIR)/packages/MetroLegacy.ipa Payload
	@rm -rf .theos/ipa_payload
	@echo "==> IPA generado exitosamente en packages/MetroLegacy.ipa"
