# BoardConfig.mk — Allwinner H723 (sun50iw15p1) "hermes" smart projector
# Scaffolded from the stock firmware (see docs/06). Values marked TODO need confirmation
# once the kernel source tree is in place. All numbers are from the dumped images/headers.

DEVICE_PATH := device/allwinner/hermes

# ---------------------------------------------------------------------------
# Architecture — PURE 32-bit ARM (ro.product.cpu.abilist64 is empty on stock)
# ---------------------------------------------------------------------------
TARGET_ARCH := arm
TARGET_ARCH_VARIANT := armv7-a-neon
TARGET_CPU_ABI := armeabi-v7a
TARGET_CPU_ABI2 := armeabi
# from dalvik.vm.isa.arm.variant
TARGET_CPU_VARIANT := cortex-a7
TARGET_CPU_VARIANT_RUNTIME := cortex-a7
# No TARGET_2ND_ARCH — the vendor blobs are 32-bit only (no /vendor/lib64).

# ro.board.platform (used in ifeq tests and file paths — must have no trailing whitespace)
TARGET_BOARD_PLATFORM := hermes
TARGET_BOOTLOADER_BOARD_NAME := sun50iw15p1

# ---------------------------------------------------------------------------
# Kernel — Linux 5.15.167, arch/arm sunxi.
# PRIMARY PATH: use the PREBUILT kernel extracted from the device (no source needed).
# The exact Image + DTB + modules already boot Android 14 on this hardware, so every
# proprietary driver works as-is. Source is only needed to *modify* the kernel (see below).
# ---------------------------------------------------------------------------
TARGET_NO_KERNEL := false
# from firmware/extracted/boot_a/kernel (a path — trailing whitespace would corrupt the filename)
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
TARGET_PREBUILT_DTB := $(DEVICE_PATH)/prebuilt/dtb/sun50iw15p1.dtb
BOARD_PREBUILT_DTBIMAGE_DIR := $(DEVICE_PATH)/prebuilt/dtb

# --- OPTIONAL: build kernel from source instead (only if you need to change it) ---
# Reference source (partial, same die): kernel/allwinner/hermes-reference (H726 CCU/pinctrl/DTS).
# Full BSP is not public — request GPL source from the ODM, or mainline from the reference.
#   TARGET_KERNEL_SOURCE := kernel/allwinner/hermes
#   TARGET_KERNEL_CONFIG := hermes_defconfig     # == firmware/kernel/kernel.config (/proc/config.gz)
#   BOARD_KERNEL_IMAGE_NAME := zImage
#   TARGET_KERNEL_ADDITIONAL_FLAGS := LLVM=1 LLVM_IAS=1   # stock: clang-17 LTO/BOLT/PGO

# ---------------------------------------------------------------------------
# boot.img — header v4, kernel only (generic ramdisk lives in init_boot)
# ---------------------------------------------------------------------------
BOARD_BOOT_HEADER_VERSION := 4
BOARD_KERNEL_PAGESIZE := 2048                            # vendor_boot page size 0x800
BOARD_KERNEL_BASE        := 0x40000000                   # kernel load 0x40008000
BOARD_KERNEL_OFFSET      := 0x00008000
BOARD_RAMDISK_OFFSET     := 0x03300000                   # ramdisk load 0x43300000
BOARD_KERNEL_TAGS_OFFSET := 0x00000100                   # tags load 0x40000100
BOARD_DTB_OFFSET         := 0x03200000                   # dtb load 0x43200000
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --pagesize $(BOARD_KERNEL_PAGESIZE)
BOARD_MKBOOTIMG_ARGS += --base $(BOARD_KERNEL_BASE)
BOARD_MKBOOTIMG_ARGS += --kernel_offset $(BOARD_KERNEL_OFFSET)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_MKBOOTIMG_ARGS += --dtb_offset $(BOARD_DTB_OFFSET)
# FIX 5 (docs/12, docs/15): vendor_boot's name field must be "arm", as on stock. u-boot reads it and sets its
# "force run 32bit os" flag. Without it, its kernel jump can switch the CPU to AArch64 first, and this kernel is 32-bit.
BOARD_MKBOOTIMG_ARGS += --board arm

