# LineageOS build — commands (Allwinner H723 "hermes" projector)

Generic, reusable layout on this NVMe. The `lineage-21.0/` checkout is **device-agnostic** — add
other devices by dropping their `device/vendor/kernel` trees beside `allwinner/hermes` and
`lunch`-ing them; no re-sync needed. (For a different LineageOS version later, make a sibling
`lineage-22.0/` and repeat.)

```
/path/to/lineageos-build/
├── lineage-21.0/     <- generic LineageOS 21 source (repo sync target; shared base)
│   ├── device/allwinner/hermes/           (already placed)
│   ├── vendor/allwinner/hermes/           (already placed: blobs + proprietary-files.txt)
│   └── kernel/allwinner/hermes-reference/ (already placed: source-build reference only)
├── ccache/           <- shared compiler cache
└── BUILD-COMMANDS.md <- this file
```

> `repo` is at `~/.local/bin/repo` — make sure that's on PATH:  `export PATH="$HOME/.local/bin:$PATH"`

## 0. One-time tools (git-lfs is NOT yet installed)
```
sudo apt-get install -y git-lfs
git-lfs install --skip-repo
# full build deps (if not already):
sudo apt-get install -y bc bison build-essential ccache flex g++-multilib gcc-multilib \
    git gnupg gperf lib32ncurses5-dev lib32z1-dev libssl-dev libxml2-utils lzop \
    python3 python-is-python3 rsync unzip zip zlib1g-dev
```

## 1. Initialise the generic LineageOS 21 base
```
export PATH="$HOME/.local/bin:$PATH"
cd /path/to/lineage-21.0
repo init -u https://github.com/LineageOS/android.git -b lineage-21.0 --git-lfs
```

## 2. (optional) local_manifest
The Android TV base (`device/google/atv`) ships with LineageOS tv targets, so usually nothing
extra is needed. A staged template is in `.local_manifests_staging/hermes.xml`. If a later build
error says `device/google/atv` is missing, copy it in:
```
mkdir -p .repo/local_manifests
cp .local_manifests_staging/hermes.xml .repo/local_manifests/
```

## 3. Sync (the big download — hours, ~150 GB)
```
cd /path/to/lineage-21.0
repo sync -c -j"$(nproc)" --no-clone-bundle --no-tags --optimized-fetch --prune
```
`-c` = current branch only, keeps it smaller. Re-run the same command to resume if interrupted.
(Our `device/`, `vendor/`, `kernel/` trees are untracked by the manifest, so sync leaves them alone.)

## 4. Generate the vendor makefiles from the staged blobs (no device needed)
The blobs are **already staged** in `vendor/allwinner/hermes/proprietary/`, so use
`setup-makefiles.sh` — it reads them in place and writes the makefiles:
```
cd /path/to/lineage-21.0/device/allwinner/hermes
./setup-makefiles.sh
```
Writes `Android.bp` + `hermes-vendor.mk` (and `Android.mk`/`BoardConfigVendor.mk` only if needed)
into `vendor/allwinner/hermes/`.

> **Do NOT run `extract-files.sh` here.** That script calls extract-utils' `extract()`, which
> *pulls* blobs out of a raw device/dump and hardcodes a `/system/` lookup prefix
> (`$SRC/system/vendor/...`). Our `proprietary/` is already the finished vendor tree
> (`proprietary/vendor/...`, no `/system/` root), so every lookup misses and you get
> `!! <blob>: file not found in source` for all ~819 entries. `extract-files.sh` is only for
> re-pulling from a fresh dump or a live device (`./extract-files.sh adb`). With blobs staged,
> `setup-makefiles.sh` is the correct, offline step.

## 5. Build
```
cd /path/to/lineage-21.0
export USE_CCACHE=1
export CCACHE_DIR=/path/to/lineageos-build/ccache
ccache -M 50G
source build/envsetup.sh
breakfast hermes                        # lineage-21 lunch: resolves to lineage_hermes-ap2a-userdebug
                                        #   (explicit: lunch lineage_hermes-ap2a-userdebug)
                                        #   NOT the old 2-part `lunch lineage_hermes-userdebug`
mka bacon                               # full OTA zip; or: brunch hermes = breakfast + mka bacon
```
Output: `out/target/product/hermes/` (`boot.img`, `vendor.img`/`super.img`, `lineage-*.zip`).

