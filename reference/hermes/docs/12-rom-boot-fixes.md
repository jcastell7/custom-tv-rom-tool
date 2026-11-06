# LineageOS boot-chain fixes — why slot `_a` didn't boot

**Branch:** `fix/boot-chain-vendor-ramdisk`

> **Update: where the boot stops.** Streaming `d` on UART turns on boot0's debug mode, and u-boot then logs past
> `Hit any key`. The last lines of the failing boot, with no `Starting kernel`:
> ```
> [05.215]partinfo: name boot_a, start 0x32400, size 0x20000
> [05.549]vbmeta hash is 8c26b299...
> [05.566]ramdisk use init boot
> ```
> **So the stop is in u-boot, before the kernel, at `init_boot`.** Leading suspect: **FIX 1**. u-boot's code
> ([`15`](15-uboot-reverse-engineering.md)) shows that with `init_boot` header v0–2 it falls back to fields of the v4
> `boot` header, making the "ramdisk size" that header's `os_version`, about **448 MiB**. Fixed build: v4, 2.3 MiB. An
> earlier note here said 256 MiB from offset 12; that was the wrong field. The branch is read from code. That it causes
> the stop is still inferred: **no rebuilt image has run on hardware**.
>
> **FIX 2–4 are untested.** Their effects come after this point, so the log says nothing about them. Later stops
> are possible. Read "fix" below as "made to match stock".

The flashed LineageOS `_a` did not boot, with no adb or fastboot. The differences below were found **without the
donor**, by diffing our build output against the stock `_a` backup. This doc records every change, the reasoning,
and the outcome — including approaches that did **not** work.

## How it was diagnosed
Compared `out/target/product/hermes/{boot,init_boot,vendor_boot}.img` vs
`firmware/partitions/{…}_a.img` with `unpack_bootimg`, a header parser, and `lz4`/`gzip`+`cpio`.

| image | stock `_a` | our build (before) | defect |
|---|---|---|---|
| boot | v4, kernel 37,182,368 B | v4, **same** kernel | none (prebuilt kernel reused) |
| init_boot | **header v4**, ramdisk 3.58 MB | **header v0** | wrong header version |
| vendor_boot ramdisk | 17.5 MB, **includes recovery and fastbootd**, plus `first_stage_ramdisk/fstab` | 154 KB, modules only, **no fstab** | no first-stage fstab; no recovery (not fixed, see below) |
| vendor_boot cmdline | full `androidboot.*` | `" bootconfig"` | params never reached image |
| bootconfig | `selinux=permissive`, `load_modules_parallel` | `hardware=` only | not permissive |

The wrong `init_boot` header is the leading suspect for the observed stop (see the update above). Once the kernel
is reached, the most serious difference is **no `fstab` in any boot ramdisk**, so first-stage init could not mount
system/vendor/super. Stock's first-stage `modules.load` is the same 12 display modules we ship.

### Differences still NOT fixed
- **No recovery and no fastbootd.** Stock's `vendor_boot` ramdisk has `system/bin/recovery`,
  `system/bin/fastbootd`, `init.recovery.sun50iw15p1.rc`, `res/` and the recovery UI libraries. Ours has only
  `lib/` and `first_stage_ramdisk/`. Until this changes, the build has no recovery to enter and no
  `adb reboot fastboot` target. See [`14`](14-power-key-boot-trigger.md).
- **Stock also has the fstab at `init_boot:/fstab.sun50iw15p1`** (identical to its first-stage copy). Ours has it
  only in `vendor_boot:/first_stage_ramdisk/`. Probably not needed on a normal boot, but it is a difference.

## Fixes (device/allwinner/hermes/) — all VERIFIED in the rebuilt images

### FIX 1 — init_boot header v0 → v4  (`BoardConfig.mk`)  ✅ verified (init_boot.img = v4)
init_boot is built by a separate mkbootimg call using `INTERNAL_MKBOOTIMG_VERSION_ARGS`, which sets only
`--os_version/--os_patch_level` (Makefile:1358) — no `--header_version` — plus `BOARD_MKBOOTIMG_INIT_ARGS`
(was empty) → mkbootimg defaulted to **v0**.
Fix: `BOARD_MKBOOTIMG_INIT_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)`

