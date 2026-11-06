# Vendor Drivers & HAL Inventory (LineageOS reuse map)

Source: live `/vendor`, `/odm`, `/vendor_dlkm`, `/system_dlkm` dumped to
[`../firmware/vendor-dump/`](../firmware/vendor-dump) (≈100 MB). This is the proprietary blob
set a LineageOS Android TV port must reuse.

## Platform summary

| Item | Value | Porting implication |
|---|---|---|
| SoC | **Allwinner `sun50iw15p1`**, platform **`hermes`**, `ro.hardware=sun50iw15p1` | New-ish sunxi family; no mainline LineageOS tree exists — expect a from-scratch device tree |
| Kernel | **Linux 5.15.167** (GKI-style, `-dirty` = locally patched) | Reuse the vendor kernel + modules; mainlining is a large separate effort |
| Bootloader | **u-boot 2018.07** (A/B, dynamic partitions) | Fastboot/AVB flow must match; bootloader is unlocked (`orange`) |
| **Userspace ABI** | **32-bit only** (`vendor/lib`, 211 `.so`, **no `lib64`**); `armv7l` toybox | **Build LineageOS as a 32-bit-userspace target** (`TARGET_ARCH=arm`). The whole stack is 32-bit ARM (CONFIG_ARM, arch/arm sunxi) — a 64-bit userspace will not work with these blobs |
| Partition scheme | dynamic partitions (`super`): system, system_ext, product, vendor (ext4), **vendor_dlkm (erofs)**, system_dlkm | `BOARD_*` dynamic-partition + erofs settings must mirror `fstab.sun50iw15p1` |
| HAL style | legacy **HIDL** (audio@6.0, composer@2.2, allocator@2.0, bt@1.0, tv.input@1.0, keymint@3.0) | Target an AOSP/LineageOS base whose VINTF matrix accepts these HIDL versions (Android 12/13 era) |

`fstab.sun50iw15p1` (reference for `BoardConfig`/`fstab`): system/system_ext/vendor/product ext4,
`vendor_dlkm` **erofs**, userdata/metadata/customapp ext4, media_data `/oem` vfat.

## HAL services to reuse (`/vendor/bin/hw`) — the proprietary interface layer
`android.hardware.{audio,graphics.allocator@2.0,graphics.composer@2.2}` services, plus
vendor-specific: `android.hardware.media.aw.c2@1.0-service` (Allwinner Codec2 video),
`android.hardware.security.keymint@3.0-service-aw` (Keystore/keymint),
`android.hardware.power-service.aw-v2`, `android.hardware.usb(-gadget)-service.aw`,
`android.hardware.drm-service-lazy.{widevine,clearkey}`, `tvserver`, `tee-supplicant`
(TrustZone), `preload_bt`, `wireless_hwinfo`.

## Crown-jewel SoC blobs (`/vendor/lib/hw/*.hermes.so`) — hardest to replace
| Blob | Size | Function |
|---|---|---|
| `vulkan.hermes.so` | 12.7 MB | **GPU Vulkan driver** (pairs with `mali_kbase.ko`) |
| `hwcomposer.hermes.so` | 263 KB | display composition (HWC) |
| `gralloc.hermes.so` | 59 KB | graphics buffer allocator |
| `audio.primary.hermes.so` | 76 KB | primary audio HAL |
| `tv_input.hermes.so` | 16 KB | TV input (HDMI-in/tuner) |
| `hdmi_cec.hermes.so` | 24 KB | HDMI-CEC |
| `power.hermes.so` | 8 KB | power HAL |

## Kernel modules (`/vendor_dlkm`, `/system_dlkm`) — 77 `.ko`, kernel 5.15.167
| Driver | Module(s) | Notes |
|---|---|---|
| **GPU** | `mali_kbase.ko` | ARM Mali; must match kernel + `vulkan.hermes.so` |
| **Wi-Fi/BT** | `aic8800_fdrv.ko`, `aic8800_bsp.ko`, `aic8800_btlpm.ko` | **AIC8800** combo chip (+ `fmacfw*.bin` firmware) |
| BT (alt) | `bcm_btlpm.ko` | Broadcom BT LPM (+ `bcm*.hcd` firmware) |
| USB | `ehci-sunxi.ko`, `ohci-sunxi.ko` | Allwinner USB host |
| Display | `panel_dsi_gen.ko`, `panel_lvds_gen.ko`, `pwm_bl.ko`, `backlight.ko` | DSI/LVDS panels, backlight |
| Input/remote | `ir-nec-decoder.ko`, `ir-rc5-decoder.ko`, `hid-betopff.ko` | IR remote, gamepad FF |
| Sensors/misc | `kxtj3.ko`, `motor-control.ko`, `pwm-fan.ko`, `mcu_comm_dev.ko`, `hidtvreg_dev.ko` | accel, motor, fan, MCU |
| Net FS | `nfs*.ko`, `cifs*.ko`, `dns_resolver.ko` | optional |
| Ethernet PHY | `pcs_xpcs.ko`, `maxio.ko` | |

## Firmware blobs (`/vendor/etc/firmware`, 172 files)
- **Wi-Fi**: `fmacfw*.bin`, `fw_patch*.bin`, `fw_xr819s_bt.bin`, `aic_userconfig.txt` (AIC8800 / XR819)
- **Bluetooth**: `bcm20710a1.hcd`, `bcm4345c0.hcd`, `bcm4359c0.hcd`, `bcm4362a2.hcd`, `bcm4381a1.hcd`, … (Broadcom patchrams), `bt_sdd.bin`
- Loaded via kernel cmdline `firmware_class.path=/vendor/etc/firmware`

## VINTF (device-advertised HALs) — `/vendor/etc/vintf/manifest.xml`
audio, audio.effect, bluetooth, graphics.allocator, graphics.composer, graphics.mapper,
soundtrigger, tv.input (+ manifest fragments for `drm widevine` and `media c2`). The LineageOS
`compatibility_matrix` must be satisfied by these; mismatches are the usual boot blocker.

## What is NOT in this dump (get later if needed)
- Kernel **source/defconfig** (only compiled modules were captured) — needed to rebuild the kernel.
- Device tree **DTS** (compiled `dtbo_a.img` is in `firmware/partitions/`; decompile with `dtc`).
- `vendor_boot` ramdisk init/fstab details (image is in `firmware/partitions/vendor_boot_a.img`).