## 6. Flash  (see this project's docs/07)
Use the fastboot package as a model, flashing the freshly built images instead of stock:
```
adb reboot fastboot                     # USB cable required (fastboot is USB-only)
fastboot flash boot        out/target/product/hermes/boot.img
fastboot flash dtbo        out/target/product/hermes/dtbo.img
fastboot flash vendor_boot out/target/product/hermes/vendor_boot.img
fastboot flash super       out/target/product/hermes/super.img     # or per-logical in fastbootd
fastboot reboot
```
Keep the stock backup (`firmware/backup/`) to revert.

## Troubleshooting (fixes already applied to this tree)
These bit us during bring-up and are now fixed in `device/allwinner/hermes/`. Listed so you know
what to expect and how to fix the same class of issue on the next device.

1. **`Invalid lunch combo: lineage_hermes-userdebug`** — Android 14 lunch is 3-part
   `<product>-<release>-<variant>`. Use `breakfast hermes` (resolves to
   `lineage_hermes-ap2a-userdebug`; release `ap2a` from `vendor/lineage/vars/aosp_target_release`).

2. **`<blob>: file not found in source` (×819) from `extract-files.sh`** — wrong script for
   pre-staged blobs. `extract-files.sh` *pulls from a dump* and prefixes `/system/`. Our blobs are
   already the finished tree under `proprietary/vendor/...`. Use **`setup-makefiles.sh`** instead.

3. **`BOARD_PREBUILT_DTBIMAGE_DIR with 'BOARD_INCLUDE_DTB_IN_BOOTIMG != true' is not supported`** —
   set `BOARD_INCLUDE_DTB_IN_BOOTIMG := true`. Device builds vendor_boot, so the DTB is routed into
   **vendor_boot**, not boot (matches stock). The "Device hermes not found / no product spec"
   messages after it are just fallout from the failed dumpvars; they vanish once board config parses.

4. **Make whitespace trap** — never put an inline `# comment` after a string/bool/path/size
   assignment: `VAR := true   # x` sets `VAR` to `"true   "` (trailing spaces kept), which fails
   `ifeq/ifneq ($(VAR),true)` compares and corrupts paths/sizes. Comment on its own line. Fixed for
   `BOARD_INCLUDE_DTB_IN_BOOTIMG`, `TARGET_BOARD_PLATFORM`, `TARGET_CPU_VARIANT`,
   `TARGET_PREBUILT_KERNEL`, `BOARD_AW_DYNAMIC_SIZE`, `PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS`.

5. **`This device does not have Treble enabled. This is unsafe.`** (config.mk warning) — the build
   only sets `PRODUCT_FULL_TREBLE := true` when `PRODUCT_SHIPPING_API_LEVEL` is set (>=26). Added
   `PRODUCT_SHIPPING_API_LEVEL := 34` (device shipped on Android 14) to `device.mk`.

6. **`Trying dependencies-only mode on a non-existing device tree?`** (roomservice) — **benign, no
   fix needed.** roomservice only auto-downloads device trees registered as repo `<project>`s; ours
   is copied in locally, so it finds nothing to fetch and exits. The tree is self-contained
   (prebuilt kernel, local blobs). lunch proceeds normally.

7. **`soong.lineage_hermes.variables did not parse correctly: invalid character ...`** (soong
   bootstrap fails) — a BoardConfig/product string var was assigned a value wrapped in literal
   double-quotes. Soong adds its own quotes, so `"lz4hc,9"` became `""lz4hc,9""` (invalid JSON).
   Fix: assign string board vars **unquoted** (`BOARD_EROFS_COMPRESSOR := lz4hc,9`). Find the
   culprit with:
   `python3 -c 'import json;json.load(open("out/soong/soong.lineage_hermes.variables"))'`
   (prints the exact line). Re-running `mka bacon` regenerates the file.