### FIX 2 — fstab into vendor_boot first_stage_ramdisk  (`Android.mk` + `device.mk`)  ✅ verified
The fstab was only copied to `/vendor/etc` (second stage); it was absent from the boot ramdisks, so
first-stage mount had none. Final fix: a **Make prebuilt** installed to
`$(TARGET_VENDOR_RAMDISK_OUT)/first_stage_ramdisk`, i.e. `vendor_boot:/first_stage_ramdisk/fstab.sun50iw15p1`
— one of the two places stock ships it. `PRODUCT_PACKAGES += fstab.sun50iw15p1` in device.mk. The `/vendor/etc`
copy (second stage) is left to `vendor/allwinner/hermes/hermes-vendor.mk`.

**Approaches that did NOT work (kept for the record):**
1. `prebuilt_etc { vendor: true; vendor_ramdisk_available: true }` → **Soong-vs-Make install collision**
   on `/vendor/etc/fstab.sun50iw15p1` (hermes-vendor.mk already installs it there). Also the ramdisk copy
   landed in `vendor_ramdisk/system/etc`, not the root.
2. Added `install_in_root: true` → **`unrecognized property`** in this Soong version.
3. `prebuilt_root { ramdisk_available; vendor_ramdisk_available }` → installed under `<img>/system/…`,
   not the ramdisk root, and wasn't pulled into the image.
4. **Make `BUILD_PREBUILT` with `LOCAL_MODULE_PATH := $(TARGET_VENDOR_RAMDISK_OUT)/first_stage_ramdisk`**
   → correct path, confirmed present in the rebuilt vendor_boot. ✅

### FIX 3 — vendor_boot cmdline params  (`BoardConfig.mk`)  ✅ verified
The params were in `BOARD_VENDOR_CMDLINE`, **a variable the build system does not define** (absent from
all of build/make). The vendor_boot cmdline comes from `INTERNAL_KERNEL_CMDLINE := $(BOARD_KERNEL_CMDLINE)`
(board_config.mk:308). Fix: `BOARD_KERNEL_CMDLINE := loop.max_part=4 firmware_class.path=/vendor/etc/firmware`
(non-`androidboot` kernel params; with vendor_boot building this feeds `--vendor_cmdline`, not boot.img).
Verified cmdline: `loop.max_part=4 firmware_class.path=/vendor/etc/firmware bootconfig`.

### FIX 4 — androidboot.* + SELinux permissive via bootconfig  (`BoardConfig.mk`)  ✅ verified
`androidboot.*` belong in bootconfig (the 5.15 kernel reads the vendor_boot bootconfig section). Added
`dynamic_partitions`, `dynamic_partitions_retrofit`, `dtbo_idx=0,1,2`, `load_modules_parallel`, and
**`selinux=permissive`** (our vendor sepolicy is a placeholder; stock runs permissive). Verified present
in the vendor_boot bootconfig.

### FIX 5 — vendor_boot name `arm`  (`BoardConfig.mk`)  ✅ verified in the image
`BOARD_MKBOOTIMG_ARGS += --board arm`. Stock's `vendor_boot` name field is `arm`; ours was empty. u-boot uses it to decide whether to
run a 32-bit OS ([`15`](15-uboot-reverse-engineering.md)). Found only by reading u-boot's code. Not yet tested on hardware.

### FIX 6 — vendor cmdline and bootconfig match stock exactly  (`BoardConfig.mk`)  ✅ verified identical
**This corrects FIX 3 and FIX 4, which were wrong.** The first boot of the rebuilt image reached the kernel, then printed
`Failed to parse bootconfig: Value is redefined at 619` and rebooted to the bootloader from first-stage init. u-boot adds
`androidboot.hardware` and `androidboot.dtbo_idx` to the bootconfig itself. FIX 4 defined them too, so the kernel rejected the whole
bootconfig and first-stage init lost `force_normal_boot`, `slot_suffix` and the rest. The cmdline and bootconfig are now the same as stock's:
two bootconfig lines, with the other `androidboot.*` values on the vendor command line.

