LOCAL_PATH := $(call my-dir)

# FIX 2 (docs/12-rom-boot-fixes.md): first-stage mount fstab.
# Installed into vendor_boot's first_stage_ramdisk/, one of two places stock ships it
# (stock also has init_boot:/fstab.sun50iw15p1). With GKI, first-stage init pivots into
# /first_stage_ramdisk and reads fstab.${ro.hardware} there to mount system/vendor/super.
# Whether its absence caused the boot failure is unproven; see docs/12.
#
# Soong could NOT target this path in this tree: prebuilt_etc lands in <img>/system/etc,
# `install_in_root` is not a recognized property, and prebuilt_root lands in <img>/system. A Make
# prebuilt with LOCAL_MODULE_PATH gives the exact location. The /vendor/etc copy (second stage) is
# installed separately by vendor/allwinner/hermes/hermes-vendor.mk, so this module must NOT also target
# /vendor/etc (that path is already owned there).
include $(CLEAR_VARS)
LOCAL_MODULE := fstab.sun50iw15p1
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES := rootdir/etc/fstab.sun50iw15p1
LOCAL_MODULE_PATH := $(TARGET_VENDOR_RAMDISK_OUT)/first_stage_ramdisk
include $(BUILD_PREBUILT)

# Apps inherited from AOSP/ATV/Lineage products that this unit shouldn't ship (docs/17). TVLauncherNoGMS is the only launcher;
# TvSettings stays for its fallback home. LineageSetupWizard stays: it handles first-run Wi-Fi, remote pairing and language,
# has no Google login, and disables itself when finished. No modem, so no phone process.
include $(CLEAR_VARS)
LOCAL_MODULE := hermes-removed-apps
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_SUFFIX := .txt
LOCAL_SRC_FILES := hermes-removed-apps.txt
LOCAL_OVERRIDES_MODULES := Settings \
    TeleService Dialer Contacts messaging MmsService WAPPushManager Stk ONS EmergencyInfo CallLogBackup \
    ImsServiceEntitlement CarrierConfig CarrierDefaultApp CellBroadcastLegacyApp com.android.cellbroadcast rild
include $(BUILD_PREBUILT)
