TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME=rootless

THEOS_DEVICE_IP=192.168.2.95
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = appcloner

appcloner_FILES = EntryPoint.x BundleHooks.x KeychainHooks.x ContainerHooks.x \
	igdumper.x DeviceSpoofer.x LocationSpoofer.x BackgroundKiller.x \
	ClonerConfig.m CameraHooks.m CameraFloatingButton.m ImageTransforms.m \
	FakeCapturePhoto.m TweakImagePickerDelegate.m \
	Networking/BBProxy.m Networking/NSHook.m Networking/Rogue/RGELog.m \
	Networking/Rogue/RGEProxy.m Networking/Rogue/RogueHook.m \
	fishhook/fishhook.c

appcloner_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -w

include $(THEOS_MAKE_PATH)/tweak.mk
FINALPACKAGE=1