### FIX 7 — folders first-stage init expects  (`BoardConfig.mk`, `sepolicy/vendor/`)  ✅ worked on hardware
SwitchRoot failed because the system root had no `/metadata`, and the fstab also mounts `/customapp`, `/treadahead` and `/Reserve0`.
Fix: `BOARD_USES_METADATA_PARTITION := true`, `BOARD_ROOT_EXTRA_FOLDERS := Reserve0 customapp treadahead`. The first build then failed on missing SELinux labels for `/Reserve0`, so `file_contexts` and `file.te` label them.

### FIX 8 — own recovery and fastbootd  (`BoardConfig.mk`, `device.mk`, `recovery/root/`)  ✅ worked on hardware
`BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true`, `TARGET_RECOVERY_FSTAB`, `fastbootd`, and the stock USB and IR modules. `hermes_auto_fastbootd` switches recovery to fastbootd 4 s after it starts, and `hermes-boot-watchdog.sh` sends a failed boot there: on the third boot in a row without `sys.boot_completed`, or after 15 minutes. **Remove these before production.** A kernel panic or a hang before init still needs the stick.

### FIX 9 — eBPF programs on the 32-bit kernel  (`packages/modules/Connectivity`)  ⚠️ first attempt incomplete
`netbpfload` rebooted the system when programs failed with `ENOTSUPP` (524). **First attempt:** skip those programs. That let boot continue, but `netd` then aborted in a loop: `Failed to get program from /sys/fs/bpf/netd_shared/prog_netd_skfilter_egress_xtbpf`.
**Cause:** this kernel requires JIT (`BPF_JIT_ALWAYS_ON`) and its 32-bit JIT has no atomic instructions. Our `netd.o` had 38. Stock's `vendor/etc/bpf-override/netd.o` has **none**, so Allwinner removed them as well.
The JIT also has no 64-bit division, which `netd.c` uses to estimate packet counts. Stock's file has no division either.
**Fix:** `bpf_net_helpers.h` defines `__sync_fetch_and_add` as a plain add, and `netd.c` multiplies by `2^24/mss` and shifts, since `mss` is 1428 or 1448 there. A 64-bit modulo in `get_app_permissions` is replaced the same way; a scan of the built `netd.o` for these opcodes now runs before flashing. `offload.c` still divides, by a path-dependent MTU, so tethering offload stays skipped and tethering falls back to software. `lineageos/patches/connectivity-netbpfload-skip-enotsupp.patch` holds both changes. The skip stays for programs nothing depends on.

### FIX 10 — vendor libraries  (`hermes-vendor-extra.mk`)  ✅ vendor HALs stopped crashing
Stock resolved many vendor libraries from its VNDK APEX, which this build doesn't have. Added `.vendor` modules and stock copies. `ro.vndk.version` must stay unset for this reason.

### FIX 11 — HALs, TAs and properties left out of the image  (`hermes-vendor-extra.mk`)  (result below)
Comparing the stock vendor tree with the built image found 94 missing files. The earlier collision fix dropped stock copies of HALs "because AOSP builds them", but never added those AOSP modules, so nothing installed them. So on this boot:
- no composer (`Could not find ...IComposer/default`), no audio HAL;
- no keymint TAs, so `keystore2` aborted (`TEEC_ERROR_ITEM_NOT_FOUND`, then `Cannot connect to Keymint`);
- none of the stock `vendor/build.prop` values, including `ro.hardware.egl=mali`, because that file is generated by our build.

