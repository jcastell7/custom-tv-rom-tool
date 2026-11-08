# Real-world timing

Scripts where the user presses SPACE at moments only they can see or hear. **Totals use only the user's own presses.** USB, `adb`, Android's log and the kernel's uptime are shown for context. See [`docs/13-TUNING.md`](../../docs/13-TUNING.md), section 1.

| Script | Device state at start | User presses SPACE | Sends anything? |
|---|---|---|---|
| `startup-timer.sh` | off, USB connected | with the power button, then at the home screen | no (`--reboot` restarts it, for testing) |
| `startup-marks.sh` | off, USB connected | with the power button, when the picture changes, at the home screen | no |
| `shutdown-timer.sh` | on, `adb` connected | when the fan stops | **yes:** power key twice (or `--svc`) |
| `shutdown-marks.sh` | on, `adb` connected | with the power button, when the picture goes dark, when the fan stops | no |

- Set `DEVICE_USB_IDS` to your device's USB vendor IDs, for example `DEVICE_USB_IDS='2207|18d1'`. The default is `1f3a|18d1` (Allwinner and Google).
- Results go to a `.csv` next to each script, which git ignores.
- Hand presses add a few tenths of a second each way, so run each one a few times.
- The startup scripts work out when the kernel started from `/proc/uptime`. Everything before that is power-on and the bootloader.

**Tested:** on the first device, `shutdown-timer.sh` (menu path) ran fully. An early `startup-timer.sh` ran too, but its bootloader split was wrong until the uptime quoting fix. Everything since was tested with a simulated `adb` and `lsusb`. **Report what fails.**

**Bugs already fixed, so don't reintroduce them:** `awk 'print'` gives epoch times as `1.79e+09`, so use `printf "%.3f"`. `adb shell cmd 'a b'` loses the inner quotes, so pass one quoted string. With no keyboard (stdin at end of file), the scripts must abort, not start.
