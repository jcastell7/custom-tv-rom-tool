# Building the ROM

A working example of everything here is in `reference/hermes/device-tree/`. Copy from it and change what differs. Its full history and reasoning are in `reference/hermes/docs/12-rom-boot-fixes.md`.

## Set up

See [`10-SETUP-NEW-COMPUTER.md`](10-SETUP-NEW-COMPUTER.md). Run `tools/00-check-host.sh --tree PATH`, then `tools/05-sync-lineage.sh PATH`, which takes hours. A tree with one built device measured 232 GB. **If this computer already has a tree, reuse it**: one tree serves many devices.

Build with `tools/40-build.sh`. **Always go through `lunch`.** A hand-rolled `soong_ui` call produces a different product configuration and false errors.

Run builds in the background and wait for them. Incremental builds take 1–3 minutes here, full ones take hours. A wrapper that writes `rc=N` to a log makes it easy to tell when a build ended.

## Kernel

The examples below use the stock kernel as a prebuilt (`TARGET_PREBUILT_KERNEL`), with stock modules. **Prefer a LineageOS or other open kernel if one fits.** See [`12-KERNEL-AND-CLOSED-SOURCE.md`](12-KERNEL-AND-CLOSED-SOURCE.md), which also covers what stays closed source.

## The files you need

```
device/<vendor>/<codename>/
  AndroidProducts.mk, lineage_<codename>.mk   product definition
  device.mk                                   packages, copies, properties
  BoardConfig.mk                              partitions, kernel, boot image settings
  manifest.xml, framework_compatibility_matrix.xml   VINTF
  rootdir/etc/fstab.<hardware>                from stock
  prebuilt/                                   stock kernel, DTB, DTBO
  recovery/root/                              stock's recovery modules and init file
  sepolicy/
vendor/<vendor>/<codename>/proprietary/       stock files
```

For a TV product, inherit in this order: your `device.mk`, then `device/google/atv/products/atv_base.mk`, then `vendor/lineage/config/common_full_tv.mk`.

## Getting stock's boot settings right

Read the settings from your backup, and match them exactly. `tools/bin/unpack_bootimg.py` prints them, and `50-gate.py` compares them.

```make
# Header versions: read from stock's images.
BOARD_BOOT_HEADER_VERSION := 4
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
# init_boot is a separate mkbootimg call and DEFAULTS TO VERSION 0 without this:
BOARD_MKBOOTIMG_INIT_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
# vendor_boot's name, if stock's isn't empty:
BOARD_MKBOOTIMG_ARGS += --board arm

# The vendor cmdline comes from BOARD_KERNEL_CMDLINE. BOARD_VENDOR_CMDLINE does nothing.
BOARD_KERNEL_CMDLINE := <stock vendor cmdline, exactly>
BOARD_BOOTCONFIG += <stock bootconfig lines, exactly>
BOARD_BOOTCONFIG += androidboot.init_fatal_reboot_target=recovery

# Recovery with fastbootd, in vendor_boot:
BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/etc/fstab.<hardware>

# Mount points that first-stage init needs:
BOARD_USES_METADATA_PARTITION := true
BOARD_ROOT_EXTRA_FOLDERS := <any others the fstab mounts>

# Stock's patch levels. Stock keymint can abort if these are empty.
VENDOR_SECURITY_PATCH := <stock value>
BOOT_SECURITY_PATCH := <stock value>
```

**AVB:** `BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 2` disables verification, so patched images still boot. Check how your bootloader treats this: ours showed an orange warning.

## Treat the `/vendor` partition carefully

**The key concept: a stock vendor partition usually can't just be copied, and the build doesn't warn when something's missing.**

### Why blobs go missing

The generated blob list drops files when they'd collide with a module in the tree. The note says "built by AOSP", but nothing installs that AOSP module unless you add it to `PRODUCT_PACKAGES`. That left the first build with no composer, audio HAL, or Wi-Fi HAL, with no build error at all.

**After the first build, compare stock's vendor with your image.** `50-gate.py --only vendor` lists what's missing. Then, for each file:
- If `module-info.json` shows a module that installs that path, add that module to `PRODUCT_PACKAGES`.
- Otherwise, copy stock's with `PRODUCT_COPY_FILES`.
- VINTF XML can't go in `PRODUCT_COPY_FILES`, so use `DEVICE_MANIFEST_FILE +=`.

### No VNDK APEX

Stock may load many libraries from a VNDK APEX (`ro.vndk.version`) that your build doesn't include. Then:
- stock blobs fail with `library not found`;
- add each as a `.vendor` module (or a stock copy);
- **don't set `ro.vndk.version`** without the APEX, as it breaks the linker configuration.

