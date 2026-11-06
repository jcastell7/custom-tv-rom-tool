# The device is bricked: what to do now

Use this when a device won't boot. `03-RECOVERY-ROUTES.md` covers preparing beforehand. This covers the emergency.

**Most "bricks" are not bricks.** The first device wouldn't boot and looked dead, yet its hardware and bootloader were fine. It only lacked a way to receive new images.

## First, stop and do no harm

1. **Don't flash or erase anything yet.** Don't try commands from forums.
2. **Don't throw away any file you don't understand**, including odd dumps. A dump I called junk turned out to hold the only copy of the bootloader.
3. **Don't apply firmware from a similar model.** Bootloaders hold board-specific DRAM settings, so the wrong one can create a much harder brick. Don't use firmware for a "related" SoC either.
4. **Beware key combinations from other devices.** A research note on a related projector says its remote's Home key at power-on can trigger a factory wipe.
5. Ask the user exactly what happened, and what they see, and write it down.

## Step 1: Find out how far it boots

Everything depends on this. Check in order:

| Check | How | Tells you |
|---|---|---|
| Screen | Logo? Which one? | Which stage runs. The first device had two screens that looked alike: a robot was u-boot fastboot, and a text menu was Android recovery |
| USB on the PC | `lsusb` while booting, `dmesg -w` | What mode it enumerates in. `18d1:4ee0` was fastboot, `1f3a:efe8` was Allwinner FEL |
| `adb devices`, `fastboot devices` | | Whether Android or fastboot is reachable |
| UART | See below | The best evidence. Exactly where it stops |

**Don't guess where it stops.** We spent days on a "kernel hang" theory, and UART showed the kernel had never started.

### UART

- Ask the user to find the pads: TX, RX, GND, usually near the SoC or labelled on the board. Measure for 3.3 V idle on TX. **Never connect a 5 V adapter, or the VCC pin.**
- Connect PC RX to device TX, and GND to GND. Start read-only, at 115200 8N1. Some SoCs use 1500000 (Rockchip, general knowledge).
- If the voltage drops when the adapter is connected, check whether the adapter is plugged into the PC. An unpowered adapter pulled our line down to 1.7–2.3 V, which looked like a fault.
- Test the adapter with a loopback: connect its TX to its RX, and type.
- If `key press :` or a similar prompt appears at the very start, try sending characters. On the first device boot0 accepted **`d`, which turned on debug logging** in u-boot, showing the stop point for the first time. Send one with: `[ -c /dev/ttyUSB0 ] && while printf 'd'; do sleep 0.005; done > /dev/ttyUSB0`. Keep it to the power-on moment. See `00-SAFETY.md` for how this can go wrong.
- u-boot may ignore all input, even with RX working. That was the case on the first device. A missing prompt doesn't mean a wiring fault.

## Step 2: Choose a route by what you found

| What you found | Go to |
|---|---|
| Android runs, or `adb` works | Route A |
| Stops in Android, no `adb`, bootloader is fine | Route B, C, D |
| Fastboot screen, PC sees it | Route C |
| Fastboot screen, PC doesn't see it | Route D, E |
| Bootloader log stops before the kernel | Route D, E, F |
| No bootloader output at all, or nothing at all | Route G, H, I. This is the hard case |

## The routes

Status on the first device is in brackets.

### A. `adb` works [worked]
```bash
adb reboot fastboot      # fastbootd
adb reboot recovery
adb reboot bootloader
```
Then reflash a good build with `tools/60-flash.sh`.

### B. Wait for a fallback [worked, on builds that had it]
With `templates/fallback/`, a failed Android boot returns to fastbootd after 3 tries, or after 15 minutes. **Give it those 15 minutes** before you try anything else, and leave USB plugged in. Check `fastboot devices` periodically.

### C. Fastboot works [fastbootd worked; bootloader fastboot was never seen by the PC]
- `fastboot getvar all`: partition names, slot, and whether it's userspace. Save this output.
- **fastbootd** (`is-userspace: yes`) can write logical partitions inside `super`. Bootloader fastboot often can't, or treats `super` as one raw partition.
- If `fastboot format userdata` refuses because of a `raw` type, use `fastboot format:ext4 userdata`, or `erase`.
- **Flash `vendor_boot` first if stock's holds recovery.** That stops recovery depending on any external route. See `reference/hermes/rescue-stick/restore-stock-fastbootd.sh`.