Fix: 66 AOSP modules, the 3 TAs, the IR keylayout, VINTF fragments, and 76 properties. Left out on purpose: `ro.vndk.version`, `ro.incremental.enable` (module not shipped), and stock's `vendor_am` tools. Stock's generated `framework-res` overlay isn't installed yet; it holds settings like `config_useExtconHdmiAudio`, so it's worth revisiting if HDMI audio or low-RAM behaviour differs.

First flash of FIX 11 failed because the new `android.hardware.cas` fragment duplicated the one in the CAS APEX: `VINTF parse error: Conflicting FqInstance`. servicemanager then treats the whole device manifest as null, so `update_verifier` can't find the boot HAL and reboots. Removed the fragment.

### FIX 12 — security patch levels  (`BoardConfig.mk`, `hermes-vendor-extra.mk`)
With the TAs present, keymint got further and aborted in `set_boot_patchlevel` with `stoi: no conversion`: `ro.vendor.build.security_patch` and `ro.vendor.boot_security_patch` were empty. Set both to stock's `2024-06-05`.

### Watchdog counter survives flashing
`/metadata/hermes_bootcount` carried over from earlier builds, so one flash started at "boot attempt 3" and went straight to recovery. Recovery now clears the counter when it starts.

### FIX 13 — Wi-Fi HAL library  (`frameworks/opt/net/wifi/libwifi_hal`)
The unit reached `sys.boot_completed` with Wi-Fi off: `Can not initialize the vendor function pointer table`. The chip is a Seekwave (`skw_sdio_lite`). Stock's `libwifi-hal.so` picks the driver and `libwifi-hal-skw.so` from `/vendor/etc/hwinfo.xml`, and AOSP's build only has a fallback. `libwifi-hal` is now a prebuilt of the stock file. That alone crashed: the AOSP service (AIDL V2) segfaulted at a NULL address in `skw_wifi_get_chip_feature_set`, most likely a function-table mismatch with the stock vendor library. So `android.hardware.wifi-service-lazy` is the stock binary (AIDL V1) with its VINTF fragment as well. Patch: `lineageos/patches/wifi-libwifi-hal-stock-prebuilt.patch`; copy `vendor/lib/libwifi-hal.so` to `libwifi_hal/libwifi-hal-stock.so` when applying.

### FIX 14 — IR remote key layout  (`keylayout/sunxi-ir.kl`)
Android loaded `Generic.kl` for `sunxi-ir`. Stock's `sunxi-ir.kl` names `APPS` and `MOUSE`, which LineageOS doesn't define, and an unknown key name rejects the whole file. `APPS` became `ALL_APPS`, and `MOUSE` (scancode 365) is commented out.

### FIX 15 — Bluetooth crash loop  (`packages/modules/Bluetooth`, `hermes-vendor-extra.mk`)
`com.android.bluetooth` aborted in a loop with `assertion 'was_validated_' failed`, in `OnTransmitPacketCommandComplete`. The chain:
1. The stack sends vendor command `0xfd5e` (logged as `Received UNEXPECTED command status:UNKNOWN_HCI_COMMAND opcode:0xfd5e`). Believed to be Bluetooth Quality Reporting, enabled by `persist.bluetooth.bqr.event_mask=14`, which FIX 11 copied from stock.
2. The Seekwave controller rejects it, and the HCI layer passes the shim an empty view.
3. The shim reads that view and aborts.

**Fix:** remove the BQR properties, and have the shim return a Command Complete with `UNKNOWN_HCI_COMMAND`, so other unsupported vendor commands can't cause the same abort. Patch: `lineageos/patches/bluetooth-shim-invalid-command-complete.patch`.

### FIX 16 — Wi-Fi and Bluetooth chip scan timed out  (`hermes-bringup.rc`, `hermes-wl-retry.sh`)
With FIX 15 in, Bluetooth failed in a new way: `skwbt_boot_open: unable to open`. There was no `/dev/BT*` and no `wlan0`, because the Seekwave driver had unloaded itself:
```
[53.30] skw_sdio_probe: ... SV6160LITE chip
[53.88] skw_sdio_scan_card: wait scan card time out
[54.56] skw_sdio_io_init: scan card fail
```
The console log level was 8 (everything), and `printk.devkmsg=on` adds userspace logs. Console output to the 115200-baud UART is synchronous, and 136 lines were printed in that window, about 1.4 s of output against a scan timeout of about 1 s. An earlier boot got through by luck of timing.

