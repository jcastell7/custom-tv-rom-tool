# device/allwinner/hermes

LineageOS device tree **scaffold** for the Allwinner **H723** (sun50iw15p1) "hermes" smart
projector. Built from the stock-firmware extraction (see `docs/`). This is a starting skeleton,
not yet a buildable tree — TODOs below.

## What's scaffolded (this step: vendor_boot + recovered config)
| File | Source | Status |
|---|---|---|
| `BoardConfig.mk` | dumped boot/vendor_boot headers, partition table, fstab | boot/vendor_boot/arch/partitions/AVB/filesystems filled from real values |
| `hermes_defconfig` | `/proc/config.gz` (exact kernel .config) | ready as `TARGET_KERNEL_CONFIG` |
| `rootdir/etc/fstab.sun50iw15p1` | vendor partition | real first-stage fstab |
| `prebuilt/dtb/sun50iw15p1.dtb` | vendor_boot image | SoC DTB (source in `firmware/extracted/dts/vendor_boot.dts`) |
| `modules.load.{first_stage,vendor_dlkm}` | device | kernel-module load order (12 / 77) |
| `AndroidProducts.mk`, `lineage_hermes.mk`, `device.mk` | — | minimal Android TV product skeleton |

### Key facts baked into BoardConfig
- **32-bit ARM only** (`armeabi-v7a`, cortex-a7; no 64-bit).
- boot/vendor_boot **header v4**, pagesize 2048, base 0x40000000 (kernel+0x8000, ramdisk+0x3300000,
  tags+0x100, dtb+0x3200000).
- Dynamic `super` 2.56 GB, A/B, logical: system/system_ext/product/vendor/vendor_dlkm(**erofs**)/system_dlkm.
- Generic ramdisk in **init_boot** (GKI-style); DTB in vendor_boot.
- SELinux cmdline `permissive` **deliberately dropped** → target enforcing (docs/02 #1).
- Truthful fingerprint (not the spoofed stock ADT-3 one, docs/02 #7).

## TODO before this builds
1. **Kernel source** at `kernel/allwinner/hermes` (5.15.167 arch/arm sunxi) — see
   `firmware/kernel/KERNEL-SOURCE.md`. Drop `hermes_defconfig` into `arch/arm/configs/`.
2. **Proprietary blobs**: run extract-utils against `vendor/allwinner/hermes/` (the
   `proprietary-files.txt` + staged `proprietary/` are ready) to generate `hermes-vendor.mk` +
   `BoardConfigVendor.mk`.
3. **VINTF**: add `manifest.xml` / `compatibility_matrix.xml` from `firmware/vendor-dump/vendor/etc/vintf/`.
4. **sepolicy**: port `firmware/vendor-dump/vendor/etc/selinux` into `sepolicy/vendor/` for enforcing.
5. **init/rootdir**: import the recovered `init.*.rc` (display, stepper-motor, gpu.mali, ir, …) from
   `firmware/extracted/vendor_boot_a/.../` and `firmware/vendor-dump/vendor/etc/init/`.
6. Confirm `BOARD_KERNEL_IMAGE_NAME` (stock kernel image is non-standard 32-bit ARM).
7. Build/sign your own **AVB** keys; the device is unlocked so dev verity can be disabled.