**If the PC doesn't see the device in fastboot,** try: a different cable and USB 2 port, the OTG port specifically (TV boxes often have one, sometimes needing a USB-A to USB-A cable), and having the cable connected before power-on. Check `dmesg -w`. On the first device, none of this helped with bootloader fastboot.

### D. Bootloader updater from a USB stick or SD card [**this saved the first device**]
Many TV box bootloaders scan removable storage at boot, which can run with the OS completely broken.

**Identify it:**
- UART log lines such as `sunxi update check`, `scanning usb for storage`, `List file under ULI/factory`, `aml_autoscript`, `sdupdate`.
- If you have the bootloader binary, run `strings` on it.

**The file on the first device:** `update/auto_update.txt` on the stick, one command per line, `#` starts a comment, and everything after `%` is ignored. The documented form is `sunxi_flash write <file path> <partition>`. Other firmware uses different names. A similar projector's guide (a different SoC, so only a lead) is at [HY300 USB burn guide](https://github.com/YuujiLab/HY300-H713-Research/blob/main/Firmware/USB_BURN_GUIDE.md). The first test there, with `printenv` then `%`, proved the stick was being read.

**The safe sequence that worked:**
1. Format the stick: FAT32 on MBR, not GPT. Use a USB 2 stick, in the port the bootloader scans.
2. Test with commands that only print, like `printenv` and `help`.
3. Find what the parser does to your lines: it may append arguments. On the first device, tabs inside a word and a trailing `;` allowed real commands.
4. Read-only tests next. Dump to the stick with `fatwrite` if it exists.
5. **Try booting a known-good image from RAM before writing anything.**
6. Use `fastboot` from the script if the PC can see it.
7. Only if needed, write partitions, one at a time, reading each back with a CRC. Never the bootloader, env or GPT.

**Traps on the first device** (details differ elsewhere):
- There was no `if`, no `test` and no `gpio`, and `if` lines were not skipped: **the commands between them still ran**.
- A small read size caused a RAM overrun and a crash.
- A file that was an exact multiple of 8 MiB made the updater silently skip that line's command. So did a large `filesize` left by an earlier command.
- Loads near a certain address overwrote u-boot's own data. Keep clear of the monitor and TEE, at `0x48000000` there.
- The stick must come out afterwards, or the script runs again on each boot.

**For the first device:**
```bash
reference/hermes/rescue-stick/make-stick.py rescue  /path/to/usb-stick   # u-boot fastboot
reference/hermes/rescue-stick/make-stick.py ramboot /path/to/usb-stick   # stock recovery from RAM, nothing written
reference/hermes/rescue-stick/make-stick.py restore /path/to/usb-stick   # WRITES stock's boot chain, with CRC checks
reference/hermes/rescue-stick/make-stick.py check UART.log                  # compare CRCs
```
**These addresses are for one u-boot build only** (`Relocation Offset is: 2c909000`). **Never run them on another device.** `make-stick.py` expects its repo layout, so run the copy in the project's `tooling/rescue-stick/`.

Full history, including all failures: `reference/hermes/docs/13-fastboot-trigger-no-fel.md`, `15-uboot-reverse-engineering.md`.

**To get root from RAM-booted recovery:** on UART's root shell, `setprop sys.usb.config none`, then `setprop sys.usb.config adb`. `adb root` then works, and you can run `tools/20-backup.sh`. Using `fastboot` in place of `adb` returns to fastbootd.

### E. UART prompt [not available on the first device]
If you can interrupt the bootloader (a key, or a stream of characters during a short `bootdelay`):
```
printenv            # save this first
fastboot            # or: run boot_fastboot, fastboot usb 0
setenv force_normal_boot 0; boot   # Allwinner: recovery, on images that contain one
```
Commands vary widely. Read `help` first. Avoid `saveenv`, `erase`, `mmc write` and `sunxi_flash write`. Don't change env permanently without a plan.

### F. Boot mode flags [partly worked]