**Tested live:** rerunning `wl_info` on the quieter system loaded the driver and created `/dev/BT*`, `wlan0` and `wlan1`. Bluetooth then reached `state: ON` with its address.

**Fix:** set the console to errors only at `post-fs-data`, before the driver loads, and rerun the loader once after boot if the device is missing. Logs after that stage come from logcat, not UART. Wi-Fi was still down after this, for a separate reason: FIX 17.

### FIX 17 — wpa_supplicant wouldn't start  (`shim/`, patched blobs)
`CANNOT LINK EXECUTABLE ".../wpa_supplicant": cannot locate symbol "sk_dup"`, about once a second. Stock's `wpa_supplicant` and `hostapd` expect a BoringSSL that exported `sk_dup`; ours exports `OPENSSL_sk_dup`.

A scan of all 396 vendor ELF files against their dependencies found only these two binaries with an unresolved symbol, and only this one. String functions resolved through libc were filtered out as false positives.

**Fix:** `libhermes_wpa_shim.so` provides `sk_dup`, and `tooling/vendor-fixups/patch-wpa-blobs.sh` adds it to both blobs with `patchelf --add-needed`. **Rerun that script if the blobs are extracted again.** The blobs in `lineageos/vendor/` are the patched versions.

## Build-invocation gotcha (not a code fix)
Building with a hand-rolled `soong_ui --make-mode` + bare env vars produced a **different product config**
than `lunch` — it dropped the `packages/apps/FMRadio/jni/fmr` Soong namespace
(`vendor/lineage/config/BoardConfigSoong.mk:147`), causing a spurious `libfmjni` "undefined module"
error. **Build via `lunch` + `m`** (neutralizing the benign `fixup_common_out_dir: command not found` that
makes `lunch` return non-zero in a non-interactive shell):
```
source build/envsetup.sh
fixup_common_out_dir() { return 0; }
lunch lineage_hermes-ap2a-userdebug
m -j"$(nproc)" <targets>        # or: m bacon && m superimage
```
Also note Android 14 needs `TARGET_RELEASE=ap2a` (lunch sets it).

## Status
- Targeted boot-image build (boot/init_boot/vendor_boot): **compiles; all 4 fixes verified in the images.**
- Full `bacon` + `superimage` (complete installable set): **DONE (2026-11-05, exit 0, 02:50 incremental).**
  Produced in `out/target/product/hermes/`: `boot.img` (64 MB), `init_boot.img` (8 MB), `vendor_boot.img`
  (32 MB), `dtbo.img` (2 MB), `vbmeta.img`, `vbmeta_system.img`, `vbmeta_vendor.img`, `super.img` (1.12 GB),
  and the OTA/sideload zip `lineage-21.0-20261105-UNOFFICIAL-hermes.zip` (500 MB). All 4 fixes re-verified
  in the **full-build** images: init_boot header=4; `vendor_boot:/first_stage_ramdisk/fstab.sun50iw15p1`
  present; cmdline = `loop.max_part=4 firmware_class.path=/vendor/etc/firmware bootconfig`; bootconfig has
  `selinux=permissive` + `dynamic_partitions` + `dtbo_idx=0,1,2` + `load_modules_parallel`.
- **The ROM compiles and can be flashed. Whether it boots is unknown.** The images are closer to stock's layout,
  not identical to it (see "Differences still NOT fixed").
- On-device boot: **blocked on flashing access** ([`13`](13-fastboot-trigger-no-fel.md)). When testing, have a
  way back first: this build has no recovery of its own.
- A UART capture of **stock** booting, from a donor or a restored unit, would show what normally follows
  `Hit any key` and is the most useful missing comparison.
