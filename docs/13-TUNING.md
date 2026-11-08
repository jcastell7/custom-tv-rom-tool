# Tuning a working build: debug cleanup, boot time, shutdown, power button

> **⚠️ WARNING: this process could very well fully and permanently brick your device.** Only use it on a device you own and can afford to lose. It's provided as is, with no warranty, and **we accept no responsibility** for how it's used or what happens. Not affiliated with LineageOS in any way: we just use and recommend their work, so [please donate to them](https://lineageos.org/about/) when you can. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

Do this once the ROM boots reliably and the user's features work. It covers what was done on the first device after bring-up, in the order that worked. Every number here was measured on that device, unless marked otherwise. Other devices will differ, so **measure before and after every change**, and keep only what helps.

On the first device, startup went from **65.6 s to about 33.6 s**, counted from kernel start to the end of the boot animation. The user's own stopwatch run, from pressing power to Android reporting boot completed, gave 43 to 47 s. Power-off took about **10 s** from confirming to the fan stopping.

## Contents
1. [Measure first](#1-measure-first): tools and methods
2. [Remove the bring-up debug settings](#2-remove-the-bring-up-debug-settings), in two flashes
3. [Faster boot](#3-faster-boot): what helped, and how it was found
4. [Faster shutdown](#4-faster-shutdown): where the time goes, and what didn't help
5. [Power button, sleep, lamp and fan](#5-power-button-sleep-lamp-and-fan)
6. [Smaller fixes found along the way](#6-smaller-fixes-found-along-the-way)
7. [Build and flash traps hit while doing this](#7-build-and-flash-traps)
8. [Mistakes to avoid](#8-mistakes-to-avoid)

---

## 1. Measure first

**Rule:** one change per flash, at least two boots per measurement, and never the first boot after a flash. That first boot was about 10 s slower on the first device. Write every result down in `devices/<codename>/NOTES.md`.

### Automatic measurements (no user needed)

| What | How | Tool |
|---|---|---|
| Boot stages | Event log: `boot_progress_start` (zygote), `system_run`, `pms_ready`, `ams_ready`, `enable_screen`, `sf_stop_bootanim` (animation ends). Values are ms since the kernel started | `tools/76-boot-profile.py` |
| Slow system_server steps | `SystemServerTiming: X took to complete: N ms` in logcat | same |
| Slow init steps | `init: ... took Nms` and `waiting took` in `dmesg`, plus gaps between lines | same |
| The first seconds of boot | `dmesg` right after `adb` appears. **Add `log_buf_len=1M` to the vendor command line**, or the buffer rolls over before you can read it | same |
| What a thread is stuck on during boot | Stack traces at a fixed uptime, from a temporary Magisk script, because `adb` arrives too late | `tools/78-boot-stacks.sh` |
| Shutdown steps | Kernel log copied to `/metadata` during a shutdown, from a temporary Magisk script | `tools/77-shutdown-log.sh` |

### Real-world measurements (the user presses keys)

`tools/measure/` has four scripts. The user presses SPACE at moments only they can see or hear. **The total uses only the user's own presses.** The automatic marks (USB, `adb`, boot completed, Android's log) are shown for context only. The user asked for this, because it measures what they experience.

| Script | User presses SPACE | Also records |
|---|---|---|
| `startup-timer.sh` | with the power button, then when the home screen appears | USB, `adb`, boot completed, kernel start, Android's boot stages |
| `startup-marks.sh` | with the power button, when the picture changes, when the home screen appears | the same |
| `shutdown-timer.sh` | when the fan stops. The script sends the shutdown itself (power key twice, or `--svc`) | when Android's shutdown started, when `adb` dropped |
| `shutdown-marks.sh` | with the power button, when the picture goes dark, when the fan stops. Sends nothing | the same |

Kernel start is worked out from Android's uptime: host time minus `/proc/uptime` gives the moment the kernel started. Everything before it is power-on and the bootloader. The scripts look for USB IDs in `DEVICE_USB_IDS` (default `1f3a|18d1`, Allwinner and Google). Set it for your device.

### Measuring pitfalls (each one cost time)
- **`adb shell svc power reboot` starts a Java VM first**, which took 0.3 to 3.6 s before it even asked for the restart. A power-off from the menu doesn't have that delay. Time from Android's own log line (`ShutdownThread: Logging pre-reboot information`), not from the command.
- **Wait for the device to go down before polling `sys.boot_completed`.** Otherwise you read 1 from the old boot, and get a "5 s boot".
- **`/proc/kmsg` is read destructively, and logd reads it too.** Use `dmesg -w`, which reads `/dev/kmsg` without consuming it.
- **Don't raise the console log level to see more:** with a UART console, more output slows the very thing you're timing. The full log is in `dmesg` anyway.
- **`adb shell cmd 'a b'` loses the inner quotes.** `adb shell cut -d' ' -f1 /proc/uptime` became `cut -d -f1`, failed, and silently broke every value derived from it. Pass the whole command as one quoted string.
- **`awk '{ print t + 240 }'` with an epoch time prints `1.79409e+09`**, which rounds the value. Use `printf "%.3f"`.

---

## 2. Remove the bring-up debug settings

`templates/fallback/` and the early builds add settings that make debugging easier and failed boots recoverable. Remove them once the device boots and flashes reliably, and the user agrees.

| Setting | Why it was added | Remove? |
|---|---|---|
| `printk.devkmsg=on` on the vendor command line | userspace logs in the kernel log | Yes. It also slows boot with a UART console |
| `ro.adb.secure=0` | `adb` without authorization | Yes. The user then accepts this computer once on screen. **Warn them first**, or you lose `adb` until they do |
| Boot watchdog (`boot-watchdog.sh`, its service, the boot counter in `/metadata`) | failed boots go to recovery | Yes, in a **second** flash |
| `hermes_auto_fastbootd` in recovery's `.rc` | recovery switches itself to fastbootd | Yes, in the second flash |
| `androidboot.init_fatal_reboot_target=recovery` | a fatal init error goes to recovery, not to a fastboot the PC can't see | **Keep it.** It costs nothing in normal use. The user chose to keep it |
| Console quieting (`write /proc/sys/kernel/printk 4`) | the UART console blocked the kernel | Keep it, and move it from `post-fs-data` to `early-init` (section 3) |

**Don't touch these as part of a cleanup:** SELinux permissive (stock was permissive too, and a placeholder policy would deny everything), and dm-verity off (turning it on is a separate change with its own risk).

### Do it in two flashes
1. **Flash 1:** remove everything except the fallback (watchdog and auto-fastbootd). Boot, check `adb`, Wi-Fi, Bluetooth, root.
2. **Flash 2:** remove the fallback.

If flash 1 doesn't boot, the fallback still brings it back to fastbootd. After flash 2, a build that fails to boot needs the recovery menu or the rescue route from `docs/03`. **Tell the user this before flash 2.**

After removing `ro.adb.secure=0`, `adb` showed up about 5 minutes late on the next boot, once. The user may have toggled USB debugging. The boot after that was normal (30 s). Check `adb` on the second boot before deciding something broke.

---

## 3. Faster boot

Results on the first device, from the kernel's start to the end of the boot animation:

| Change | Zygote starts | Animation ends | Boots measured |
|---|---|---|---|
| With bring-up debug settings | 26.5 s | 65.6 s | 1 |
| Debug settings removed | 16.4 s | 53.5 s | 1 |
| Shader cache priming off | 16.5 s | 44.4 s | 1 (test) |
| Boot animation's last part removed | 16.3 s | 38.8 s (later 40.0, 40.2) | 3 |
| Kernel console at `loglevel=4` | 9.9 s | 33.5 to 33.9 s | 3 |

### 3a. Find the biggest wait first
Run `tools/76-boot-profile.py` and look at the largest `SystemServerTiming` items, and at gaps. **On the first device, one line explained 9 s:**
```
SystemServerTiming: WaitForDisplay took to complete: 9311ms
SystemServiceManager: Service com.android.server.display.DisplayManagerService took 9311 ms in onBootPhase
```
`WaitForDisplay` means system_server waits for the default display. It isn't always the display hardware.

### 3b. Shader cache priming (−9 s)
**How it was found:** `tools/78-boot-stacks.sh` captured stacks 27 s into boot, while system_server was waiting:
- system_server's `android.display` thread was in a binder call to SurfaceFlinger (`getBootDisplayModeSupport`), holding the lock `main` waited on;
- SurfaceFlinger's main thread waited on a future in `Output::composeSurfaces`;
- SurfaceFlinger's `RenderEngine` threads were inside `libGLES_mali.so`, in `cmpbe_v2_compile_multiple_shaders` and `llvm::SUnit`: **the Mali driver compiling shaders with LLVM on a slow CPU.**

SurfaceFlinger primes a shader cache at startup unless `service.sf.prime_shader_cache` is false (`SurfaceFlinger.cpp`). Test without a rebuild, with a one-boot Magisk script in `/data/adb/post-fs-data.d/`:
```sh
/debug_ramdisk/magisk resetprop service.sf.prime_shader_cache 0
rm -f "$0"
```
Result: `WaitForDisplay` 9311 ms → 57 ms. Then make it permanent: `PRODUCT_VENDOR_PROPERTIES += service.sf.prime_shader_cache=0`.

**Trade-off:** shaders compile when first used, so a screen may stutter the first time it opens. The user found menus fine.

### 3c. The boot animation's last part (−4 to −6 s)
Lineage's `vendor/lineage/bootanimation/desc.txt` marks every part `c`, meaning "play to the end even when boot is done". The last part played for 3.8 s after the system was ready. `templates/patches/bootanimation-no-end-part.patch` removes it, and makes the loop part `p`, which stops at once. `enable_screen` to animation end went from 6.8 s to 1.1 s.

To rebuild the zip, delete `out/target/product/<p>/obj/BOOTANIMATION` and `product/media/bootanimation.zip`, and `touch` the `desc.txt`. Check the result with `unzip -p .../bootanimation.zip desc.txt`.

### 3d. The kernel console (−6 s)
**How it was found:** `dmesg` from the first seconds (with `log_buf_len=1M`) showed about 600 lines before 6 s. The bootloader passes `loglevel=8`, so every message goes synchronously to a 115200-baud UART. That's about 11 KB/s, and roughly 48 KB of text, so seconds of waiting.

**Fix:** add `loglevel=4` to `BOARD_KERNEL_CMDLINE`. Later parameters override earlier ones, so the vendor command line wins over the bootloader's. Also move `write /proc/sys/kernel/printk 4` to `on early-init`, which covers second-stage init too.

**Trade-off:** the UART then shows only warnings and errors during kernel startup. For a brick investigation, take it out again, or interrupt the bootloader and set `loglevel=8` for one boot.

This is the same cause as an earlier Wi-Fi and Bluetooth failure (`docs/05`, "The UART console blocked the kernel"). **If a device has a UART console, check the log level early.**

### 3e. What's left, and what wasn't worth it
After these, the boot on the first device looked like this, in kernel uptime:
- **0 to 3.3 s:** kernel.
- **3.3 to 6.5 s:** first-stage init, including 0.7 s of modules.
- **6.5 to 10 s:** second-stage init setup, including APEX bootstrap (1 s).
- **10 to 14 s:** mounting, APEXes, display modules (0.4 s), waiting for `odsign` (0.7 s), Magisk (0.25 s), then `bpfloader` (1.75 s).
- **After 10 s:** Android, about 24 s to the end of the animation.
- **Before the kernel:** 2 s or more of bootloader and power-on, which the timer scripts show.

Not tried, and why:
- **Zygote preload (3 s):** cutting it moves work to app start.
- **Removing services:** small gains, and each removal risks a missing feature.
- **`bpfloader`:** networking needs it.

---

## 4. Faster shutdown

### 4a. Measure it without a UART
`tools/77-shutdown-log.sh` installs a temporary Magisk `service.d` script that waits for `sys.shutdown.requested`, then appends each kernel log line to `/metadata/<file>`, opening and closing the file per line so `/metadata` can still unmount. It restarts the device twice: once to start the logger, once for the measured shutdown. Then it pulls the log and deletes it.

Why it works:
- **Processes Magisk starts aren't in any init service's cgroup**, so init's "stop all services" step doesn't kill them. `magiskd` is in the root cgroup.
- `/metadata` stays mounted until near the end. Lines after it unmounts are lost, but that's the last moment only.

**Trap:** Magisk runs these scripts under BusyBox `ash`, where `dmesg` is BusyBox's version, with no `-w`. **Call `/system/bin/dmesg`.** The first attempt only logged its header line.

### 4b. Where the time goes (first device, one restart)

| Step | Time |
|---|---|
| ShutdownThread: shutdown broadcast 1.07 s, activity manager 0.94 s, package manager 0.07 s, plus Bluetooth chip stop | about 2.4 s |
| init: `Stopping 112 services by sending SIGTERM`, sent one by one, then `Waiting for 50 pids to be reaped took 1194ms` | about 2.3 s |
| `vdc volume shutdown`, `sync()` | 0.5 s |
| `apexd --unmount-all`: 31 APEXes, about 70 ms each | 2.1 to 2.5 s |
| unmount `/data` and the rest, `sync()`, kernel power-off | about 2 s |

Init logs `So far shutdown sequence took Nms` before unmounting APEXes, so it's an easy number to compare between builds.

The user measured 9.6 s from confirming power off to the fan stopping. Their estimate was about 10 s.

### 4c. What helped and what didn't

| Change | Result |
|---|---|
| Turn the swap file off when shutdown starts: `exec_background - root root -- /system/bin/swapoff <file>` on `sys.shutdown.requested`. An active swap file on `/data` can stop `/data` from unmounting | restart time 18.5 s → 16.4 to 17.2 s. Small, kept |
| Remove `blank_screen` (from `hardware/interfaces/light`). It waits for a lights HAL, and failed after 2.2 s with exit 255 | **no measurable gain**: it's `shutdown critical`, so init doesn't wait for it. Kept removed because it only failed. Override it in `templates/remove-apps/` |

**Don't lower `ro.build.shutdown_timeout`** (default 6 s). It caps the wait for services, and then gives the unmount step the rest of the budget. Too low, and init kills everything and forces the unmount, which risks data in `/data`. The remaining time is real work: stopping services, unmounting and syncing.

---

## 5. Power button, sleep, lamp and fan

### 5a. What went wrong
On LineageOS, a short press of power put Android to sleep. On the first device:
- **The lamp and fan kept running**, with only the picture black;
- **with USB unplugged, the device froze** in deep sleep and needed a power cut;
- no log survived, so the exact cause isn't proven.

**Why it was never caught over `adb`:** with a USB cable plugged in, the `usb_connecting` wake source blocks suspend. You can't reproduce the freeze while connected. `cat /sys/kernel/debug/suspend_stats` showed 0 attempts.

### 5b. How stock did it
Find it in stock's framework (see `docs/06`):
```bash
unzip services.jar 'classes*.dex' -d s
dexdump -d s/classes2.dex > dump.txt
grep -n '/sys/class/' dump.txt
```
On the first device that found:
- **`/sys/class/backlightandfan/{backlight,fan,led}/value`**, written by `ShutdownThread.BacklightEnable` and `FanEnable`, called from `ShutdownThread.run`. The lamp and fan have their own switches. `/sys/class/backlight/<x>` didn't control the lamp.
- `PhoneWindowManager.powerPress` started with a call to `showGlobalActionsInternal`. **Stock opened a power menu on a short press, and didn't sleep.**

The device tree showed the same driver: `compatible = "allwinner,backlightandfan"`, with `backlight-gpios`, `fan-gpios`, `led-gpios`.

### 5c. What the user wanted, and the fix
The user always unplugs the projector, so standby has no value for them. They asked for a power menu on a short press, and for a second press to confirm power off.

| Piece | Where |
|---|---|
| Short press opens the power menu, a press while it's open powers off | `templates/patches/framework-power-button-menu.patch` (`PhoneWindowManager.powerPress`, `GlobalActions.isShowing`) |
| Never suspend: `write /sys/power/wake_lock <name>` `on boot` | `templates/power/power.rc.snippet` |
| Lamp off when shutdown starts; **fan left running until the power goes off**, so the fan stopping tells the user it's safe to unplug | same |
| Swap file off when shutdown starts | same |

**Patch detail:** `GlobalActions.mShowing` is true from `showDialog` until SystemUI reports it dismissed. When adding `isShowing()`, don't put it between an `@Override` and the method it belongs to. The first build failed that way (`method does not override or implement a method from a supertype`).

**Holding power** stays a shutdown with no confirmation (`config_longPressOnPowerBehavior` 3, as stock).

**Test it:** `adb shell input keyevent 26` should open the menu (check the focused window is `ActionsDialog`), and `input keyevent 4` closes it. Don't test the second press over `adb` unless the user can switch the device back on.

### 5d. If a user does want standby
Not built. An option that was tested for 2 minutes: Android asleep, the lamp and fan switched off through the sysfs files, and kernel suspend blocked. The CPU went from 43 °C to 51 °C, with no fan. **Measure temperatures over a long run before relying on it.** Ask the user what stock did first: here, stock never slept.

---

## 6. Smaller fixes found along the way

| Problem | Cause | Fix |
|---|---|---|
| "Remote and accessories" is an empty page | TvSettings shows nothing when Bluetooth is off, because `show_bluetooth_toggle` defaults to false and the pair button needs Bluetooth on. Reproduced with `cmd bluetooth_manager disable` | Overlay `show_bluetooth_toggle` true: `templates/overlay/`. The IR remote can turn Bluetooth back on |
| Apps never get root, no prompt | **Magisk 31.1 has no prompt.** A request from an app with no stored policy is rejected (`su: request rejected (<uid>)` in `/cache/magisk.log`). Read from v31.1's `su/daemon.rs` and seen on the device | Grant in Magisk's Superuser tab. From `adb`: `magisk --sqlite "REPLACE INTO policies (uid,policy,until,logging,notification) VALUES(<uid>,2,0,1,1)"` |
| AdAway: "not enough space" | It compares its hosts file (2.37 MB) with the free space where `/system/etc/hosts` lives: the system partition, 2.1 MB free and read-only. `/data` space plays no part | A Magisk module `/data/adb/modules/hosts` with `module.prop` and `system/etc/hosts`, which is what "Systemless Hosts" makes. Reboot. Uninstalling apps doesn't help |
| `adb root` refused: "disabled by system setting" | LineageOS's rooted debugging toggle | Developer options, "Rooted debugging". It needs the user's agreement |
| Google sign-in "account not found" | **Not found.** It worked later with no change made | Get logs from the attempt itself |

---

## 7. Build and flash traps

| Trap | What happened | Avoid it |
|---|---|---|
| The build tree has a separate copy of the device tree | Edits in the git repo never reached the build | Sync with `rsync -a --delete`, then compare with `diff -rq` |
| **`rsync -a` keeps old timestamps** | Edited files were older than `out/build-<product>.ninja`, so make silently didn't re-read them. A new file in the same sync was picked up, which hid the problem | `touch` every changed file after syncing |
| Changing only the kernel command line or a property doesn't rebuild some images | `vendor_boot.img` and `vendor/build.prop` kept the old values | Delete them and `obj/PACKAGING/vendor_boot_intermediates` |
| A failed build left old images in `out` | A script flashed them anyway, because it ignored the build's exit code. Nothing broke, since they were the previous working build | **Check the exit code, then check each change is in the images before flashing:** `strings vendor_boot.img`, `grep` the `.rc` and `build.prop`, `dexdump` the jar for the changed method |
| The gate pointed at the wrong stock folder | Two false FAILs about header version and name | Use the backup copied from the device's own partitions |
| `fastboot getvar partition-size` came back empty once | The flash script read it as 0, and refused | Re-run it. The script refused rather than writing anything |
| `set -o pipefail` with `... \| head` | Exit 141 (SIGPIPE) stopped a script halfway | Don't pipe into `head` under pipefail, or make the script safe to re-run |

---

## 8. Mistakes to avoid

These were made on the first device, and some were mine as the agent:
- **A wrong theory about Magisk.** The agent blamed a missing `stub.apk` in the boot image. Magisk 31.1's patcher doesn't use one. Read the version's source before theorizing.
- **A contaminated test.** To show that Bluetooth off empties the accessories page, the agent first opened the pairing activity, which turned Bluetooth back on. Change one thing per test.
- **Treating `svc`'s startup as shutdown time.** See section 1.
- **Stating the second power press worked before testing it.** It couldn't be tested over `adb` without powering the device off. Say so.
- **Using an automatic mark as a total.** The user wanted totals from their own presses only.
