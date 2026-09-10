TARGET := iphone:clang:6.1:6.0
ARCHS := armv7 armv7s

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = OpenVK

OpenVK_FILES = main.m $(wildcard src/*.m) $(wildcard vendor/APLSlideMenu/*.m)
OpenVK_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Ivendor/APLSlideMenu -Isrc
OpenVK_FRAMEWORKS = UIKit CoreGraphics QuartzCore Security CFNetwork MediaPlayer AVFoundation AudioToolbox CoreMedia

include $(THEOS)/makefiles/application.mk

after-install::
	install.exec "killall -9 OpenVK" || true