# FIX 1 (docs/12): init_boot.img is built by a SEPARATE mkbootimg call (build/make/core/Makefile:1524)
# using INTERNAL_MKBOOTIMG_VERSION_ARGS, which carries only --os_version/--os_patch_level (Makefile:1358)
# and NOT --header_version, plus BOARD_MKBOOTIMG_INIT_ARGS (was empty) -> mkbootimg defaulted init_boot
# to header v0. Stock init_boot is v4; force it so all three images (boot/init_boot/vendor_boot) are v4.
BOARD_MKBOOTIMG_INIT_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
# Required whenever BOARD_PREBUILT_DTBIMAGE_DIR is set. The build routes the dtb into vendor_boot
# (not boot) because BUILDING_VENDOR_BOOT_IMAGE=true. NB: keep this comment on its OWN line — an
# inline comment after the value makes it "true<spaces>", which fails the ==true string compare.
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
# FIX 3 (docs/12): with vendor_boot building, INTERNAL_KERNEL_CMDLINE (= BOARD_KERNEL_CMDLINE,
# board_config.mk:308) feeds vendor_boot's --vendor_cmdline, NOT boot.img (boot cmdline stays empty, as
# stock). The params were previously in BOARD_VENDOR_CMDLINE — a variable the build does not define
# (absent from all of build/make) — so they never reached the image. androidboot.* go in bootconfig
# (FIX 4); only the non-androidboot kernel params belong here.
BOARD_KERNEL_CMDLINE := loop.max_part=4 androidboot.dynamic_partitions=true androidboot.dynamic_partitions_retrofit=true androidboot.selinux=permissive androidboot.dtbo_idx=0,1,2 firmware_class.path=/vendor/etc/firmware printk.devkmsg=on

# GKI-style layout: separate init_boot holds the generic ramdisk (Android 13+)
BOARD_USES_GENERIC_KERNEL_IMAGE := true
BOARD_GKI_NONAB_COMPAT := false
BOARD_USES_RECOVERY_AS_BOOT := false

# FIX 7 (docs/12): the fstab mounts /metadata in first stage, and SwitchRoot must move it into the read-only system
# image, so the directory has to exist there or init dies right after mounting system. Stock's system root has these.
BOARD_USES_METADATA_PARTITION := true
BOARD_ROOT_EXTRA_FOLDERS := Reserve0 customapp treadahead

# Recovery in the vendor_boot ramdisk, the same layout as stock, which has no recovery partition. FIX 8 (docs/12).
BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/etc/fstab.sun50iw15p1

# ---------------------------------------------------------------------------
# vendor_boot.img — header v4, carries the vendor ramdisk + the SoC DTB
# ---------------------------------------------------------------------------
# FIX 4 (docs/12): androidboot.* belong in bootconfig (the 5.15 kernel reads the vendor_boot bootconfig
# section). These were previously in BOARD_VENDOR_CMDLINE (a non-existent build variable), so none
# reached the image and first-stage init had none of them. Values match the stock vendor_boot.
# selinux=permissive matches stock — our vendor sepolicy is a placeholder, so ENFORCING would deny
# everything at first boot. loop.max_part / firmware_class.path are non-androidboot params -> FIX 3.
# FIX 6 (docs/12): the vendor cmdline and bootconfig must match stock exactly. u-boot adds androidboot.hardware and
# androidboot.dtbo_idx to the bootconfig itself, so defining them here made the kernel reject the WHOLE bootconfig
# ("Failed to parse bootconfig: Value is redefined"), and first-stage init lost force_normal_boot, slot_suffix, etc.
BOARD_BOOTCONFIG += androidboot.load_modules_parallel=true
BOARD_BOOTCONFIG += androidboot.selinux=permissive
# A fatal first-stage or init error reboots to recovery, not u-boot fastboot, which the PC could not see.
BOARD_BOOTCONFIG += androidboot.init_fatal_reboot_target=recovery
BOARD_INCLUDE_RECOVERY_DTBO := true
# Prebuilt dtbo (device tree overlays, dtbo_idx 0,1,2) recovered from the stock dtbo_a partition with
# its AVB footer stripped (avbtool erase_footer -> clean 4 KiB dtbo table; the build re-adds AVB).
# Required: `dtbo` is in AB_OTA_PARTITIONS, so the OTA image check asserts a dtbo.img exists
# (add_img_to_target_files.py CheckAbOtaImages) — without this it fails "Failed to find dtbo.img".
BOARD_PREBUILT_DTBOIMAGE := $(DEVICE_PATH)/prebuilt/dtbo.img

