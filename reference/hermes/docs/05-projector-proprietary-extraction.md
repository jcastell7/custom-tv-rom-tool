# Projector proprietary-blob extraction (Allwinner H723 "hermes")

Step 1 of the LineageOS build: extract the proprietary files needed to keep **normal projector
operation**. Output is a ready-to-use LineageOS-style vendor tree.

## Where it is
```
lineageos/vendor/allwinner/hermes/
├── proprietary/            # 827 staged blobs, mirroring on-device partition paths
└── proprietary-files.txt   # 819 annotated entries (projector-critical called out first)
```
Regenerate with (reproducible):
```
tooling/scripts/stage-proprietary.sh        # copies blobs from firmware/vendor-dump → proprietary/
tooling/scripts/gen-proprietary-files.sh     # writes the annotated proprietary-files.txt
```
Source of truth is the on-device dump in `firmware/vendor-dump/` (`/vendor`, `/odm`,
`/vendor_dlkm`, `/system_dlkm`). Strategy: carry the **whole vendor layer** (not a hand-picked
subset) so no projector function silently breaks; the file list groups the critical pieces.

## Correction: no autofocus
Per the device owner, this projector has **no autofocus**. The stepper motor
(`motor-control.ko`, `init.stepper-motor.rc`, `/sys/devices/platform/motor/motor_ctrl`) is
therefore **motorized focus/keystone driven manually** (e.g. from the remote), *not* an AF loop,
and the accelerometer is at most for orientation/auto-keystone. The motor driver is still carried
because it is part of normal operation; omitting it only removes the feature, it never blocks boot.

## Projector subsystem → blob map (the "crucial" set)

| Subsystem | Kernel module(s) | Userspace / config | Notes |
|---|---|---|---|
| **Display / projection engine** | `vs-display.ko`, `tvpanel.ko`, `panel_dsi_gen.ko`, `panel_lvds_gen.ko`, `backlight.ko` | `gralloc.hermes.so`, `hwcomposer.hermes.so`, `init.display.rc`, `vendor/etc/display/**` | TSE tables below are the projection geometry/PQ calibration |
| **Geometry & picture-quality calibration** | — | `vendor/etc/display/dp/tse/**` (`ProjectID_0x00{12,30,40}.TSE`, `pq_custom.TSE`, `projecttable.TSE`, `main/*.TSE`), `vendor/etc/tvconfig/**` (`pq_*`, `panel_config.ini`, `tvpq.db`) | **Per-optical-module** — wrong table = wrong geometry/colour. Keep as-is |
| **GPU** | `mali_kbase.ko` | `vulkan.hermes.so` (12.7 MB), `init.gpu.mali.rc`, `init.gpu.property.rc` | Mali; must match kernel |
| **Companion MCU** (power, HDMI-CEC, wake, GPIO, optics) | `mcu_comm_dev.ko` | `libhalmcu.so` (`Thal_MCU_*`), `libhalspi.so` | MCU over SPI; `libhalmcu` also owns CEC & power-on mode |
| **Motorized focus/keystone** (manual) | `motor-control.ko` | `init.stepper-motor.rc` → `/dev/motor`, `motor_ctrl` sysfs | `motor-limiter.ko` is referenced by the rc but **absent on the device** (dangling insmod, harmless) |
| **Thermal / fan** (light-source cooling — safety critical) | `pwm-fan.ko` | `vendor/etc/thermal_info_config.json`, `power.hermes.so` | Do not drop — LED/lamp overheats without it |
| **Sensors** (orientation / keystone) | `sc7a20h.ko`, `kxtj3.ko`, `stk.ko` | `android.hardware.sensors@2.0-service`, `vendor/etc/gsensor.cfg` (selects `sc7a20h`) | `stk.ko` = ambient-light/proximity |
| **Audio** | `snd_alsa_trid.ko` | `audio.primary.hermes.so`, `libhalsound.so`, `libalsautils.so`, `android.hardware.audio.service` | |
| **Wi-Fi / BT** | `aic8800_fdrv.ko`/`_bsp`/`_btlpm`, `bcm_btlpm.ko` | `vendor/etc/firmware/*` (AIC8800/XR819 fw, Broadcom `*.hcd`), `wpa_supplicant`, `hostapd`, `wifi-service-lazy` | AIC8800 is the primary radio |
| **IR remote / input** | `ir-nec-decoder.ko`, `ir-rc5-decoder.ko`, `hid-betopff.ko` | `init.ir.rc`, `init.input.rc` | remote control |
| **Video codecs / DRM** | — | `android.hardware.media.aw.c2@1.0-service` (Allwinner Codec2), Widevine/ClearKey drm services | |

## Install notes for the device tree (`BoardConfig.mk`)
- `/vendor/lib/modules` on-device is a **symlink → `/vendor_dlkm/lib/modules`**; the staged files
  are the real `vendor_dlkm` modules. Install them via `BOARD_VENDOR_KERNEL_MODULES` /
  `vendor_dlkm`, honouring load order in `vendor_dlkm/lib/modules/modules.load`.
- `vendor_dlkm` is **erofs** (`BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := erofs`).
- 32-bit userspace (`TARGET_ARCH := arm`, no `lib64`).
- Feed `proprietary-files.txt` to LineageOS `extract-utils` (`setup-makefiles.sh`) to emit
  `Android.mk` / `<device>-vendor.mk`; the staged `proprietary/` is the blob source, so
  `extract-files.sh --only-target` can copy straight from it (no second device pull needed).

## Still required before a build (not proprietary blobs)
- **Kernel source + defconfig** for 5.15.167 (only compiled `.ko` were captured).
- **Device tree source**: decompile `firmware/partitions/dtbo_a.img` and the dtb inside
  `boot_a.img`/`vendor_boot_a.img` with `dtc` to recover panel/motor/sensor/thermal nodes.
- `vendor_boot` ramdisk `fstab`/init for the first-stage mount config.

See [`04-lineageos-porting-plan.md`](04-lineageos-porting-plan.md) for the full build roadmap.
