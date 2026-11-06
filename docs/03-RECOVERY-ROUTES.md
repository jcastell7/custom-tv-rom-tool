# Ways back, and proving them

> **⚠️ WARNING: this process could very well fully and permanently brick your device.** Only use it on a device you own and can afford to lose. It's provided as is, with no warranty, and **we accept no responsibility** for how it's used or what happens. Not affiliated with LineageOS in any way: we just use and recommend their work, so [please donate to them](https://lineageos.org/about/) when you can. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

If a device is already stuck, go to [`09-BRICK-RECOVERY.md`](09-BRICK-RECOVERY.md).

**The goal:** before the first flash, know exactly how you'd get this device back if a build fails at any stage, and have tested that route.

## Failure stages and what can save you

| Boot fails at | Symptom | What still works |
|---|---|---|
| Android framework, HALs | Boot animation or a black screen, `adb` often up | `adb`, your boot watchdog, fastbootd |
| Second-stage init | Reboots, no `adb` | Watchdog if it started; `init_fatal_reboot_target=recovery` |
| First-stage init | Reboots to bootloader or hangs | Recovery in another image, bootloader fastboot, UART |
| Kernel | Hang or panic | Bootloader fastboot, SoC USB mode, UART |
| Bootloader reading images | Hang before `Starting kernel` | SoC USB mode, updater inside the bootloader, UART |
| Bootloader itself (never touch it) | Dead | SoC USB mode, SD boot, or a hardware programmer |

## The ladder: try to prove each rung

Write down the result of each on this device. You want at least two working routes before the first flash.

| # | Route | Test while stock still works | Notes |
|---|---|---|---|
| 1 | `adb reboot fastboot` reaches **fastbootd** | Run it, then `fastboot devices`, then `fastboot getvar is-userspace` | Needs a working Android or recovery to start from |
| 2 | `adb reboot bootloader` reaches **bootloader fastboot** | Run it, then `fastboot devices` **on the PC** | A fastboot logo on screen doesn't prove the PC sees it. It didn't on the first device |
| 3 | **Hardware trigger** into recovery or fastboot | Ask the user which buttons exist, and try with the power cable | TV boxes often have a button hidden in a port. Ours had a FEL button, not recovery |
| 4 | **UART** | Ask the user to find the pads. Read at 115200 8N1 first, 3.3 V | Read-only needs just TX and GND. u-boot may ignore input even with RX wired |
| 5 | **Bootloader updater from SD or USB** | Look for `auto_update`, `sdupdate`, `aml_autoscript`, `update.zip` strings in the bootloader | This saved the first device |
| 6 | **SoC USB mode** | Enter it, and check the PC sees it. Check you have the tool and the files for THIS SoC | Reachable isn't usable: see below |
| 7 | **SD card boot** | Check the SoC's boot order | Many boxes will boot from SD before eMMC |
| 8 | **Identical donor unit** | Ask the user | Lets you compare, and supplies blobs. Only for the same model and revision |

## SoC USB modes: general knowledge, not verified here

Only the Allwinner row was tested in this project. Verify the others before relying on them, and check support for your exact chip.

| SoC | Mode | Common tools | Things to check |
|---|---|---|---|
| Allwinner | FEL | `sunxi-fel`, PhoenixSuit | Tested: FEL was reachable on H723, but `sunxi-tools` didn't support SoC ID `0x1911`, so nothing could be loaded with it |
| Rockchip | Maskrom, Loader | `rkdeveloptool`, RKDevTool | Needs a `MiniLoader` for the exact chip |
| Amlogic | USB burning mode | `aml-flash-tool`, USB Burning Tool | Needs a matching full image; a burn can erase bootloader data |
| MediaTek | BROM, Preloader | `mtkclient`, SP Flash Tool | Secure-boot chips may need an auth file or exploit |
| Qualcomm | EDL (9008) | `edl`, QFIL | Usually needs a signed programmer for the device |

**The trap:** USB mode being reachable means nothing until you've loaded something through it. Test: read something harmless through it.

## Finding an updater inside the bootloader

This is what saved the first device. A TV box bootloader often scans USB or SD for an update script.

1. Get the bootloader binary from your backup. Run `strings` on it, and look for `auto_update`, `usb start`, `fatload`, `sunxi_flash`, `update/`, `script`.
2. Read the UART log during boot with a USB stick inserted. On the first device: `List file under ULI/factory`, and a scan for `update/auto_update.txt`.
3. Test with something harmless first, like `echo` or `printenv`. Start with read-only commands, and only ever use RAM addresses you've confirmed.
4. Read `reference/hermes/docs/13-fastboot-trigger-no-fel.md` and `15-uboot-reverse-engineering.md`. They show the whole method, including the failed attempts.

**The first device's tricks** (Allwinner u-boot 2018.07; **addresses and parser details won't apply elsewhere**):
- Script lines were built as `"%s %s 0x%lx %s 0x%x"`, so tabs inside the first word, plus a trailing `;`, allowed arbitrary commands.
- An environment variable set by one command changed how the next line was parsed.
- Setting a cache flag in RAM made u-boot use images loaded from the stick, so stock recovery booted **from RAM without writing to the eMMC**.

That last idea, running a known-good recovery from RAM, is worth looking for on any device. It lets you get `adb` root with nothing written.

## One-shot boots: test without flashing

If it works on your device, this is the safest way to test a build:

```bash
fastboot boot boot.img        # one boot, nothing written
```

Support varies, and it's limited on devices with `vendor_boot` and `init_boot`. If it isn't available, use the fallback in `templates/fallback/`.

## A/B slots

If slot `_b` holds a working stock OS, you may be able to flash `_a` and switch back. Check first: on the first device `_b` was zeros. With Virtual A/B, both slots share `super`, so flashing `super` affects both. Having two slots doesn't mean having two OSes.

## Writing the plan down

Before the first flash, write this in `devices/<codename>/NOTES.md`:
```
Stage reached  | Action                   | Tested on this device?
framework      | watchdog -> fastbootd     | no build yet
kernel         | ...                       | yes/no
```
Show it to the user. If the only route for an early failure is "no idea", don't flash yet.