# ---------------------------------------------------------------------------
# Partition sizes (bytes) — from /dev/block/by-name on the device
# ---------------------------------------------------------------------------
BOARD_BOOTIMAGE_PARTITION_SIZE        := 67108864
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE  := 8388608
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 33554432
BOARD_DTBOIMG_PARTITION_SIZE          := 2097152
BOARD_FLASH_BLOCK_SIZE := 131072

# ---------------------------------------------------------------------------
# Dynamic partitions (super) — A/B, 2.56 GB, logical: system/system_ext/product/vendor/*_dlkm
# ---------------------------------------------------------------------------
BOARD_SUPER_PARTITION_SIZE := 2684354560
BOARD_SUPER_PARTITION_GROUPS := aw_dynamic
# super size - 4 MiB overhead. Sized for Virtual A/B (one partition set in super); do NOT halve.
# Consumed by Make's group lookup (BOARD_<GROUP>_SIZE) -> lpmake, so no trailing whitespace.
BOARD_AW_DYNAMIC_SIZE := 2680160256
BOARD_AW_DYNAMIC_PARTITION_LIST := system system_ext product vendor vendor_dlkm system_dlkm
TARGET_USES_UPDATE_ENGINE := true
AB_OTA_UPDATER := true
# OTA partitions = physical boot/vbmeta set + the LOGICAL dynamic partitions (not `super` itself).
# With dynamic partitions, update_engine updates the logical partitions inside super via snapshots;
# `super` is never an AB_OTA partition. Listing `super` here made CheckAbOtaImages demand a super.img
# (add_img_to_target_files.py:749). Use $(BOARD_AW_DYNAMIC_PARTITION_LIST) = system system_ext product
# vendor vendor_dlkm system_dlkm (defined just above).
AB_OTA_PARTITIONS += boot init_boot vendor_boot dtbo vbmeta vbmeta_system vbmeta_vendor $(BOARD_AW_DYNAMIC_PARTITION_LIST)

# ---------------------------------------------------------------------------
# Filesystems (from fstab.sun50iw15p1)
# ---------------------------------------------------------------------------
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := erofs
# No quotes: Soong wraps string board vars in quotes when writing soong.variables, so a quoted
# value here becomes ""lz4hc,9"" (invalid JSON) and fails soong bootstrap. Plain value only.
BOARD_EROFS_COMPRESSOR := lz4hc,9
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_VENDOR_DLKM := vendor_dlkm
TARGET_COPY_OUT_SYSTEM_DLKM := system_dlkm