`50-gate.py --only symbols` checks every vendor binary's libraries and symbols. Run it after each change.

### Same name, different library

**The worst bug of the project.** A tree can contain another vendor's HAL with the same name. Here `vendor.display.config@1.0` was both Allwinner's and Qualcomm's. The build picked Qualcomm's, everything linked, the service registered, and every keystone call failed at runtime with `HwBinder Error: (-74)`.

The build won't let you install a stock file on a path that a module owns, even if that module isn't installed. Rename the stock library. See `templates/shim/rename-display-config.sh`, and `50-gate.py --only collisions`.

### Prefer matched pairs

If a service and its vendor library came from stock together, keep them together. AOSP's newer Wi-Fi service and stock's Wi-Fi library crashed, because they disagreed on a function table. To use a stock binary where a module has the same name, change that module to a `cc_prebuilt_binary` or `cc_prebuilt_library_shared` in the tree. See `templates/patches/wifi-*.patch`.

### Missing symbols

A stock binary may need a symbol your newer library dropped, like `sk_dup`. Provide it with a small shim library and add the shim using `patchelf --add-needed`. See `templates/shim/`. This is standard LineageOS practice. **Record it in a script**, because re-extracting the blobs loses the change.

## Properties

Your `vendor/build.prop` is generated, not copied. Stock's properties are lost unless you add them. **Review them rather than copying them all.**

**Needed:** `ro.hardware.egl`, `ro.opengles.version`, `ro.sf.lcd_density`, `ro.surface_flinger.*`, security patches, Bluetooth profile settings, dalvik heap settings.

**Don't copy without thinking:**

| Property | Problem |
|---|---|
| `ro.vndk.version` | Breaks linking without the VNDK APEX |
| `ro.lmk.*` | Stock's old-strategy values killed foreground apps once GApps and swap were in the picture |
| `persist.bluetooth.bqr.*` | Sends a vendor command the controller may reject |
| `ro.incremental.enable` | Points at a module that may not ship |
| Anything with a fake fingerprint | Stock on the first device claimed to be a different device |

Also check runtime properties. Some stock values live outside `vendor/build.prop`: compare the live `getprop` output too.

## Common build errors

The most frequent are below. **The complete list, about 45 errors, is in [`08-BUILD-ERRORS.md`](08-BUILD-ERRORS.md).**

| Error | Cause | Fix |
|---|---|---|
| `includes non-existent modules in PRODUCT_PACKAGES` | Wrong name, often a `.vendor` suffix on something without that variant | Look in `module-info.json` |
| `VINTF metadata found in PRODUCT_COPY_FILES` | XML under `etc/vintf` copied directly | Use `DEVICE_MANIFEST_FILE +=` |
| `overriding commands for target` | Two rules install the same path | Rename your file, or turn the module into a prebuilt |
| `LOCAL_MODULE_CLASS := FAKE cannot use LOCAL_OVERRIDES_MODULES` | Overrides on a phony module | Use a real small file module: `templates/remove-apps/` |
| `lunch` returns non-zero with `fixup_common_out_dir` | Non-interactive shell | `tools/40-build.sh` handles it |
| `libfmjni` undefined, or other strange module errors | Built without `lunch` | Use `lunch` |
| Dexpreopt check fails for a jar | 32-bit bring-up | `DISABLE_DEXPREOPT_CHECK := true`, then revisit |
| `Group size ... exceeds` for dynamic partitions | Classic A/B sizing was applied | Inherit `virtual_ab_ota/launch.mk` if stock uses Virtual A/B |
| `ln -f <empty> ...` during bacon | No OTA package | `PRODUCT_BUILD_GENERIC_OTA_PACKAGE := true` |

For device-side errors, go to [`05-DEBUG-CATALOG.md`](05-DEBUG-CATALOG.md).

## Patches to the tree

Changes outside your device and vendor directories are lost on a re-sync, so save each with `git diff > patch` and record it. The ones used for the first device are in `templates/patches/`. They apply to LineageOS 21, and may need adjusting for other versions:

| Patch | For |
|---|---|
| `connectivity-bpf-32bit.patch` | 32-bit kernels with a JIT that lacks atomics and 64-bit div/mod |
| `bluetooth-shim-invalid-command-complete.patch` | Any controller that rejects vendor commands |
| `wifi-libwifi-hal-stock-prebuilt.patch`, `wifi-service-stock-prebuilt.patch` | Vendor Wi-Fi HALs that select the chip themselves |
| `inputflinger-right-button-back.patch` | Remotes with a trackpad, where right click should be Back |

The Wi-Fi patches also need the stock files copied next to the `Android.bp`. See their comments.
