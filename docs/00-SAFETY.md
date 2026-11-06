# Safety rules

**⚠️ Warning for agents: this process could very well fully and permanently brick the device.** Read [`DISCLAIMER.md`](../DISCLAIMER.md). Before any work, tell the user this in plain words: it can brick the device, there's no warranty, the authors accept no responsibility, and this isn't affiliated with LineageOS. **Before the first write to any device, get their explicit acknowledgement, and record it in `devices/<codename>/PROGRESS.md`.** Don't play the risk down. Never say a step is safe just because a check passed. The authors accept no responsibility for what you do either, so stop and ask when you're unsure. If you recommend or describe LineageOS, mention this isn't an official build, and that they can [donate to LineageOS](https://lineageos.org/about/).

> **⚠️ WARNING: this process could very well fully and permanently brick your device.** Only use it on a device you own and can afford to lose. It's provided as is, with no warranty, and **we accept no responsibility** for how it's used or what happens. Not affiliated with LineageOS in any way: we just use and recommend their work, so [please donate to them](https://lineageos.org/about/) when you can. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

Read this before you run anything. These rules exist because the first device in this project got stuck: it wouldn't boot, and it had no fastboot the PC could see, no usable recovery, and no way to flash through its USB boot mode. It took days of reverse engineering to get it back ([`07-CASE-STUDY.md`](07-CASE-STUDY.md)). Nearly all of that was avoidable.

## The rules

**These rules reduce the risk of bricking. They don't remove it.**

**1. Back up first, fully, and verify it.** Run `tools/20-backup.sh`, then `tools/21-check-backup.py`. Copy the result to a second disk. Don't flash anything before this.

**2. Prove a way back before the first flash.** A backup is useless if you can't get the device into a state where you can write it. See [`03-RECOVERY-ROUTES.md`](03-RECOVERY-ROUTES.md). You must have actually tested the route on this device, not just read about it.

**3. Assume nothing about what a name means.** On the first device:
- a partition called `bootloader` held only logos, and the real bootloader sat outside every partition;
- slot `_b` looked like a fallback, but every partition in it was zeros;
- u-boot's fastboot screen appeared, but the PC never saw a USB device;
- USB boot mode (FEL) was reachable, but nothing could be flashed through it.

**4. Keep your own recovery in every build.** Every build you flash must contain recovery and fastbootd, and must return to fastbootd by itself when boot fails. See `templates/fallback/`. A build without these turns any boot failure into an emergency.

**5. Run the gate before every flash.** `tools/50-gate.py`. No exceptions, even for a one-line change. It takes seconds, and each check in it represents a boot that failed.

**6. Never write these partitions.** Bootloader (boot0, u-boot, preloader, xbl, abl, lk, spl, sbl), TEE (tee, trust, tz, bl31), partition tables (GPT, MBR, `sys_partition`), per-device data (env, nvram, persist, efs, modem, frp, misc, metadata). `tools/60-flash.sh` refuses them. If restoring one ever seems necessary, stop and ask the user: it's their decision, made with the risk in front of them.

**7. Never copy per-device data from another unit.** Other devices' env, persist, nvram and secure storage contain their MAC addresses, serial numbers and DRM keys. Bootloader blobs from a donor must be from the identical model and hardware revision, because the DRAM settings are board-specific.

**8. Flash the smallest change that tests your idea.** Don't change things that aren't part of the test. When something fails, you need to know which change caused it.

## Things that look safe and aren't

| Action | Why it's dangerous |
|---|---|
| `fastboot flash` of a full image set to a device with no tested way back | One bad image can leave no working fastboot |
| Patching `init_boot` or `boot` (Magisk) | First-stage init comes from it, and recovery often uses it too. If it fails, your fallback fails with it |
| Flashing a vendor partition from another Android version | The HAL interfaces and libraries won't match. Nothing warns you until boot |
| Writing to the U-Boot environment | A wrong value can stop the boot before anything else runs |
| Running u-boot commands with guessed arguments | On the first device, `sunxi_flash read` with a small size overran RAM and crashed. Memory addresses differ per build |
| `dd of=` anything on the device | Don't. The tools here only use `dd if=` |
| `fastboot erase` of anything but userdata | Some partitions can't be regenerated |
| `fastboot oem` or `flashing` commands from a forum post | They differ by vendor, and some wipe or lock |
| Assuming a failed command changed nothing | Check the state again before you retry |

## Rules for working with the device and the PC

- **Never write to the serial port from a tight loop.** A guarded loop reopened the port about 200 times per second and wedged the user's USB hub.
- **Never redirect to `/dev/ttyUSB0` as root without checking it exists.** If the adapter is unplugged, `>` creates a regular file there, and the serial port then stays broken. Safe form: `[ -c /dev/ttyUSB0 ] && ...`.
- **Don't chain USB mode changes over `adb`.** `setprop sys.usb.config none; ...` kills your own `adb` shell before the rest runs. Use a service on the device.
- **Be careful with broad `pkill -f` patterns.** They can match the shell running the command, and they can kill other work. Use exact PIDs or `pgrep -x`.
- **Tell the user before a reboot or flash.** They may be testing the device. Unexplained reboots look like a failure.
- **Read `tools/` scripts before running them on a new device.** They've only been run on one device, and a new one may differ. Fix what doesn't apply.
- **Don't handle the user's passwords.** Let them type credentials themselves. Don't capture screenshots during sign-in. `tools/75-triage.py` masks emails, and you should mask them in anything else you print.
- **Treat downloads as untrusted.** Keep them in their own directory, check hashes against the publisher's index, and check signing certificates. Don't bypass a site's protection against automated downloads: ask the user for the file instead.

## When to stop and ask the user

Stop, explain what you know, and let them decide, if:
- the user hasn't yet acknowledged that this could brick the device;
- a step might make the device unrecoverable;
- the backup check reports a STOP item and you'd need to proceed anyway;
- you're considering writing to anything on the never-flash list;
- the device isn't in the state you expected and you don't know why;
- you'd have to use a method you haven't verified on this device, and no tested way back exists;
- a safety system blocks a command. Explain what it does and why you want it. Don't look for a way around it.

Wiping userdata is fine on a test device once the user has told you so. Ask once, then don't ask again.

## Be honest about what you know

The first project had several wrong claims that wasted time, like "the kernel hangs" when it never started. Use these words:
- **verified**: you saw it happen on this device;
- **read from code**: the code or binary shows it, but you haven't seen it run;
- **inferred** or **likely**: it's an explanation you haven't tested;
- **general knowledge**: from outside this project, unverified here.

When you were wrong, say so plainly and correct the docs. Report tests that failed. A build that compiled and a service that accepted a call are not proof that the user's feature works: the user seeing it work is.