# ---------------------------------------------------------------------------
# Kernel modules (DLKM) — load order recovered from the device
# ---------------------------------------------------------------------------
# First-stage (vendor_boot ramdisk): firmware/kernel/modules.load.first_stage  (12)
# vendor_dlkm: firmware/kernel/modules.load.vendor_dlkm  (77, incl. mali_kbase, aic8800_*, motor-control)
# Prebuilt .ko extracted from the device (81 modules), with the device's load order:
BOARD_VENDOR_KERNEL_MODULES := $(wildcard $(DEVICE_PATH)/prebuilt/modules/*.ko)
BOARD_VENDOR_KERNEL_MODULES_LOAD := $(strip $(shell cat $(DEVICE_PATH)/prebuilt/modules/modules.load 2>/dev/null))

# First-stage modules go in the vendor_boot ramdisk (early display/panel/backlight + bootevent) so
# first-stage init can load them. Without this, nothing is staged into out/.../vendor_ramdisk, the
# dir is never created, and mkbootfs fails: "cannot open directory '.../vendor_ramdisk'". The .ko are
# the same prebuilt set; the first_stage list just selects which 12 load from the ramdisk (they also
# exist in vendor_dlkm for second stage — different partitions, no collision).
BOARD_VENDOR_RAMDISK_KERNEL_MODULES := $(addprefix $(DEVICE_PATH)/prebuilt/modules/,$(shell cat $(DEVICE_PATH)/modules.load.first_stage 2>/dev/null))
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD := $(strip $(shell cat $(DEVICE_PATH)/modules.load.first_stage 2>/dev/null))

# ---------------------------------------------------------------------------
# AVB / Verified Boot — stock chains vbmeta_system + vbmeta_vendor
# ---------------------------------------------------------------------------
BOARD_AVB_ENABLE := true
# --flags 2 = HASHTREE_VERIFICATION_DISABLED (dm-verity off) for bring-up. Comment on its OWN line to
# avoid the trailing-whitespace trap in the arg value. TODO(release): sign with your own key, drop flag.
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 2

# Chained vbmeta partitions. Stock chains vbmeta_system + vbmeta_vendor off the top-level vbmeta
# (Rollback Index Location 1 and 2). Both are listed in AB_OTA_PARTITIONS, so these images MUST be
# built or CheckAbOtaImages fails ("Failed to find vbmeta_system.img"). Setting these makes the build
# emit vbmeta_system.img / vbmeta_vendor.img and chain them from the main vbmeta automatically.
# Test key (matches the unlocked/UNOFFICIAL build); swap for your own release key later. Grouping is
# not boot-critical here because --flags 2 disables dm-verity; the images just need to exist/be valid.
# A chained vbmeta needs ALL FOUR of KEY_PATH/ALGORITHM/ROLLBACK_INDEX/ROLLBACK_INDEX_LOCATION
# (build/make/core/Makefile _check-and-set-avb-chain-args). _ROLLBACK_INDEX is the index VALUE (0 for
# bring-up); _ROLLBACK_INDEX_LOCATION is its slot in the top vbmeta (1 and 2, matching stock).
BOARD_AVB_VBMETA_SYSTEM := system system_ext product
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_VBMETA_SYSTEM_ALGORITHM := SHA256_RSA2048
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX := 0
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX_LOCATION := 1

BOARD_AVB_VBMETA_VENDOR := vendor vendor_dlkm
BOARD_AVB_VBMETA_VENDOR_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_VBMETA_VENDOR_ALGORITHM := SHA256_RSA2048
BOARD_AVB_VBMETA_VENDOR_ROLLBACK_INDEX := 0
BOARD_AVB_VBMETA_VENDOR_ROLLBACK_INDEX_LOCATION := 2

# ---------------------------------------------------------------------------
# SELinux — ship ENFORCING (stock is permissive via cmdline; we fix that)
# ---------------------------------------------------------------------------
# Vendor sepolicy will need porting; start from firmware/vendor-dump/vendor/etc/selinux.
# (Comment on its own line: a trailing inline comment leaves trailing spaces in the path value.)
# TODO: populate $(DEVICE_PATH)/sepolicy/vendor with ported *.te. Empty for now (placeholder dir
# keeps the wildcard valid); an empty vendor policy builds fine but means ENFORCING will deny a lot
# at first boot — see "Known, not-yet-handled".
BOARD_VENDOR_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor

# ---------------------------------------------------------------------------
# Vendor blobs shipped as-is (wholesale vendor-partition copy)
# ---------------------------------------------------------------------------
# Our proprietary blobs (hundreds of ELF .so + vendor/bin executables) are installed via
# PRODUCT_COPY_FILES (hermes-vendor.mk), not as Soong cc_prebuilt_* modules. Android's build
# normally rejects ELF files in PRODUCT_COPY_FILES ("found ELF prebuilt in PRODUCT_COPY_FILES,
# use cc_prebuilt_binary / cc_prebuilt_library_shared instead", build/make/core/Makefile:152).
# Allowing it is the standard approach for a device tree that copies the stock vendor image
# wholesale: converting every blob to a cc_prebuilt module would be enormous AND would trip
# Soong's symbol/NEEDED-dependency checks that stock over-captured blobs routinely fail.
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true

include device/allwinner/hermes/BoardConfigVendor.mk

# Stock's patch levels. The stock keymint reads them at startup and aborts if they're empty (docs/12, FIX 12).
VENDOR_SECURITY_PATCH := 2024-06-05
BOOT_SECURITY_PATCH := 2024-06-05
