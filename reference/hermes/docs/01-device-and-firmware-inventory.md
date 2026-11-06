# Device & Firmware Inventory

## Device identity

| Property | Value |
|---|---|
| Enumerated model / device | `ADT_3` / `adt3` (Android-TV dev-kit identity) |
| **Actual build** | `h723_evb1-userdebug 14 UP1A.231105.001.A1 eng.<builder>.20260130.160613 release-keys` |
| Android version | **14** |
| Build type | **userdebug** (eng build) |
| Build date | Fri Jan 30 2026 (system: Feb 26 2026) |
| Security patch level | **2024-06-05** (≈20 months behind build date) |
| SoC vendor | **Allwinner / Softwinner** (vendor apps `com.softwinner.*`) |
| OEM | **MSI / Micro-Star** (signing keys `O=Micro-Star, CN=rc`) |
| `ro.build.fingerprint` | `custom,release-keys` (stripped) |
| `ro.system.build.fingerprint` | `ADT-3/adt3/adt3:10/QTT1.200116.002.B6/6245789:user/release-keys` — **impersonates the genuine Google ADT-3 Android 10 image** |
| Active slot | `_a` (A/B device) |

## Verified-boot / security state

| Property | Value | Note |
|---|---|---|
| `ro.boot.verifiedbootstate` | `orange` | bootloader unlocked / custom image |
| `ro.boot.flash.locked` | `0` | flashing not locked |
| `ro.boot.veritymode` | `enforcing` | dm-verity enforcing |
| SELinux (`getenforce`) | **`Permissive`** | MAC not enforced |
| `ro.secure` | `1` | |
| `ro.debuggable` | `1` | userdebug; `adb root` available |
| `ro.adb.secure` | `0` | **ADB host-key auth disabled** |
| `persist.sys.usb.config` | `adb` | adb on by default |

## Partition map (`/dev/block/by-name` → `mmcblk0pN`)

Disk `mmcblk0` = 7.82 GB. A/B slotting on boot chain; dynamic partitions enabled (`super`).

| Partition | Block | Size |
|---|---|---|
| bootloader_a/_b | p1 / p2 | 32 MiB |
| env_a/_b | p3 / p4 | 256 KiB |
| boot_a/_b | p5 / p6 | 64 MiB |
| vendor_boot_a/_b | p7 / p8 | 32 MiB |
| init_boot_a/_b | p9 / p10 | 8 MiB |
| **super** | p11 | **2.56 GiB** (system/vendor/product/system_ext) |
| misc | p12 | 16 MiB |
| vbmeta_a/_b | p13 / p14 | 128 KiB |
| vbmeta_system_a/_b | p15 / p16 | 64 KiB |
| vbmeta_vendor_a/_b | p17 / p18 | 64 KiB |
| frp | p19 | 512 KiB |
| empty | p20 | 15 MiB |
| metadata | p21 | 16 MiB |
| treadahead | p22 | 96 MiB |
| private | p23 | 16 MiB |
| dtbo_a/_b | p24 / p25 | 2 MiB |
| media_data | p26 | 16 MiB |
| **customapp** | p27 | 16 MiB (mounted **rw**, nosuid,nodev) |
| Reserve0_a/_b | p28 / p29 | 16 MiB |
| userdata | p30 | 4.57 GiB (**not extracted** — personal data) |

## Extracted artifacts (SHA-256)

Raw partitions in [`../firmware/partitions/`](../firmware/partitions):

```
42afa4ec…9d1f18  boot_a.img
b830c937…de6ae6  bootloader_a.img
0d98b8a9…a143c0  dtbo_a.img
59cf315d…c93a9…  env_a.img
5564c51e…a566c…  frp.img
2bbbb0e9…896141  init_boot_a.img
e34cc1f6…d2148a  metadata.img
cb5236b6…c114a…  misc.img
93499355…9943b8  super.img
d57cc527…6799aa  vbmeta_a.img
baea9061…37ce3e  vbmeta_system_a.img
9887f955…f259a2  vbmeta_vendor_a.img
596234b6…bba879  vendor_boot_a.img
```
(full hashes: `sha256sum firmware/partitions/*.img`)

Other locations:
- `firmware/extracted/boot_a/` — REA/unblob carve of the boot image (kernel + ramdisk blobs)
- `firmware/device-state/` — `getprop.txt`, `propfiles/`, `apk-inventory.txt`, `otacerts/`
- `firmware/apks/` — pulled custom OEM APKs
- `firmware/analysis/manifests/`, `firmware/analysis/jadx-ota/` — decoded manifests, decompiled OTA

## APK inventory

130 APKs total (`firmware/device-state/apk-inventory.txt`). Notable **custom/OEM** apps reviewed:

| APK | Package | Signer | Runs as system |
|---|---|---|---|
| Ota_common_release_v5.51.00 | `com.vsoontech.mos.ota` | MSI `rc` | **yes** |
| AppMarket_release_auth_v1.33 | `com.vsoontech.mos.market` | MSI `rc` | no |
| MosAppStore_comm_release_v5.31 | (Mos app store) | MSI `rc` | **yes** |
| Launcher_release_v7.21.00_auth | (launcher) | MSI `rc` | no |
| AwTvFactoryMenu | `com.softwinner.tv.factorymenu` | MSI `rc` | **yes** |
| FacTest | (factory test) | MSI `rc` | **yes** |
| GSettings | `com.gls.Gsettings` | MSI `rc` | **yes** |

All seven share the MSI "Research Center `rc`" app-signing cert
(SHA-256 `16af60cf…0d749`). Pre-installed third-party apps also present under
`/system/preinstall/` (Facebook, AmazonPrimeVideo, AirPin, Magis, YouTube).
