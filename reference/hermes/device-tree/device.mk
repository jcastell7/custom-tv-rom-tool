# device.mk — Allwinner H723 "hermes" projector (scaffold)

# --- Device path (product-config scope) ---
# device.mk (product config) is parsed BEFORE BoardConfig.mk, where DEVICE_PATH is defined for the
# board scope. So DEVICE_PATH is EMPTY here unless we set it: a `$(DEVICE_PATH)/foo` with `:=` would
# expand to `/foo` (absolute), and ninja then fails with "'/manifest.xml' ... missing and no known
# rule to make it". NOTE: `$(call my-dir)` does NOT work here — inside inherit-product's include the
# last entry of MAKEFILE_LIST is the import machinery, not this file, so my-dir returns empty and the
# bug persists. Use the literal tree path (same value BoardConfig.mk uses). Must precede any use below.
DEVICE_PATH := device/allwinner/hermes

# --- Platform / Treble ---
# Device shipped on Android 14 (SDK 34). Setting the shipping API level makes the build compute
# PRODUCT_FULL_TREBLE := true (config.mk: >=26 => true), which clears the "device does not have
# Treble enabled. This is unsafe." warning and enables the Treble/VINTF behaviors this vendor
# partition requires. Truthful value for this hardware.
PRODUCT_SHIPPING_API_LEVEL := 34

# --- Build behavior (bring-up) ---
# Skip the system-server dexpreopt artifact check. On this first 32-bit bring-up the
# org.lineageos.platform system-server jar isn't producing oat/arm dexpreopt artifacts, so the
# check (build/make/core/tasks/dex_preopt_check.mk) errors. Disabling it lets the build finish;
# the jar is simply JIT/dexopted at first boot instead of build time (startup-speed only, not
# correctness). TODO(production): get system-server dexpreopt working and remove this.
DISABLE_DEXPREOPT_CHECK := true

# --- Dynamic partitions / A-B ---
PRODUCT_USE_DYNAMIC_PARTITIONS := true
# BSP kernel, relax during bring-up. (Comment on its own line: a trailing inline comment would
# make the value "false<spaces>" and break the ==false string compare.)
PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false

# --- A/B ---
AB_OTA_UPDATER := true
PRODUCT_PACKAGES += \
    update_engine \
    update_engine_sideload \
    update_verifier

# Virtual A/B (matches stock: ro.virtual_ab.enabled=true, non-compressed). REQUIRED, not optional:
# our super group is sized the VAB way (~full super, one slot). Without VAB enabled, the build
# classifies us as classic A/B (both slots in super) and check_partition_sizes enforces group <=
# super/2 (1.28 GB), which our 2.68 GB group fails. launch.mk sets PRODUCT_VIRTUAL_AB_OTA := true ->
# misc_info virtual_ab=true -> DeviceType=VAB -> num_slots=1 -> limit = full super (passes).
# Non-compressed launch.mk (not compression.mk): stock has no ro.virtual_ab.compression.enabled.
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota/launch.mk)

# Force OTA package generation (needed by `mka bacon`). The build otherwise opts out of building an
# OTA package when there's no recovery fstab (build/make/core/Makefile:5523) — which is our case (no
# dedicated recovery partition). Without this, INTERNAL_OTA_PACKAGE_TARGET is empty and the
# lineage zip rule fails: `ln -f <empty> ...lineage-....zip`. This device's OTA is an A/B payload
# applied by update_engine, so no recovery fstab is required to produce it.
PRODUCT_BUILD_GENERIC_OTA_PACKAGE := true

# --- Kernel modules (DLKM): install the recovered .ko set ---
# Point these at the prebuilt blobs once extract-files has run:
#   BOARD_VENDOR_KERNEL_MODULES += $(wildcard vendor/allwinner/hermes/proprietary/vendor_dlkm/lib/modules/*.ko)
# Load order is in device/allwinner/hermes/modules.load.vendor_dlkm (+ .first_stage).

