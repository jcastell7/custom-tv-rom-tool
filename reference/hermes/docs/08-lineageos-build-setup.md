# LineageOS build setup — H723 "hermes" projector

Everything needed to **start building** is now assembled. Base: **LineageOS 21 (Android 14)** to
match the device's Android-14 vendor blobs. Kernel: **prebuilt** (the one extracted from the
device) — no kernel source required to get started.

## What's ready in this repo (`lineageos/`)
```
lineageos/
├── device/allwinner/hermes/     # device tree (BoardConfig, product mk, prebuilt kernel+dtb+modules,
│                                #  fstab, VINTF manifest, sepolicy reference, extract scripts)
├── vendor/allwinner/hermes/     # 827 proprietary blobs + proprietary-files.txt (the driver layer)
├── kernel/allwinner/hermes-reference/   # H726 CCU/pinctrl/DTS reference (ONLY for source builds)
└── local_manifests/hermes.xml   # how to graft the above into a LineageOS checkout
```
Key design choices (see `device/allwinner/hermes/README.md`):
- **Prebuilt kernel** = `firmware/extracted/boot_a/kernel` (`TARGET_PREBUILT_KERNEL`), prebuilt DTB,
  and the **81 `.ko`** from the device. All drivers work as-is; no bring-up.
- 32-bit ARM, boot/vendor_boot header v4, dynamic `super` (A/B, erofs `vendor_dlkm`).
- SELinux **enforcing** target (stock `permissive` cmdline dropped).

## Host prerequisites (build machine)
- Linux, ~400 GB free, 16 GB+ RAM (32 GB better), fast disk.
- `repo`, `git`, and the AOSP build deps (`openjdk`, `bc`, `bison`, `flex`, `libssl-dev`,
  `python3`, `ccache`, …). See the LineageOS "build_prep" page for your distro.
- The `adb`/`fastboot` from this project's `tooling/` are fine for flashing.

## Steps

### 1. Sync LineageOS 21
```
mkdir -p ~/android/lineage && cd ~/android/lineage
repo init -u https://github.com/LineageOS/android.git -b lineage-21.0 --git-lfs
repo sync -c -j$(nproc)          # ~100+ GB, slow — this is the big download
```

### 2. Graft in the hermes trees
```
cp -a <THIS_REPO>/lineageos/device/allwinner/hermes   device/allwinner/hermes
cp -a <THIS_REPO>/lineageos/vendor/allwinner/hermes    vendor/allwinner/hermes
# optional (only if you later build the kernel from source):
cp -a <THIS_REPO>/lineageos/kernel/allwinner/hermes-reference kernel/allwinner/hermes-reference
```
(Android TV base `device/google/atv` comes with LineageOS tv targets; if a build error says it's
missing, add it via `local_manifests/hermes.xml`.)

### 3. Generate the vendor makefiles from the blobs
The blobs are already staged in `vendor/allwinner/hermes/proprietary/`, so run
**`setup-makefiles.sh`** (NOT `extract-files.sh`) — it generates the makefiles from the
in-place blobs without needing a device or dump:
```
cd device/allwinner/hermes
./setup-makefiles.sh
```
This writes `Android.bp` and `hermes-vendor.mk` (plus `Android.mk`/`BoardConfigVendor.mk` if
there's anything that needs them).

> `extract-files.sh` is only for *pulling* blobs out of a raw device/dump (it does a
> `/system/`-prefixed lookup). Against our already-finished `proprietary/` tree it reports
> `file not found in source` for every entry — use `setup-makefiles.sh` instead.

### 4. Build
```
cd ~/android/lineage
source build/envsetup.sh
breakfast hermes                    # lineage-21: resolves to lineage_hermes-ap2a-userdebug
                                    # (the old 2-part `lunch lineage_hermes-userdebug` is INVALID on A14)
mka bacon                           # or brunch hermes (=breakfast+bacon); or mka systemimage vendorimage bootimage
```

### 5. Flash (see docs/07 for detail)
- **Fastboot (USB):** `firmware/backup/fastboot/flash-all.sh` as a model, flashing the LineageOS
  `boot.img`, `vendor.img`/`super`, `dtbo`, `vbmeta` instead of the stock images.
- Keep the stock backup handy to revert.

## Recommended first milestone (de-risk)
Before a full native build, validate the vendor layer per `docs/04` **Phase 1**: boot an
Android-TV GSI (32-bit `arm`) on top of this device's stock `vendor`/`boot`. If graphics
(`hwcomposer/gralloc/vulkan.hermes`), audio and AIC8800 Wi-Fi come up, the native build is a safe
investment.

## If/when you need to BUILD the kernel from source (optional)
Not required for the prebuilt path. If you must modify the kernel:
1. Obtain a 5.15 Allwinner `sun50iw15` tree (request GPL source from the ODM; or extend
   `kernel/allwinner/hermes-reference`, which has the CCU/pinctrl/DTS for the sibling H726).
2. Drop `device/allwinner/hermes/hermes_defconfig` into `arch/arm/configs/`.
3. Switch BoardConfig from `TARGET_PREBUILT_KERNEL` to the `TARGET_KERNEL_SOURCE`/`_CONFIG` block
   (commented there), and confirm `BOARD_KERNEL_IMAGE_NAME`.