8. **`module "...xml" already defined`** (soong bootstrap, many lines) — two causes, both fixed:
   - **Internal triplication**: `setup-makefiles.sh` was missing `write_headers` (and ran
     `COMMON=1`). `write_headers` truncates the generated files; `write_makefiles` only *appends*,
     so each run stacked another copy. Fixed: script now runs the full extract-utils sequence —
     `setup_vendor (COMMON=false)` → `write_headers` → `write_makefiles` → `write_footers`. (Missing
     `write_headers` = the dup; missing `write_footers` = `Android.mk`'s `ifeq` guard left unclosed →
     kati `missing 'endif'`.) Regeneration is now idempotent; re-run `./setup-makefiles.sh`.
   - **AOSP collisions**: 4 VINTF manifest fragments are also defined by platform modules. Dropped
     from `proprietary-files.txt` (AOSP provides them): `android.hardware.cas-service.xml`,
     `android.hardware.drm-service.clearkey.xml`, `android.hardware.wifi.hostapd.xml`,
     `android.hardware.wifi.supplicant.xml`. Allwinner-specific fragments are kept.
   - **Triage**: the "previous definition here" path tells you which — points back into our own
     `Android.bp` = internal dup (regenerate); points to external/frameworks/hardware = AOSP
     collision (drop that blob from `proprietary-files.txt`).

9. **`VINTF metadata found in PRODUCT_COPY_FILES ... use DEVICE_MANIFEST_FILE / DEVICE_MATRIX_FILE
   / vintf_fragments instead`** (ckati, ~99% parsing) — top-level VINTF files can't be plain-copied.
   Dropped `vendor/etc/vintf/manifest.xml` + `compatibility_matrix.xml` from `proprietary-files.txt`.
   Manifest is provided via `DEVICE_MANIFEST_FILE` (our scaffold manifest == stock vendor manifest;
   other HALs via the 18 `prebuilt_etc_xml` fragments). Matrix staged as device-tree
   `compatibility_matrix.xml` with `DEVICE_MATRIX_FILE` commented (enable later if needed). The
   per-HAL fragments under `vintf/manifest/*.xml` are fine (emitted as `prebuilt_etc_xml`).

10. **`dex_preopt_check.mk: error ... Missing compilation artifacts ... org.lineageos.platform`** —
    system-server dexpreopt artifact check. On this 32-bit bring-up the jar's `oat/arm` artifacts
    aren't produced. Set `DISABLE_DEXPREOPT_CHECK := true` in `device.mk` (the check's documented
    disable input); the jar is dexopted at first boot instead. Revisit for production.