| Flag | How it's set | Notes |
|---|---|---|
| RTC register | Written by a kernel reboot, or from a stick | `0x07090118` on H723: `0x5c` recovery, `0x5f` fastboot, `0x5a` FEL. A kernel reboot's flag survived the restart. One set from the stick with `mw.l`, then `reset`, didn't. Set in the same boot, it worked |
| `misc` partition (BCB) | `boot-recovery` string at the start | u-boot honoured it on hermes. Needs a way to write it |
| `env` | `bootcmd`, `force_normal_boot` | **Dangerous.** A bad env can stop the boot, and fixing it needs a flash route. u-boot may also rewrite `bootcmd` at boot. CRC-correct images were generated in `reference/hermes/env-fastboot-trigger/`, but **were never tested on hardware** |

### G. Physical buttons, remote keys [button: FEL only; remote: not useful]
- Ask the user about holes in the case, inside ports (AV, USB), and under labels. Hold with a toothpick during power-on, for 8–10 seconds.
- **A button may not do what it seems to.** The first device's hidden button entered FEL, with a black screen, which looks dead but isn't.
- Keys can be read by the ADC, by GPIO, or from the remote at boot. On hermes u-boot logged `ir boot recovery not used`, and holding the power button changed nothing.
- **Only ever pull an ADC pin to ground, through a resistor, and never apply voltage.** Its limit may be about 1.8 V.

### H. SoC USB mode, and vendor burn tools [reachable, not usable on the first device]
See the table in `03-RECOVERY-ROUTES.md`. You need three things: the tool to support your exact chip, a loader or image for your exact board, and a way into the mode.

- On H723, FEL was reachable (`1f3a:efe8`), but `sunxi-tools` didn't know SoC ID `0x1911`. Building it needs `libusb-1.0-0-dev` and `libfdt-dev`.
- u-boot also logged `usb burn from boot`, an Allwinner USB handshake for PhoenixSuit. Using it needs a complete vendor image, which we didn't have, and which can erase per-device data.
- An image for a related SoC mustn't be used.

Once you have the boot0, u-boot and partition table from a backup, a vendor image can in principle be built. This was never done here.

### I. Hardware routes [not tried]
Last resorts, and only with the user's decision:

| Route | Needs | Risk |
|---|---|---|
| SD card boot | SoC boot order that allows it, and a board-matched bootloader on the card | Low: doesn't touch eMMC. The first device had no SD slot |
| Direct eMMC access | Soldering to CMD, CLK, D0, power and GND, with a 3.3 V/1.8 V reader. Bypasses all software | Physical damage. Hold the SoC in reset, or it fights the reader |
| Chip off | Hot air, a reader, good hands | High. Usually a repair shop job |
| Donor unit | The identical model and revision | Low to the donor if read-only: `reference/hermes/donor-extract/` is read-only over `adb`. Gives you a backup and a comparison log |

**Never copy a donor's per-device data** (env, MACs, keys).

## Step 3: After you have access

In this order:

1. **Back up what's there now**, even if it's broken: `tools/20-backup.sh`. Keep the earlier backups too.
2. **Compare with your older backup.** Partitions you never meant to change should still match. A changed bootloader is an emergency in itself.
3. **Make the rescue permanent:** flash a recovery you can reach without external help.
4. **Fix the failure's cause** with `tools/50-gate.py` and `05-DEBUG-CATALOG.md` before you flash again.
5. **Write down what worked**, in `devices/<codename>/`.

## If nothing works

Be honest with the user. Say what's been tried and what's left, and what each remaining option costs. Don't try things that could make it worse just to feel like you're making progress. A stuck device on a shelf can still wait for a donor unit, a new tool release, or a repair shop.

## Restoring stock

- `reference/hermes/rescue-stick/restore-stock-fastbootd.sh` does a dry run by default and writes only with `--commit`.
- Write the OS partitions, and leave out boot0, u-boot, env, misc, GPT and frp, unless you've confirmed they're damaged and it's the user's decision.
- `metadata` can hold `userdata`'s encryption metadata. If you restore or clear it, wipe `userdata` too.
- Older ROMs may be blocked by anti-rollback on some devices. Check `rollback` values in `vbmeta` before downgrading on a locked device.
