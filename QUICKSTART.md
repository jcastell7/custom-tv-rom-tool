# Quick start

For the person running this. Full guide: [`docs/11-HOW-TO-USE.md`](docs/11-HOW-TO-USE.md).

**You need:** a Linux PC, the device with USB debugging on, and a USB data cable. For building, also about 350 GB free on a local ext4 SSD. Plan on about 2–4 days overall, much of it unattended.

**Know what you're getting:** the ROM is LineageOS on top of the device's **closed-source** stock binaries: bootloader, drivers, GPU libraries and usually the kernel. These can't be inspected or fixed, get no security updates from LineageOS, and may not be legal to redistribute. A LineageOS or other open kernel is used when one fits. See [`docs/12-KERNEL-AND-CLOSED-SOURCE.md`](docs/12-KERNEL-AND-CLOSED-SOURCE.md).

## 1. Check the computer (2 minutes)
```bash
cd /path/to/custom-tv-rom-tool
tools/00-check-host.sh --purpose device
```
If you'll build here too, use `--tree /path/to/lineage-21.0` instead of `--purpose device`.

## 2. Create the device's workspace (5–15 minutes)
```bash
tools/01-new-device.sh mybox
```
Fill in `devices/mybox/INTAKE.md`. **The feature list matters most:** use the device on stock and write down everything you rely on. Leave unknowns blank.

## 3. Start an agent in this folder, and paste this
```
Use this toolkit to build a custom Android TV ROM for my device, codename mybox.
Read CLAUDE.md, README.md and docs/00-SAFETY.md, then devices/mybox/INTAKE.md.

Start with read-only steps only: check the computer, run preflight, and take a verified full backup.
Then show me what you found, your recovery plan, which kernel you recommend and why (docs/12), what will stay closed source, and any questions.
Don't flash anything until I've approved the plan.
Keep devices/mybox/PROGRESS.md up to date.
```

## 4. Stay available for what only you can do
- Approve the recovery plan before the first flash.
- Run `sudo` commands.
- Press buttons and plug things in.
- Run the serial log, if UART is wired: `picocom -b 115200 --logfile ~/uart.log /dev/ttyUSB0`
- Tell the agent what's actually on screen.
- Test features, and type your own passwords.

## 5. Continuing later
In a new session:
```
Continue the ROM for device mybox. Read CLAUDE.md, then devices/mybox/PROGRESS.md and NOTES.md, and carry on from there.
```

## In an emergency
**Device stuck:**
```
My device mybox won't boot. Read docs/09-BRICK-RECOVERY.md and devices/mybox/. Don't write anything to the device yet.
Here's what I see: <screen, lights, what happened just before>
```

**Build failing:** `Read docs/08-BUILD-ERRORS.md and fix this build error: <paste the first error>`

## The rules that prevent bricks
1. No flashing before a verified backup, with a second copy.
2. No flashing before two proven ways back.
3. Never flash bootloader, partition table, or per-device partitions.
4. Run the gate before every flash.