11. **`overriding commands for target .../vendor/etc/vintf/manifest/<hal>.xml`** (ckati, "writing
    legacy Make module rules") — **install-path** collision (vs the module-name kind in #8): AOSP
    installs some VINTF fragments via `copy-vintf-manifest-checked` (when it builds the default HAL
    service) to the same path our `prebuilt_etc_xml` uses. These aren't duplicate Soong *names*, so
    #8's scan misses them. Find them by intersecting our Android.bp fragment names with AOSP's
    copy-vintf-manifest-checked destinations in `out/soong/installs-lineage_hermes.mk`. Dropped our 4
    (all standard AOSP HALs): `android.hardware.boot@1.2.xml`,
    `android.hardware.health-service.example.xml`, `android.hardware.wifi-service.xml`,
    `bluetooth_audio.xml`. AIC8800 driver/fw blobs still load under AOSP's wifi HAL; proprietary
    fragments kept.

12. **`overriding commands for target .../vendor/bin/awk` (+ ~168 like it)** — systemic
    over-capture: the `/vendor` dump included many **standard AOSP components**, so our
    `PRODUCT_COPY_FILES` collide with the platform's own Soong installs. Affected: standard bins,
    AOSP default HAL services + `.rc`, all `vendor/etc/selinux/*` (must be platform-built), and every
    VNDK/HIDL/AIDL `.so`. Dropped all 168 at once by intersecting our copy destinations with Soong's
    install targets in `out/soong/installs-lineage_hermes.mk`, then commenting the matches in
    `proprietary-files.txt` (827 → 636 active). Proprietary drivers (`*.hermes.so`, `vendor.sunxi.*`,
    `*-aw`, AIC8800 fw, 81 `.ko`) retained; 0 collisions remain. Re-run the intersection after any
    `proprietary-files.txt` change.

13. **`overriding commands ... composer@2.2-service, previously defined at base_rules.mk:497`** —
    same over-capture as #12 but a **legacy Make module** (base_rules.mk = Make, not Soong), so the
    Soong-only #12 scan missed it. `module-info.json` can't help (kati aborts before emitting it).
    Enumerated `LOCAL_MODULE` names from legacy `Android.mk` in the real HAL dirs and intersected
    with our shipped bins/libs → only `android.hardware.graphics.composer@2.2-service` matched.
    Dropped it + its `.rc`; kept `hwcomposer.hermes.so` (AOSP's composer service loads it). Both
    collision classes now exhausted: 827 → 634 active blobs.

14. **`overriding commands ... vendor/etc/fs_config_dirs`** (+ `fs_config_files`, `NOTICE.xml.gz`,
    `linker.config.pb`) — third over-capture class: **build-generated partition metadata**, emitted
    by `build/make/core/Makefile` (not Soong, not Android.mk), so #12/#13 scans miss them. A stock
    copy both collides and is wrong (describes stock layout). Dropped those 4 (`build.prop`,
    `group`, `passwd`, `selinux/*`, `*_dlkm` variants already gone under #12). Rule: never ship
    `build.prop`, `fs_config_*`, `NOTICE.xml.gz`, `linker.config.pb`, `etc/selinux/*`,
    `group`/`passwd`, or VINTF files as blobs.
15. **`overriding commands ... vendor/lib/hw/gralloc.default.so`** (`base_rules.mk`) — same legacy
    Make-module class as #13, but a **fallback HAL**: AOSP's generic gralloc from
    `hardware/libhardware`. We ship the real `gralloc.hermes.so`, so the fallback is both a collision
    and dead weight. Dropped `vendor/lib/hw/gralloc.default.so`. Rule: any `*.default.so` fallback
    HAL (or any blob whose basename matches a LOCAL_MODULE the platform builds) collides via
    `base_rules.mk` — drop it, keep the vendor-specific `*.hermes.so`.
16. **`overriding commands .../vendor/lib/libreference-ril.so`** (then `libril.so`, `libdisplayconfig.so`) —
    more `base_rules.mk` collisions with **generic-named AOSP libs** the platform builds. kati reports
    only the first dup then aborts, so these trickle one per build. Batch them with a tree scan: intersect
    every legacy `LOCAL_MODULE` name (walk `.mk` under hardware/frameworks/system/external/device/
    vendor/lineage/packages/build) with our active blob basenames (full script in the drive runbook
    `BUILD-COMMANDS.md` item 16). For each hit, **check the module's board guards before dropping** —
    drop ours only if the module is defined for *our* build; keep ours if it's gated off for our board
    (genuine blob sharing a generic name):
    - DROP: `libreference-ril.so`, `libril.so` (built unless `BOARD_PROVIDES_LIBRIL`), `libdisplayconfig.so`
      (unconditional, `hardware/qcom/sdm845/...`).
    - KEEP: `libbt-vendor.so` (gated `BOARD_HAVE_BLUETOOTH_QCOM`, unset); `hostapd`, `wpa_supplicant`,
      `libwpa_client.so` (gated `BOARD_HOSTAPD_DRIVER`/`BOARD_WPA_SUPPLICANT_DRIVER`, unset — AIC8800 wifi).
17. **`overriding commands .../vendor_dlkm/lib/modules/*.ko`** — both rules in
    `build/make/core/Makefile` (`:702` vs `:161`): a **mechanism conflict**. BoardConfig's
    `BOARD_VENDOR_KERNEL_MODULES := $(wildcard $(DEVICE_PATH)/prebuilt/modules/*.ko)` makes the build
    assemble `vendor_dlkm` and install every `.ko` to `vendor_dlkm/lib/modules/` (+ `depmod`-generated
    `modules.dep/.alias/.softdep`). `proprietary-files.txt` *also* copied the same 77 `.ko` + 4
    `modules.*` there — second owner, and the stock metadata is wrong. Removed all 81; the `.ko` source
    of truth is `device/allwinner/hermes/prebuilt/modules/`. Rule: never list `.ko`/`modules.*` as blobs
    when `BOARD_VENDOR_KERNEL_MODULES` (or `BOARD_SYSTEM_KERNEL_MODULES`) is set — it owns `*_dlkm/lib/modules/`.
18. **`ninja: '/manifest.xml' ... missing and no known rule`** — leading `/` = `$(DEVICE_PATH)` empty.
    `device.mk` (product config) is parsed **before** `BoardConfig.mk` where `DEVICE_PATH` is set, so
    `DEVICE_MANIFEST_FILE := $(DEVICE_PATH)/manifest.xml` (and the `$(DEVICE_PATH)/rootdir/...fstab` copy)
    became `/...`. Fix: set `DEVICE_PATH := device/allwinner/hermes` (literal) at the **top of device.mk**
    before any use. **`$(call my-dir)` does NOT work here** — inside inherit-product's include
    MAKEFILE_LIST ends with the import machinery, not device.mk, so it returns empty and the error
    persists. Use the literal (same value BoardConfig.mk uses). Also removed
    `PRODUCT_PACKAGES += fstab.sun50iw15p1` — no
    module by that name exists (unresolved PRODUCT_PACKAGES fails staging); the fstab is a plain file
    copied via PRODUCT_COPY_FILES to `vendor/etc/fstab.sun50iw15p1`.
19. **`assemble_vintf: Cannot override existing value 34.0 with BOARD_SEPOLICY_VERS (which is 202404)`** —
    `manifest.xml` (copied from stock) hard-coded `<sepolicy><version>34.0</version></sepolicy>`.
    assemble_vintf injects the build's `BOARD_SEPOLICY_VERS` (LOS 21 = `202404`) and errors if the file
    declares a different value. `34.0` is stale stock vendor sepolicy (dropped under #12). Fix: **remove
    the `<sepolicy>` element** from `manifest.xml` so the build fills it from `BOARD_SEPOLICY_VERS`.
    Rule: don't hard-code `<sepolicy>` in a device manifest built from platform sepolicy.
20. **`check-elf-files: found ELF prebuilt in PRODUCT_COPY_FILES`** (busybox, crda, vendor/bin/hw/*, many
    `.so`) — Android wants ELF blobs as Soong `cc_prebuilt_binary`/`cc_prebuilt_library_shared`, not
    PRODUCT_COPY_FILES (`build/make/core/Makefile:152`). We ship the vendor partition **wholesale** via
    PRODUCT_COPY_FILES, so every ELF trips it. Fix: `BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true`
    in BoardConfig.mk (empties the check, `Makefile:148`) — the standard choice for a copy-the-vendor-image
    tree; converting hundreds of blobs to cc_prebuilt modules is huge and trips Soong symbol/NEEDED checks
    that over-captured stock blobs fail. Also moved the `BOARD_VENDOR_SEPOLICY_DIRS` inline comment off the
    value line and created an empty `device/allwinner/hermes/sepolicy/vendor/.keep` so that missing dir
    resolves.
21. **`mkbootfs: cannot open directory '.../vendor_ramdisk'`** / **`fileslist panic: lstat .../vendor_ramdisk`** —
    building `vendor_boot` (hdr v4) but nothing was staged into the vendor ramdisk, so the dir was never
    created. The vendor ramdisk must hold the **first-stage kernel modules**. Fix in BoardConfig.mk, from
    `modules.load.first_stage` (12 early display/panel/backlight + bootevent):
    `BOARD_VENDOR_RAMDISK_KERNEL_MODULES := $(addprefix $(DEVICE_PATH)/prebuilt/modules/,$(shell cat $(DEVICE_PATH)/modules.load.first_stage))`
    and `BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD := $(strip $(shell cat $(DEVICE_PATH)/modules.load.first_stage))`.
    Same prebuilt `.ko` set; also present in vendor_dlkm (second stage) — different partitions, no collision.
22. **VINTF `INCOMPATIBLE`: "instances are in the device manifest but not specified in framework
    compatibility matrix"** — the "not declared in FCM <= level 7" list is a non-fatal warning (platform
    HALs at FCM 8+). The fatal part is **vendor-proprietary** HALs in no framework matrix — here 4 from our
    kept vintf fragments: `vendor.aw.homlet.tvsystem.tvserver` (hidl 1.0 ITvServer), `vendor.display.config`
    (hidl 1.0 IDisplayConfig), `vendor.sunxi.tv.graphics` (hidl 1.0 IDisplay), `vendor.hardware.drmheapallocator`
    (aidl v1 IDrmHeapAllocator). Fix: add a **device framework compat matrix** (`type="framework"`) listing
    them `optional="true"`, wired via `DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE := $(DEVICE_PATH)/framework_compatibility_matrix.xml`
    in device.mk. Copy format/version/interface/instance verbatim from each `proprietary/vendor/etc/vintf/manifest/*.xml`.
23. **`bacon` → `out/.../lineage-.zip` then `ln: cannot create hard link ... No such file or directory`** —
    empty version string. `lineage_hermes.mk` had the LineageOS common inherit commented out:
    `# $(call inherit-product, vendor/lineage/config/common_full_tv.mk)`. That brings in
    `vendor/lineage/config/{common,version}.mk` which set `LINEAGE_VERSION`/`LINEAGE_BUILD`. Fix:
    **uncomment** it. Note: reaching bacon means all partition images already built in
    `out/target/product/hermes/*.img` — for an Allwinner first-flash you flash those raw images
    (fastboot / PhoenixSuit), the LOS OTA zip is optional.
24. **`bacon` zip name correct but SAME `ln -f` empty-source failure** — after #23 the version is right,
    but `INTERNAL_OTA_PACKAGE_TARGET` is empty (`bacon.mk:24` links from it). The build opts out of OTA
    packaging when `recovery_fstab` is empty (`build/make/core/Makefile:5523`) — our case (no recovery
    partition). Fix: `PRODUCT_BUILD_GENERIC_OTA_PACKAGE := true` in device.mk skips the opt-out block
    (`Makefile:5514`) and forces OTA generation. Fine here — the OTA is an A/B `update_engine` payload,
    no recovery fstab needed to build it.
25. **`check_partition_sizes: sum of sizes of ['aw_dynamic'] >= BOARD_SUPER_PARTITION_SIZE / 2`** — the
    build applied the **super/2** limit (classic A/B, both slots in super). `check_partition_sizes.py`
    `DeviceType.Get`: `ab_update=true` + no `virtual_ab` ⇒ AB ⇒ `num_slots=2`. But the device is
    **Virtual A/B** (stock `ro.virtual_ab.enabled=true`) — super holds one slot, group ≈ full super (how
    we sized it). We'd sized super the VAB way but never enabled VAB. Fix: inherit
    `$(SRC_TARGET_DIR)/product/virtual_ab_ota/launch.mk` in device.mk ⇒ `virtual_ab=true` ⇒ VAB ⇒
    `num_slots=1` ⇒ limit = full super (2.68 GB group passes under 2.684 GB). Use **launch.mk**
    (non-compressed) — stock has no `ro.virtual_ab.compression.enabled`. Rule: a VAB-sized super group
    requires VAB actually enabled.
26. **`CheckAbOtaImages: AssertionError: Failed to find dtbo.img`** — `dtbo` is in `AB_OTA_PARTITIONS`,
    so the OTA check requires `dtbo.img`, but none was built (no `BOARD_PREBUILT_DTBOIMAGE`). Fix: ship the
    stock dtbo. The stock `dtbo_a` has an AVB footer (`avbtool info_image`: original image size 4096) which
    `BOARD_PREBUILT_DTBOIMAGE` must not have — strip it with `avbtool erase_footer`, stage at
    `device/allwinner/hermes/prebuilt/dtbo.img`, set `BOARD_PREBUILT_DTBOIMAGE := $(DEVICE_PATH)/prebuilt/dtbo.img`.
    (Stock dtbo was unsigned, `Algorithm: NONE`.) The build re-adds AVB with our key.
27. **`CheckAbOtaImages: Failed to find super.img`** — `super` must NOT be in `AB_OTA_PARTITIONS`. With
    dynamic partitions the OTA updates the LOGICAL partitions inside super (system/system_ext/product/
    vendor/vendor_dlkm/system_dlkm) via snapshots; `super` itself is never an OTA partition (only
    `super_empty.img` exists). Fix: replace `super` with `$(BOARD_AW_DYNAMIC_PARTITION_LIST)` in the
    `AB_OTA_PARTITIONS` line.
28. **`CheckAbOtaImages: Failed to find vbmeta_system.img`** (and vbmeta_vendor.img) — those chained
    vbmeta are in `AB_OTA_PARTITIONS` but only `BOARD_AVB_ENABLE := true` was set, so only the top-level
    `vbmeta.img` built. Stock chains `vbmeta_system` (RIL 1, hashtrees system) and `vbmeta_vendor`
    (RIL 2, hashtrees vendor) off the main vbmeta (confirmed via `avbtool info_image`). Fix: declare the
    chained groups in BoardConfig (`BOARD_AVB_VBMETA_SYSTEM := system system_ext product` +
    `_KEY_PATH`/`_ALGORITHM`/`_ROLLBACK_INDEX_LOCATION := 1`, and `BOARD_AVB_VBMETA_VENDOR := vendor
    vendor_dlkm` + RIL 2). Chained vbmeta REQUIRE a key (test key `external/avb/test/data/testkey_rsa2048.pem`
    for the unlocked UNOFFICIAL build). `--flags 2` disables dm-verity so the grouping isn't boot-critical.
    NOTE: each chained vbmeta needs ALL FOUR of KEY_PATH/ALGORITHM/**ROLLBACK_INDEX**/ROLLBACK_INDEX_LOCATION.
    `_ROLLBACK_INDEX` (the index value, use 0) is separate from `_ROLLBACK_INDEX_LOCATION` (slot 1/2);
    omitting it gives `Makefile:4803: BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX is not defined`.

## Known, not-yet-handled

## Known, not-yet-handled (likely later hurdles — NOT needed for a first fastboot image)
- **Virtual A/B**: now ENABLED (non-compressed, `virtual_ab_ota/launch.mk`), matching stock
  `ro.virtual_ab.enabled=true`; `super` is single-slot VAB (group ≈ full super — do NOT halve). Open:
  (a) stock also reports `ro.boot.dynamic_partitions_retrofit=true`; we build a plain (non-retrofit)
  VAB super — fine to fastboot-flash/boot, revisit only if exact retrofit modelling matters for OTA;
  (b) VAB **compression** (VABC) is off — switch launch.mk → compression.mk for smaller OTAs later.
- **SELinux enforcing**: BoardConfig drops stock's `androidboot.selinux=permissive`. If early boot
  loops on denials, temporarily re-add it to confirm it's policy, then write sepolicy instead of
  shipping permissive.

## Notes
- **Prebuilt kernel**: the build reuses the device's own kernel + 81 modules (BoardConfig
  `TARGET_PREBUILT_KERNEL`). No kernel source needed. See `device/allwinner/hermes/README.md`.
- **Adding another device later**: `cd lineage-21.0`, add `device/<vendor>/<codename>`,
  `vendor/...`, `kernel/...`, then `breakfast <codename> && mka bacon`. The synced base is shared.
```
