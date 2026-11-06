# LineageOS Android TV port — plan (Allwinner `sun50iw15p1` / `hermes`)

Goal: build a LineageOS **Android TV** image for this box, reusing the extracted proprietary
drivers. This is the roadmap grounded in what was actually found in the firmware (see
[`03-vendor-drivers-and-hal-inventory.md`](03-vendor-drivers-and-hal-inventory.md)).

## Reality check first
- **No existing LineageOS tree** targets `sun50iw15p1`/`hermes`; this is a **new bring-up**, not a
  "sync and build". Allwinner sunxi support in LineageOS is limited and community-driven.
- The vendor userspace is **32-bit**, kernel **5.15.167** is a **vendor fork** (`-dirty`), and the
  HALs are **HIDL**. The device ships **Android 14 (SDK 34)**, so use a **LineageOS 21 (Android 14)**
  base — it matches the vendor blobs' VINTF/HAL versions exactly. (Android 14 still supports these
  HIDL HALs.) Going to a much newer/AOSP-only-HAL base would fight these blobs.
- Easiest path to a *bootable* result is a **GSI/“treble” style** approach reusing this `vendor`
  partition; a fully native LineageOS device tree is more work but is the real end state.

## Recommended two-phase approach

### Phase 1 — Prove the vendor blobs boot a generic Android TV GSI (low risk, fast feedback)
1. Keep this device's **`boot`, `vendor_boot`, `dtbo`, `vendor`, `vendor_dlkm`** as-is (already in
   `firmware/partitions/` and `firmware/vendor-dump/`).
2. Flash an **Android TV GSI** (or LineageOS GSI, 32-bit `arm` / `arm_a` variant) to `system`.
3. Boot. If it comes up, the vendor/HAL/VINTF layer is reusable → a native device tree is viable.
   This validates graphics (`hwcomposer/gralloc/vulkan.hermes`), audio, and AIC8800 Wi-Fi before
   investing in a device tree.

### Phase 2 — Build a proper LineageOS device tree
Create the standard trees for a Lineage bring-up:

```
device/allwinner/hermes/      # device tree (BoardConfig.mk, device.mk, fstab, sepolicy, overlays)
vendor/allwinner/hermes/      # proprietary blobs from firmware/vendor-dump (+ proprietary-files.txt)
kernel/allwinner/hermes/      # kernel 5.15.167 source + defconfig (NOT yet extracted)
```

Key `BoardConfig.mk` settings dictated by the findings:
- `TARGET_ARCH := arm` / `TARGET_2ND_ARCH` unset — **32-bit userspace**.
- `TARGET_KERNEL_VERSION := 5.15`, GKI/DLKM modules from `vendor_dlkm`.
- Dynamic partitions group sized to `super` (2.56 GB); `BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := erofs`.
- `BOARD_KERNEL_CMDLINE` mirroring `/proc/cmdline` **except remove `androidboot.selinux=permissive`**
  (ship enforcing — see security note below), `firmware_class.path=/vendor/etc/firmware`.
- PRODUCT package = Android **TV** (`aosp_tv` / `lineage_tv` base, Leanback launcher, TvSettings).

Blob extraction: build `proprietary-files.txt` from `firmware/vendor-dump/vendor` covering:
- `lib/hw/*.hermes.so` (+ `vulkan.hermes.so`), `bin/hw/*-service*`, the HIDL `*-impl.so`,
- `etc/firmware/*` (AIC8800/XR819 Wi-Fi + Broadcom BT), `etc/vintf/*`, `etc/init/*`,
- `vendor_dlkm`/`system_dlkm` `*.ko` (77 modules incl. `mali_kbase`, `aic8800_*`).
Keep them under `vendor/allwinner/hermes` and let `extract-files.sh` pin them.

## Hard dependencies still to acquire
1. **Kernel source + defconfig for 5.15.167** — only compiled `.ko` were captured. Needed to
   rebuild `boot`/modules and to change the cmdline. Sources: Allwinner BSP / the ODM (MSI). If
   unavailable, you can *reuse the prebuilt `boot_a.img` + modules as-is* in Phase 1.
2. **DTB/DTS** — decompile `firmware/partitions/dtbo_a.img` and the dtb in `boot`/`vendor_boot`
   with `dtc` to recreate the device tree overlays.
3. **AVB/verity keys** — the device is unlocked (`orange`), so you can sign with your own AVB key
   or disable verity for development.

## Suggested next steps I can do now
- Decompile `dtbo_a.img` + `boot_a.img`/`vendor_boot_a.img` (unpack ramdisk, dtb → dts) to recover
  the device tree, fstab, and init — the backbone of `device/allwinner/hermes`.
- Unpack `super.img` (needs `lpunpack`/erofs tools) to diff the shipped `system` vs. a GSI.
- Generate a first-cut `proprietary-files.txt` from `firmware/vendor-dump`.

## Security carry-over for YOUR build (don't inherit these)
The stock image's weaknesses (see (security notes, not included here)) are things
to **fix**, not reproduce, in a LineageOS build:
- Ship **SELinux enforcing** (drop `androidboot.selinux=permissive` from the cmdline; write proper
  `sepolicy` for the vendor services instead of running permissive).
- Set `ro.adb.secure=1`, `user` build type, truthful fingerprint.
- Replace the MSI `rc` signing/OTA keys with **your own** release + AVB keys.
- The reused `vendor` HALs are closed blobs — treat them as untrusted-ish; the `libP2pDownload.so`
  / vsoontech OTA stack from the stock apps should **not** be carried into a clean build.
