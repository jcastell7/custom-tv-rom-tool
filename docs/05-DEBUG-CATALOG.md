# Debug catalog

> **⚠️ WARNING: this process could very well fully and permanently brick your device.** Only use it on a device you own and can afford to lose. It's provided as is, with no warranty, and **we accept no responsibility** for how it's used or what happens. Not affiliated with LineageOS in any way: we just use and recommend their work, so [please donate to them](https://lineageos.org/about/) when you can. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

Every entry happened on the first device, unless it's marked otherwise. `tools/75-triage.py` matches most of these log lines automatically.

**How to debug:**
1. Find the first error, not the last. Later errors are usually results of it.
2. Don't fix a symptom until you know its cause. Check a theory on the running device first when you can, as a live test costs seconds and a flash costs minutes.
3. Once you've found one instance of a problem, check for others of the same kind. Scanning every binary for missing symbols took minutes, and it answered the question for good.
4. When you fix something, add a check to `50-gate.py` or a line to `75-triage.py`.

## Getting logs

| Situation | How |
|---|---|
| `adb` works | `adb logcat -d`, `adb logcat -d -b crash`, `adb logcat -d -b events`, `adb shell dmesg` |
| No `adb`, UART wired | The serial log. Add `d` at the boot0 prompt on Allwinner to get more u-boot output |
| Boot looping | Save logcat quickly, as `70-watch-boot.sh` does. `recovery-persist` also keeps some |
| Nothing on UART after early boot | The console level is low: use logcat |

**PC notes:** the serial port may need `dialout` group access, so the user may have to run `picocom` themselves with a logfile you can read. In zsh, unmatched globs raise an error, and `grep` may be an alias, so use `command grep`.

## Looks scary, but is normal

**Compare with a stock boot log before you chase anything.** These appear on every boot of the first device, including ones that worked. They're from the UART logs the user supplied. Other devices will have their own list, which is another reason to capture stock's log early. **On the first device, I wasted time on some of these.**

| Log line | Why it's fine |
|---|---|
| `mmc 0 cmd timeout`, `smc 0 err, cmd 55, RTO`, `Card did not respond to voltage select`, `mmc_init: -95`, `card0 init failed` | u-boot probing the absent SD slot. The eMMC is `mmc 2`, and it works |
| `get sdc_type fail`, `can't find node "mmc0"` | Same |
| `ERROR: reserving fdt memory region failed (addr=76a00000 size=9600000)` | Printed just before `Starting kernel`, on good boots too |
| `secure storage read widevine fail`, `ec_key`, `hdcpkeyV22`, `erase secure storage failed` | Keys this unit doesn't have. It may affect DRM, not boot |
| `Load advert_file fail`, `get file(advert.crc) size from Reserve0 error` | Optional boot ad |
| `fail to get clk1`, `failed to request regulator(power0-supply): -22`, `of_pll_clk_config_setup error`, `[KSC_ERR]`, `ksc 5900000.ksc: Fail to get rst0` | Optional device-tree properties in display and keystone drivers. Keystone works with these |
| `FDT ERROR:fdt_get_regulator_name`, `fdt_get_all_pin ... FDT_ERR_INTERNAL`, `prop trace_level not found` | Optional properties |
| `** Bad device usb 0 **`, `** Unrecognized filesystem type **`, `skip update boot_param` | No USB stick present, during u-boot's update scan |
| `** Unable to read file **`, `Unknown command '0x40007000'` | **Only while using the rescue stick.** Our script's lines cause these on purpose |
| `EHCI fail timeout STS_ASS set` | USB host during the scan |
| `ANDROID: bootable slot 0 ... corrupt: 0, successful: 1` | Normal slot status. "corrupt: 0" is the good value |
| `exceed env_a scope` | A memory-overlap tracker in u-boot |
| `supply vcc-pl not found, using dummy regulator`, `cannot get the TX DMA channel`, `Get clk0_freq property failed`, `get gpio_names failed`, `failed with error -22` for `sunxi-direct-gpio` | Vendor kernel, optional hardware |
| `failed to load regulatory.db` | Wi-Fi regulatory database file; works without it |
| `Using internal RC 16M clock source` | RTC warning; time may drift |
| `Unknown kernel command line parameters "snum=... wifi_mac=..."` | The bootloader's own parameters. **That line holds the unit's serial number and MAC. Mask them before sharing it, and never copy them here** |
| `FAT-fs (mmcblk0p26): Volume was not properly unmounted` | A vendor FAT partition after a hard power-off |
| `audit: rate limit exceeded`, `has incorrect label or no domain transition`, `libprocessgroup: Failed to` | Permissive SELinux, and cleanup of exited processes |
| `Command 'restart vendor.audio-hal-aidl' ... failed: service not found`, also `-4-0-msd`, `audio_proxy_service`, `zygote_secondary` | AOSP's `.rc` names every possible variant, and this device has only some |
| `Could not create socket 'pdx/system/vr/display/...'` | VR display sockets, unused |
| `Command 'write /sys/power/state on' ... failed` | Harmless here. Appears when zygote restarts |
| `cutils-trace: Error opening trace file` | Early in boot, before tracefs is ready |
| `Tried to start aidl service ... as a lazy service, but was unable to`, 785 times here | Often means a service was restarting. See whether that HAL really runs |
| `get power supply failed`, from `sunxi_usb_udc` | Device has no battery or USB power reporting |
| `binder: transaction failed 29189/-3` | Target process died. **Look for why**, if it's frequent |
| `ir boot recovery not used`, `do_burn_from_boot usb : no usb exist` | Status messages |
| `Can't find service: activity` once | `system_server` is restarting or the device is shutting down. Check for `sys.powerctl` |

**The test:** does the line also appear in stock's log? If so, ignore it, unless you have a specific reason not to.

## Before the kernel

| Symptom | Cause | Fix |
|---|---|---|
| Stops at `ramdisk use init boot`, no `Starting kernel` | `init_boot` had header v0, so u-boot used a wrong field as the ramdisk size (448 MiB) and copied over its own memory | `BOARD_MKBOOTIMG_INIT_ARGS += --header_version 4` |
| Could fail at `Starting kernel` on 32-bit | Empty `vendor_boot` name. u-boot only sets "force run 32bit os" when the name is `arm` | `BOARD_MKBOOTIMG_ARGS += --board arm` |
| `prefetch abort` in u-boot | A command with a bad size overran RAM (`sunxi_flash read` with less than `0x8000`) | Use valid sizes. This one only overwrote RAM |
| Fastboot screen shows, PC sees nothing | u-boot fastboot USB isn't working on this board | Use fastbootd. Don't rely on bootloader fastboot until the PC has actually seen it |
| Device powers off during a large load from USB | Seen once, cause unknown, didn't recur | Retry once and record it |

## Kernel and first-stage init

| Symptom | Cause | Fix |
|---|---|---|
| `Failed to parse bootconfig: Value is redefined`, then reboot to bootloader | Build and bootloader both set a key. The kernel rejects ALL of bootconfig, and `force_normal_boot` and `slot_suffix` go with it | Match stock's cmdline and bootconfig exactly |
| Init can't find partitions | No fstab in a boot ramdisk | Install the fstab to `vendor_ramdisk/first_stage_ramdisk` with a Make prebuilt. Soong's `prebuilt_etc` puts it in the wrong place or collides |
| SwitchRoot fails | Mount point missing from the system root | `BOARD_USES_METADATA_PARTITION`, `BOARD_ROOT_EXTRA_FOLDERS`. New folders also need SELinux labels, or the build fails |

## Second-stage init and early services

| Symptom | Log | Cause | Fix |
|---|---|---|---|
| Reboots while loading BPF | `non-optional program failed`, errno 524 | 32-bit JIT with `BPF_JIT_ALWAYS_ON` can't run atomics or 64-bit div/mod | See the next line. Stock's `vendor/etc/bpf-override/netd.o` shows the same approach |
| `netd` aborts, zygote keeps restarting | `Failed to get program from /sys/fs/bpf/...` | **Skipping the programs at load only moved the failure.** `netd` needs them | Patch `bpf_progs`: plain add for `__sync_fetch_and_add`, multiply-and-shift for the division and the modulo. Scan `netd.o` for opcodes `3f 37 9f 97 db c3` |
| System reboots at zygote start | `Error getting bootctrl module`, from `update_verifier` | No boot control HAL | Add `android.hardware.boot@1.2-impl`, `-impl.recovery`, `-service` |
| No HAL can be found | `VINTF parse error: Conflicting FqInstance`, `NULL VINTF MANIFEST` | One duplicate invalidates the whole manifest. An APEX also declared `android.hardware.cas` | Remove the duplicate. Check APEX manifests too |
| HALs exit immediately | `CANNOT LINK EXECUTABLE ... not found` | Library missing; no VNDK APEX | `.vendor` module or stock copy |
| `wpa_supplicant` restarts every second | `cannot locate symbol "sk_dup"` | BoringSSL changed | Shim plus `patchelf --add-needed` |
| Service won't start in a watchdog | `service not found` | A shell one-liner in init `.rc` was too fragile | Put the logic in a script file |

## Security services

| Symptom | Log | Cause | Fix |
|---|---|---|---|
| `keystore2` aborts | `Cannot connect to Keymint` | Result of the problems below | Find why KeyMint isn't running |
| KeyMint can't open a session | `TEEC_ERROR_ITEM_NOT_FOUND`, `TA not found` | `.ta` files weren't installed | Copy `vendor/lib/optee_armtz/*.ta` |
| KeyMint aborts | `stoi: no conversion`, in `set_boot_patchlevel` | Empty patch-level properties | `VENDOR_SECURITY_PATCH`, `BOOT_SECURITY_PATCH`, `ro.vendor.boot_security_patch` |

## System server and UI

| Symptom | Log | Cause | Fix |
|---|---|---|---|
| Boot loop after adding privileged apps | `Signature\|privileged permissions not in privapp-permissions allowlist` | Allowlist missing. `ro.control_privapp_permissions=permissive` didn't prevent it | Generate the XML, as `tools/80-apps.py` does |
| Apps missing after flash | `No APK Signature Scheme v2 signature` | The build rewrote the APK, because of `LOCAL_PREBUILT_JNI_LIBS` | `LOCAL_REPLACE_PREBUILT_APK_INSTALLED`, with libraries copied beside it |
| App crashes on loading a library | `UnsatisfiedLinkError` | Compressed JNI isn't extracted for system apps | `lib/<arch>` beside the APK |
| Black screen with audio after adding GApps | `ANR in ...setupwraith`, Google's setup video playing | Google's setup app on 1 GB of RAM, with no swap | Remove `SetupWraithPrebuilt`, and fix swap |
| "Choose your home app" prompt | `ResolverActivity` on top | Phone `Settings` also declares HOME | Override `Settings`. Keep `TvSettings`, which provides the fallback home |

**The setup wizard:** `LineageSetupWizard` handles first-run Wi-Fi, remote and language. It has no Google login, and it exits at once if Google's setup app is installed. Removing it was a mistake that the user caught. Keep it.

## Memory

| Symptom | Evidence | Cause | Fix |
|---|---|---|---|
| Thrashing, load of 20–30 | `SwapTotal: 0`, `MemAvailable: 0` | zram never started: stock's rule waits on `vold.post_zram_writeback`, which AOSP's vold doesn't set | `templates/memory/swap.sh` |
| Menus close by themselves, Google sign-in fails, swap free | `killinfo` with `min_oom=1`, reason `-1`; `lowmemorykiller: Kill` at `oom_score_adj` 100 or less | Stock's `ro.lmk.use_new_strategy=false` and `ro.lmk.critical=1`. The old strategy ignores swap | Remove those. `use_new_strategy=true`, `thrashing_limit=100` |
| Swap file not created | `fallocate: -l > 2147483647` | 32-bit toybox limit | Use 2147483647 |
| Swap script fails on first boot | Runs before `/data/vendor` exists | Timing | Wait for the directory |
| High RSS from a phone stack on a TV | `com.android.phone`, `cellbroadcast`, `imsserviceentitlement`, `smspush`, 42–46 MB each | `atv_base.mk` inherits telephony. Changing the top-level inherit does nothing | Override those modules: `templates/remove-apps/`. Verify in the build output |

**Read memory correctly:** RSS double-counts shared pages. Use `MemAvailable`, `SwapFree` and `dumpsys meminfo`. Note that `dumpsys meminfo` can fail when `system_server` is busy.

## Wi-Fi and Bluetooth

| Symptom | Log | Cause | Fix |
|---|---|---|---|
| Both missing, no `wlan0`, no `/dev/BT*` | `wait scan card time out`, `scan card fail` | **The UART console blocked the kernel.** 136 lines in a roughly 1 s window, at 115200 baud, is about 1.4 s of output | `write /proc/sys/kernel/printk 4` before drivers load, plus one retry after boot |
| Wi-Fi off | `Can not initialize the vendor function pointer table` | AOSP's `libwifi-hal` is only a stub | Stock's `libwifi-hal` as a prebuilt |
| Wi-Fi service crashes | SIGSEGV in `skw_wifi_get_chip_feature_set` | AOSP service versus stock library | Stock's service too, with its VINTF fragment |
| Bluetooth crash loop | `assertion 'was_validated_' failed`; `UNKNOWN_HCI_COMMAND opcode:0xfd5e` | Controller rejects a vendor command; the shim reads the empty response | Remove `persist.bluetooth.bqr.*`, and apply the shim patch |
| Bluetooth HAL fails | `skwbt_boot_open: unable to open` | Chip driver not loaded | See the first line of this table |
| Android stopped retrying | `Already restarted wifi 2 times`; Bluetooth state OFF | Android gives up after repeated failures | After fixing, use `cmd bluetooth_manager enable` and `cmd wifi set-wifi-enabled enabled` |

**A trap:** an earlier boot worked, which made the driver look fine. Timing bugs come and go. Check a clean boot before you trust a result.

## Input

| Symptom | Evidence | Cause | Fix |
|---|---|---|---|
| IR remote partly dead | `KeyLayoutFile: Generic.kl` in `dumpsys input` | Stock's `.kl` uses keycodes only its own framework defined (`APPS`, `MOUSE`). One unknown name rejects the whole file | Replace or remove those lines |
| Keys ignored after pressing Power | `policyFlags` without the pass-to-user bit | The device is asleep | Not an input bug: check `mWakefulness` |
| Right click does nothing | Stock modified its framework | | `templates/patches/inputflinger-right-button-back.patch` |

**To test input:** run `getevent -lt /dev/input/eventN` while the user presses keys. Then check `dumpsys input` for the resulting `keyCode`. That splits the problem into kernel, key layout and app.

## Feature apps

| Symptom | Evidence | Cause | Fix |
|---|---|---|---|
| Arrow keys "don't work" in the keystone app | **Logs show the keys arriving**, then `HwBinder Error: (-74)` | Qualcomm's library had the name of Allwinner's. Each call failed, and the app only logged it | Rename stock's library |
| Log says "success" but nothing happened | Our own log line printed after a call that caught its exception | Vendor code swallows the error | Check for the error text, not for your own log line |
| Stock app can't be opened | No launcher entry; stock's launcher or framework opened it | | A small companion app: `templates/companion-app-example/` |
| Feature stops after a reboot | Stock's framework restored the state | | Do it in a boot receiver in the companion app |

## Google

| Symptom | Likely causes, in order |
|---|---|
| Add-account menu closes | lmkd killing the flow (check first) |
| "Account not found" | The flow's web process killed mid-way; a key layout mangling `@`; Play services out of date. **Not fully diagnosed on the first device** |
| "Device isn't certified" | Register the GSF ID at google.com/android/uncertified |

**Have the user test sign-in.** Don't handle their credentials. A typo-free address that works elsewhere means the device is at fault, not the account.

## Root

| Symptom | Cause | Fix |
|---|---|---|
| Magisk warns about being a system app | It was bundled in the ROM | Remove it from the ROM, and `adb install` it |
| Daemon runs, `su` missing | First-run setup may be incomplete | Open the Magisk app. It appeared at `/product/bin/su` on a later boot |
| Root gone after a flash | Full flash replaced `init_boot` | `60-flash.sh --init-boot PATCHED` |
| AdAway can't write hosts | `/system` is read-only | Enable Systemless Hosts in Magisk (general knowledge; not yet confirmed on hermes) |

## Screenshots and "black screen" reports

`adb exec-out screencap` shows what SurfaceFlinger composes. A black screenshot doesn't tell you what's on the projector, and a normal screenshot doesn't prove the backlight or panel works. Ask the user what they see. Also check `mWakefulness`, `topResumedActivity` and `/sys/class/backlight/*/brightness`.

## Ways this project misled itself

- **Properties can lie.** A unit that flashed normally reported `ro.boot.flash.locked=1`. Check with the thing that enforces it: `fastboot getvar unlocked`.
- **"It built" isn't "it's installed".** A telephony change had no effect, and I claimed it had. Check the build output after each change.
- **Trust the log, not the user-visible symptom.** "Keys don't work" was a display library. "Dim picture" was a black frame from an overloaded system.
- **Copying stock isn't automatically right.** Stock's tuning made sense for stock's framework and apps.
- **Check whether your own earlier fix is the cause.** At least four failures here came from earlier fixes: the library fix installed Qualcomm's HAL, and the property copy brought BQR and old lmkd settings.
- **Don't remove something you haven't read.** I removed the setup wizard on an assumption. The user caught it.
