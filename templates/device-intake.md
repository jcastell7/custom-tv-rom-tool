# Device intake: <CODENAME>

Fill in what you know, and leave the rest blank. "Don't know" is a fine answer: the agent can find most of it. Give this file to the agent.

## The device
- Brand and model:
- What it is (TV box, projector, stick, TV):
- Chip, if known:
- RAM and storage, if known:
- Is the stock ROM working right now? (yes / no / stuck)
- Do you have a second identical unit? (yes / no)

## Access
- Can you enable USB debugging? (yes / no / already on)
- Does `adb root` work? Is there root another way?
- Is the bootloader unlocked? (yes / no / don't know)
- Which USB port connects it to the PC? What kind of cable?
- Physical buttons, including hidden holes in ports:
- UART: wired? pads known? adapter voltage?
- If UART is wired, the log file the agent can read (example: `~/uart.log`):
- Is there an SD slot? USB-A port?

## Rules for this device
- Is the data on it disposable? May the agent wipe it without asking? (yes / ask each time)
- May the agent reboot it and flash it without asking each time? (yes / ask each time)
- Is it OK to risk this unit? (it's a spare / I need it working)
- Things the agent must never do:

## What you want
- ROM base (default: LineageOS matching the stock Android version):
- Android TV interface? (yes / no)
- Google Play? (no / yes, with sign-in optional / yes, required)
- Root? (no / yes, what for)

## Stock features that must keep working
Use the device on stock, and list everything you rely on. This list prevents the most rework.
- Display (keystone, four corners, zoom, picture modes):
- Video inputs (HDMI in, AV):
- Remote (IR, Bluetooth, keyboard, trackpad; any special button behaviour):
- Sensors (autofocus, tilt):
- Audio (speaker, HDMI, Bluetooth, optical):
- Network (Wi-Fi, Ethernet):
- Casting:
- Factory or settings apps:
- Power behaviour:
- Other:

## Apps to preinstall
Give the exact package name where you can. For paid apps, say where the license came from.
| App | Package name | Source | Notes |
|---|---|---|---|
|  |  |  |  |

## This computer
- LineageOS tree location, if one exists:
- Where backups should go:
- Second disk for a backup copy:

## Anything else
Forum links, earlier attempts, what's already been tried:
