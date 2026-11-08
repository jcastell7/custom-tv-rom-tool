# Every build error we hit

> **⚠️ WARNING: this process could very well fully and permanently brick your device.** Only use it on a device you own and can afford to lose. It's provided as is, with no warranty, and **we accept no responsibility** for how it's used or what happens. Not affiliated with LineageOS in any way: we just use and recommend their work, so [please donate to them](https://lineageos.org/about/) when you can. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

These all happened on the first device, in rough order. They're compiled from the project's notes (`reference/hermes/docs/09-build-commands.md`), the session's build logs, and the logs the user supplied. For errors on the device after flashing, see [`05-DEBUG-CATALOG.md`](05-DEBUG-CATALOG.md).

**Where to find the real error:** the terminal only shows the end. Read `out/error.log`, or `zcat out/verbose.log.gz`. Look for the first `FAILED:` or `error:`. Text after it is often just fallout: `Device hermes not found`, for instance, follows any `dumpvars` failure.

**kati stops at the first collision.** Fixing them one at a time costs a build each. Batch them, as described under "Install collisions".

## Which stage failed

| Message includes | Stage | Usual cause |
|---|---|---|
| `dumpvars failed` | Product and board config | Syntax or a bad variable in your `.mk` files |
| `soong bootstrap failed`, `build.<product>.ninja` | Soong analysis | `Android.bp` problems: duplicate or undefined modules |
| `ckati failed`, `finishing legacy Make module parsing` | Make parsing | Collisions, bad `PRODUCT_PACKAGES`, VINTF copies |
| `ninja failed` | Compiling and packaging | A specific step. Read its `FAILED:` line |

## Setup and invocation

| Error | Cause | Fix |
|---|---|---|
| `Invalid lunch combo: lineage_x-userdebug` | Android 14 lunch has three parts | `lunch lineage_x-ap2a-userdebug`, or `breakfast x` |
| `No release config set for target; please set TARGET_RELEASE` | Built without lunch | Use `lunch` |
| `FMRadio depends on undefined module libfmjni` | Hand-rolled `soong_ui` gives a different config, losing a Soong namespace | Use `lunch` and `m`. **Not caused by your device tree** |
| `fixup_common_out_dir: command not found`, lunch returns non-zero | Non-interactive shell | Define `fixup_common_out_dir() { return 0; }`. `tools/40-build.sh` does this |
| `device/google/atv` missing | TV base not synced | Add it through `local_manifests` |
| `Trying dependencies-only mode on a non-existing device tree?` | roomservice, for a local tree | **Harmless**, ignore it |
| `<blob>: file not found in source` (819 times) from `extract-files.sh` | Wrong script for already-staged blobs | Use `setup-makefiles.sh` |

## Your `.mk` files

| Error | Cause | Fix |
|---|---|---|
| Comparisons fail mysteriously, sizes and paths are wrong | **`VAR := true   # comment` keeps the spaces in the value** | Put comments on their own lines. Never after a value |
| `ninja: '/manifest.xml' ... missing and no known rule` | `DEVICE_PATH` is empty in `device.mk`, which is parsed before `BoardConfig.mk`. `$(call my-dir)` also doesn't work there | `DEVICE_PATH := device/x/y` as a literal, at the top of `device.mk`. In inherited `.mk` files use the literal path |
| `soong.<product>.variables did not parse correctly: invalid character` | A string variable wrapped in quotes | No quotes: `BOARD_EROFS_COMPRESSOR := lz4hc,9`. Locate it with `python3 -c 'import json;json.load(open("out/soong/soong.<product>.variables"))'` |
| `This device does not have Treble enabled` | Warning, but the setting matters | `PRODUCT_SHIPPING_API_LEVEL := 34` |
| `includes non-existent modules in PRODUCT_PACKAGES`, `Offending entries:` | Wrong name. Examples: `libcodec2_hidl_plugin.vendor`, `libkeystore-engine-wifi-hidl.vendor` (exists without `.vendor`), `android.hardware.boot-service.default` | Look the name up in `out/target/product/<x>/module-info.json`. Note kati can't create that file after a parse failure |
| `LOCAL_MODULE_CLASS := FAKE cannot use LOCAL_OVERRIDES_MODULES` | Overrides on a phony module | A small real file module: `templates/remove-apps/` |
| `missing 'endif'` in the vendor `Android.mk` | `setup-makefiles.sh` lacks `write_footers` | Sequence: `setup_vendor` (COMMON=false), `write_headers`, `write_makefiles`, `write_footers` |

## Board config

| Error | Cause | Fix |
|---|---|---|
| `BOARD_PREBUILT_DTBIMAGE_DIR with 'BOARD_INCLUDE_DTB_IN_BOOTIMG != true' is not supported` | Required setting | `BOARD_INCLUDE_DTB_IN_BOOTIMG := true`. With `vendor_boot`, the DTB still goes there |
| `mkbootfs: cannot open directory '.../vendor_ramdisk'`, `fileslist panic` | Nothing staged into the vendor ramdisk | `BOARD_VENDOR_RAMDISK_KERNEL_MODULES` and `_LOAD`, from `modules.load.first_stage` |
| `check_partition_sizes: sum of sizes ... >= BOARD_SUPER_PARTITION_SIZE / 2` | Classic A/B limit applied, but `super` is sized for Virtual A/B | Inherit `$(SRC_TARGET_DIR)/product/virtual_ab_ota/launch.mk`, or `compression.mk` if stock uses compression |
| `Failed to find dtbo.img` (`CheckAbOtaImages`) | `dtbo` is in `AB_OTA_PARTITIONS`, but none is built | Stock's dtbo with its AVB footer removed (`avbtool erase_footer`), `BOARD_PREBUILT_DTBOIMAGE` |
| `Failed to find super.img` | `super` must not be in `AB_OTA_PARTITIONS` | List the logical partitions instead |
| `Failed to find vbmeta_system.img` | Chained vbmeta not declared | `BOARD_AVB_VBMETA_SYSTEM` and `_VENDOR` |
| `BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX is not defined` | Each chained vbmeta needs four values | `_KEY_PATH`, `_ALGORITHM`, `_ROLLBACK_INDEX`, `_ROLLBACK_INDEX_LOCATION` |
| `bacon`: `lineage-.zip`, then `ln: cannot create hard link` | Empty version: Lineage common config isn't inherited | Inherit `vendor/lineage/config/common_full_tv.mk` |
| `bacon`: same `ln -f` failure, correct version | OTA target empty, as there's no recovery fstab | `PRODUCT_BUILD_GENERIC_OTA_PACKAGE := true` |
| `dex_preopt_check.mk ... Missing compilation artifacts ... org.lineageos.platform` | Happens on 32-bit bring-up | `DISABLE_DEXPREOPT_CHECK := true`. The jar is compiled at first boot |

## Blob packaging

| Error | Cause | Fix |
|---|---|---|
| `module "x.xml" already defined` (many) | **If the earlier definition is in your `Android.bp`:** generated files stacked up, because `setup-makefiles.sh` lacked `write_headers`. **If it's in `external/`, `frameworks/` or `hardware/`:** AOSP has it | Regenerate; or drop that blob |
| `VINTF metadata found in PRODUCT_COPY_FILES` | VINTF can't be copied this way | `DEVICE_MANIFEST_FILE +=`, `vintf_fragments`, or `prebuilt_etc_xml` |
| `found ELF prebuilt in PRODUCT_COPY_FILES`, or `FAILED: .../check-non-elf-file-timestamps_intermediates/...` | The same check, reported either way | `BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true` |

## Install collisions: `overriding commands for target`

Two rules install the same file. "Previously defined at" tells you the other owner:

| Other owner | Examples | Fix |
|---|---|---|
| `out/soong/installs-*.mk` (Soong) | `vendor/bin/awk`, HAL services, `etc/selinux/*`, HIDL and AIDL `.so`, about 168 files | Intersect your copies with Soong's install targets |
| `base_rules.mk` (legacy Make) | `composer@2.2-service`, `gralloc.default.so`, `libril.so`, `libreference-ril.so`, `libdisplayconfig.so` | Scan `LOCAL_MODULE` names under `hardware`, `frameworks`, `system`, `external`, `device`, `vendor`, `packages`, `build`. **Check the module's board guards first**: it might not apply to your board |
| `build/make/core/Makefile` (generated) | `fs_config_dirs`, `fs_config_files`, `NOTICE.xml.gz`, `linker.config.pb` | Drop your copy. Stock's is wrong for your image anyway |
| `build/make/core/Makefile:702` | `vendor_dlkm/lib/modules/*.ko` | `BOARD_VENDOR_KERNEL_MODULES` owns that directory, so don't list `.ko` or `modules.*` as blobs |
| `copy-vintf-manifest-checked` | `vendor/etc/vintf/manifest/<hal>.xml` | Drop your fragment, or use a different filename |

**Never ship as blobs:** `build.prop`, `fs_config_*`, `NOTICE.xml.gz`, `linker.config.pb`, `etc/selinux/*`, `group`, `passwd`, top-level VINTF files, `.ko` when kernel modules are configured.

**The important catch:** dropping a blob means nothing installs that file any more, unless you add the AOSP module to `PRODUCT_PACKAGES`. **The build still succeeds, with no warning.** This silently left out the composer, audio and Wi-Fi HALs. Run `tools/50-gate.py --only vendor` after every round of collision fixes. Also check the module isn't another vendor's code with the same name: `--only collisions`.

**The same collision in the opposite direction:** a stock library you need can't be installed where an unrelated module owns the path, even when that module isn't installed: `overriding commands for target .../vendor.display.config@1.0.so`. Rename the stock file: `templates/shim/rename-display-config.sh`.

## VINTF

| Error | Cause | Fix |
|---|---|---|
| `assemble_vintf: Cannot override existing value 34.0 with BOARD_SEPOLICY_VERS` | Stock's manifest hard-codes a `<sepolicy>` version | Remove `<sepolicy>` from `manifest.xml` |
| `INCOMPATIBLE: instances are in the device manifest but not specified in framework compatibility matrix` | Vendor HALs in no framework matrix. "Not declared in FCM <= level" alone is only a warning | `DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE` listing them as `optional="true"` |

## Images

| Error | Cause | Fix |
|---|---|---|
| `FAILED: .../system.img`, with `Out of space? Out of inodes?` | **This message can be misleading.** Here the tree was 661 MB and the limit 743 MB, so space wasn't the problem. The real cause was new root folders (`/Reserve0` and others, from `BOARD_ROOT_EXTRA_FOLDERS`) with no SELinux labels | First compare the two sizes in the message. If there's room, add the folders to `sepolicy/vendor/file_contexts` and define their type in `file.te`. Read the lines before the message for the real tool error |
| `sepolicy/vendor` directory missing | Referenced by `BOARD_VENDOR_SEPOLICY_DIRS` | Create it with a `.keep` file, and keep comments off the value line |

## Prebuilts of stock binaries

| Error | Cause | Fix |
|---|---|---|
| `LOCAL_PREBUILT_JNI_LIBS` builds fine, but the app is missing on the device | The build rewrote the APK, breaking its signature | Not a build error: `LOCAL_REPLACE_PREBUILT_APK_INSTALLED`, in `tools/80-apps.py` |
| Build passes, but `CANNOT LINK` on device after making a module a prebuilt | A prebuilt doesn't pull in dependencies | Add each to `PRODUCT_PACKAGES` by hand |

## Framework patches

| Error | Cause | Fix |
|---|---|---|
| `error: method does not override or implement a method from a supertype` | A new method was inserted between an `@Override` and the method it belonged to | Put new methods above the `@Override` line |

## Your changes didn't reach the images

**The build can succeed and still contain the old settings.** Check each change in `out/` before flashing: `strings vendor_boot.img | grep <cmdline word>`, `grep` the installed `.rc` and `build.prop`, `unzip -p <zip> <file>`, `dexdump -d` a jar for a changed method, `aapt2 dump resources` for an overlay.

| Symptom | Cause | Fix |
|---|---|---|
| Edits in your git repo have no effect | The build tree has its own copy of the device tree | Sync it: `rsync -a --delete REPO/ TREE/device/<vendor>/<codename>/`, then `diff -rq` |
| Synced, still no effect; new files in the same sync did work | **`rsync -a` kept the old timestamps**, older than `out/build-<product>.ninja`, so make didn't re-read them | `touch` each changed file after syncing |
| Command line or vendor property change missing | `vendor_boot.img` and `vendor/build.prop` weren't rebuilt | Delete them and `obj/PACKAGING/vendor_boot_intermediates`, then build |
| Boot animation unchanged | The generated zip is cached | Delete `obj/BOOTANIMATION` and `product/media/bootanimation.zip` |
| Old images flashed after a failed build | A script ignored the build's exit code. Nothing broke only because they were the previous working build | Stop on a non-zero exit, and check the images as above |

## Host tools

| Error | Fix |
|---|---|
| `libusb.h`, `libfdt.h: No such file` building `sunxi-tools` | `sudo apt install libusb-1.0-0-dev libfdt-dev` |
| `sudo` needed for `adb` or serial | Add udev rules, and the user to `dialout`. Ask the user |

## Not errors: warnings you can ignore

| Message | Note |
|---|---|
| `kernel.mk: Using prebuilt kernel binary instead of source ... THIS IS DEPRECATED` | Expected when reusing stock's kernel |
| `Invalid sparse file format at header magic` while building `super` | Appeared on every successful build here |
| `Warning: The rule -checkdiscard ... matches a class not in the program` | From R8 |
| `lpmake: Partition x will resize from 0 bytes` | Normal |

## Quick order to fix things

When several errors appear, this order usually works best: (1) invocation (`lunch`), (2) `.mk` syntax and `DEVICE_PATH`, (3) board config, (4) duplicate modules, (5) install collisions, in batches, (6) VINTF, (7) image packaging, (8) OTA packaging, only if you need `bacon`.

You don't need `bacon` to flash. `m vendorbootimage bootimage initbootimage vbmetaimage superimage` produces flashable images, and it avoids the OTA errors above.
