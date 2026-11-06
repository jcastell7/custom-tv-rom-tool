# Case study: the "hermes" projector

**The device:** Allwinner H723 (`sun50iw15`) projector, 1 GB RAM, eMMC, stock Android 14, stock kernel 5.15.167 running 32-bit on Cortex-A53. Unlocked, with root `adb` on stock. **The goal:** LineageOS 21 for Android TV, reusing stock's kernel and vendor blobs.

Full detail: `reference/hermes/docs/`. Device tree: `reference/hermes/device-tree/`.

## How it got stuck

1. A backup was taken, but it was incomplete. It held the named Android partitions. Its `bootloader_a` turned out to contain only logos. The real boot0 and u-boot sat outside all partitions and weren't copied.
2. The first LineageOS build was flashed to slot `_a`. It contained **no recovery and no fastbootd**, because the build hadn't been set up to include them.
3. It didn't boot. There was no `adb`. Slot `_b` turned out to be all zeros.
4. Each route out failed:
   - u-boot's fastboot screen appeared, but **the PC never saw it**;
   - the unit had no ADC buttons for a key combination;
   - FEL was reachable with a recessed button, but `sunxi-tools` doesn't support this SoC, and we had no boot0 or u-boot to send anyway;
   - u-boot ignored all UART input.

The unit wasn't physically damaged. It only had no way to accept a new image. **The incomplete backup and the missing recovery caused this, and both are preventable.**

## How it was recovered

- **UART** showed where boot stopped, and boot0 turned out to accept a `d` key for debug output. That corrected a wrong theory: the failure was in u-boot, before the kernel, and not a "kernel hang".
- u-boot's log showed it **scanning USB for an update file**. Reverse engineering u-boot's updater, with capstone (`reference/hermes/uboot-re/ua.py`), showed how it built commands from a script on the stick, and that the script could run arbitrary u-boot commands.
- Many small tests followed. Each was RAM-only, and several failed. A chunked-read quirk even made commands silently not run.
- Setting u-boot's image cache flags in RAM got it to **boot stock recovery from images on the stick, with nothing written to the eMMC**.
- Stock recovery had root `adb`, so **the whole eMMC could finally be copied**, including boot0 and u-boot. fastbootd then accepted new images.

`reference/hermes/rescue-stick/make-stick.py` generates this stick. It's specific to this exact u-boot build.

**One thing that was useful:** `emmchead.img`, which I wrote off as junk, held the intact boot package. The user kept it. Don't dismiss data you don't understand, and don't delete it.

## Then, the boot failures

Each line is one or more flash cycles. **All of them would now be caught earlier by the tools here**, except where noted.

| # | Reached | Failure | Now caught by |
|---|---|---|---|
| 1 | u-boot | `init_boot` header v0 | gate: headers |
| 2 | u-boot | `vendor_boot` name empty (found by code reading) | gate: headers |
| 3 | First-stage init | Duplicate bootconfig keys | gate: bootconfig |
| 4 | First-stage init | No fstab in a ramdisk | gate: fstab |
| 5 | SwitchRoot | Missing `/metadata` and others | gate: fstab |
| 6 | Second-stage init | BPF `ENOTSUPP` | gate: bpf |
| 7 | Services | No boot HAL | day-one checklist |
| 8 | HALs | Missing libraries | gate: symbols |
| 9 | Services | No composer, audio, TAs, properties | gate: vendor, props |
| 10 | Early flash | Watchdog counter survived flashing | fixed in template |
| 11 | Service manager | Duplicate VINTF | gate: vintf |
| 12 | keymint | Empty patch level | gate: props |
| 13 | netd | BPF programs still unusable, twice (division, then modulo) | gate: bpf |
| 14 | **`sys.boot_completed`** | | |

Then:

| # | Feature | Failure | Now caught by |
|---|---|---|---|
| 15 | Wi-Fi | Stub HAL, then service mismatch, then missing library, then missing symbol | gate: symbols, in part |
| 16 | Bluetooth | BQR crash loop | gate: props |
| 17 | Wi-Fi, Bluetooth | UART console blocked the driver scan | gate warns on devkmsg |
| 18 | IR | Key layout rejected | gate: not yet; see 06 |
| 19 | UI | Black screen with Google's setup | playbook |
| 20 | Memory | No swap; old lmkd strategy | gate: props |
| 21 | Apps | Priv-app allowlist boot loop; APK signatures broken | `80-apps.py` |
| 22 | Keystone | Qualcomm library collision | gate: collisions |

## Time spent

Most of the time went on the initial rescue, which should never have been needed, and on repeated flash cycles for bugs a static check can find. With these tools, I'd expect most of the second table's early items to be fixed before the first flash.

## Status when this was written

**Verified on hardware:** boot to home screen, picture, Wi-Fi scanning, Bluetooth on and finding the remote, IR key events, zram and the swap file, recovery fallback, fastbootd, Magisk daemon running, flashes that keep user data.

**Installed, but not confirmed working by the user at the time of writing:** Google login, full F-Droid install, keystone actually moving the picture, HDMI picture and sound, right click as Back, AdAway using root, Symfonium activation.

**Not done:** autofocus (its service wasn't found in stock's app list), stock's framework overlay, audio warnings cleanup, production SELinux, removing bring-up items.

## The lessons, in order of importance

1. **A backup you haven't checked isn't a backup.** Find the bootloader in it.
2. **Prove the way back before flashing.** Reachable isn't the same as usable.
3. **Every build needs its own recovery**, with automatic fallback.
4. **Static checks beat flash cycles.** One gate run takes seconds.
5. **Stock is the reference for how it boots, not for everything.** Match boot settings exactly, but review tuning properties.
6. **Ask the user what the device does before you start.**
7. **Check your earlier fixes when something new breaks.**
8. **Say what you verified, and what you're only inferring.** My wrong claims cost time, and the user caught several.
