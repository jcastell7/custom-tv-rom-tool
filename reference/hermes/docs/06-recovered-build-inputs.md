# Recovered build inputs & full unpack (source-of-truth archive)

Everything unpacked from the stock firmware so we can "call back" later without re-dumping the
device. Allwinner **H723** (`sun50iw15p1`), kernel **5.15.167**, **32-bit ARM**.

## Kernel (`firmware/kernel/`)
See [`../firmware/kernel/KERNEL-SOURCE.md`](../firmware/kernel/KERNEL-SOURCE.md) for the full
write-up and where to get GPL source.
- `config.gz` / `kernel.config` — exact in-kernel `.config` from `/proc/config.gz` (the defconfig).
- `proc_version.txt` — `5.15.167-g9656a7fee7a7-dirty`, Android clang 17.0.2 (LTO/BOLT/PGO).
- `kallsyms.txt` — 173,785 kernel symbols.
- `modules.load.first_stage` (12) and `modules.load.vendor_dlkm` (77) — module load order.

## Boot chain (`firmware/extracted/`)
| Source image | Unpacked to | Contents |
|---|---|---|
| `boot_a.img` | `extracted/boot_a/kernel` | 37 MB 32-bit ARM kernel (embedded gzip/xz payloads ~17.8 MB) |
| `init_boot_a.img` | `extracted/init_boot_a/ramdisk_root/` | **first-stage ramdisk**: `init`, `fstab.sun50iw15p1`, `avb/` |
| `vendor_boot_a.img` | `extracted/vendor_boot_a/vendor_ramdisk00_root/` | **vendor ramdisk** (259 files): `first_stage_ramdisk/fstab.sun50iw15p1`, `lib/modules/` + `modules.load`, recovery init, `ueventd.rc`, `init.rc` |
| `vendor_boot_a.img` | `extracted/vendor_boot_a/dtb` | the live SoC DTB (→ DTS below) |
| `dtbo_a.img` | `extracted/dtbo_a/*.dtb` | 3 device-tree overlays (`androidboot.dtbo_idx=0,1,2`) |

Ramdisks are **LZ4-legacy**; decompressed with `tooling/bin/unlz4_legacy.py` then `cpio`.

## Device tree source (`firmware/extracted/dts/`)
- `vendor_boot.dts` — **111 KB full SoC/board device tree** (`compatible = "allwinner,h723"`).
  Contains the real hardware nodes: panel/display engine, stepper motor, MCU, thermal, sensors,
  GPU (mali), Wi-Fi/BT, clocks, pinctrl — the backbone for a LineageOS `device/allwinner/hermes`.
- `dtbo_00.dts` / `dtbo_01.dts` / `dtbo_02.dts` — board/panel overlays.
Converted from DTB with `tooling/bin/dtb2dts.py` (pure-python `fdt`); split with `split_dtb.py`.

## Filesystems (`firmware/`)
| What | Where | Note |
|---|---|---|
| `/vendor` + `/odm` | `firmware/vendor-dump/` | full driver layer (prior step) |
| `/vendor_dlkm` + `/system_dlkm` | `firmware/vendor-dump/` + `firmware/filesystems/system_dlkm/` | 77 + 4 kernel modules |
| `/product` | `firmware/filesystems/product/` | 92 files (live pull) |
| `/system`, `/system_ext` | **inside `firmware/partitions/super.img`** | not separately unpacked — see below |

### `super.img` / `/system`
`super.img` (2.56 GB raw) is retained and holds the `system`, `system_ext`, `product`, `vendor`,
`*_dlkm` logical partitions. Splitting it needs the downloaded `tooling/bin/lpunpack.py`, which the
sandbox blocked from executing ("Code from External"). To finish it, either approve running that
script, or re-pull `/system` live with:
```
adb exec-out "su 0 tar -cf - -C / system" > system.tar     # ~live pull, large
```
`/vendor`, `/product`, `/system_dlkm` are already extracted above, so nothing projector-critical
is blocked by this.

## Tooling added this step (`tooling/bin/`)
`unpack_bootimg.py` (AOSP), `lpunpack.py` (third-party), `dtb2dts.py`, `split_dtb.py`,
`unlz4_legacy.py`. Python deps installed to `--user`: `fdt`, `extract-dtb`, `lz4`.