# --- init / fstab (FIX 2, docs/12-rom-boot-fixes.md) ---
# First-stage init needs the fstab in a boot ramdisk, not only the vendor partition, to mount
# system/vendor/super. Stock ships it there; ours did not. Provided by the Make prebuilt in Android.mk, which
# installs to vendor_boot:/first_stage_ramdisk/. The /vendor/etc copy (second stage) is already installed by
# vendor/allwinner/hermes/hermes-vendor.mk, so that module must not also target /vendor/etc.
PRODUCT_PACKAGES += fstab.sun50iw15p1

# --- Recovery USB identity, the same values as stock's recovery ---
PRODUCT_VENDOR_PROPERTIES += \
    ro.recovery.usb.vid=18D1 \
    ro.recovery.usb.adb.pid=D001 \
    ro.recovery.usb.fastboot.pid=4EE0

# fastbootd in recovery, so flashing doesn't depend on the USB stick. adb in recovery is open while bringing up the
# device, as on stock (ro.adb.secure=0). TODO(production): remove this.
PRODUCT_PACKAGES += fastbootd
PRODUCT_COPY_FILES += $(DEVICE_PATH)/rootdir/etc/init/hermes-bringup.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/hermes-bringup.rc
PRODUCT_COPY_FILES += $(DEVICE_PATH)/rootdir/bin/hermes-boot-watchdog.sh:$(TARGET_COPY_OUT_VENDOR)/bin/hermes-boot-watchdog.sh
PRODUCT_COPY_FILES += $(DEVICE_PATH)/rootdir/bin/hermes-swap.sh:$(TARGET_COPY_OUT_VENDOR)/bin/hermes-swap.sh
PRODUCT_COPY_FILES += $(DEVICE_PATH)/rootdir/bin/hermes-wl-retry.sh:$(TARGET_COPY_OUT_VENDOR)/bin/hermes-wl-retry.sh

# Apps this unit shouldn't ship (docs/17).
PRODUCT_PACKAGES += hermes-removed-apps

# Launcher entry and boot tasks for stock's keystone app (docs/18).
PRODUCT_PACKAGES += HermesKeystone

# Provides the sk_dup symbol stock's wpa_supplicant and hostapd need (docs/12, FIX 17).
PRODUCT_PACKAGES += libhermes_wpa_shim

# Boot control HAL, the same HIDL 1.2 version as stock. update_verifier reboots the system without it. It uses the misc format u-boot already reads (BCAB).
PRODUCT_PACKAGES += \
    android.hardware.boot@1.2-impl \
    android.hardware.boot@1.2-impl.recovery \
    android.hardware.boot@1.2-service
PRODUCT_VENDOR_PROPERTIES += ro.adb.secure=0

# --- HALs / VINTF ---
DEVICE_MANIFEST_FILE := $(DEVICE_PATH)/manifest.xml
# Stock fragments for HALs whose AOSP module doesn't install one (docs/12, FIX 11). The build rejects VINTF files in PRODUCT_COPY_FILES.
# Not android.hardware.cas: its APEX declares it, and a second declaration invalidates the whole device manifest.
DEVICE_MANIFEST_FILE += \
    $(DEVICE_PATH)/vintf/android.hardware.wifi.hostapd.xml \
    $(DEVICE_PATH)/vintf/android.hardware.wifi.supplicant.xml
# DEVICE_MATRIX_FILE   := $(DEVICE_PATH)/compatibility_matrix.xml
# Device framework compat matrix: declares the 4 proprietary vendor HALs this device advertises
# (tvserver, display.config, sunxi.tv.graphics, drmheapallocator) as optional, so the VINTF
# compatibility check (PRODUCT_ENFORCE_VINTF_MANIFEST=true) accepts them — they're in no AOSP/LOS FCM.
DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE := $(DEVICE_PATH)/framework_compatibility_matrix.xml

# --- Proprietary blobs (generated by setup-makefiles.sh from proprietary-files.txt) ---
$(call inherit-product-if-exists, vendor/allwinner/hermes/hermes-vendor.mk)

$(call inherit-product, $(DEVICE_PATH)/hermes-vendor-extra.mk)

# Google Play and F-Droid, unpacked by tooling/gapps/setup-gapps.py (docs/16). Not in git.
$(call inherit-product-if-exists, vendor/hermes-gapps/gapps.mk)
