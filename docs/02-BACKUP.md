# Backing up a device

> **⚠️ WARNING: this process could very well fully and permanently brick your device.** Only use it on a device you own and can afford to lose. It's provided as is, with no warranty, and **we accept no responsibility** for how it's used or what happens. Not affiliated with LineageOS in any way: we just use and recommend their work, so [please donate to them](https://lineageos.org/about/) when you can. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

## What a complete backup contains

| What | Why | How |
|---|---|---|
| Every named partition | Restores the OS | `tools/20-backup.sh` |
| Disk head, before the first partition | The bootloader and GPT often live here, outside any partition | Same |
| Disk tail, last 16 MiB | Backup GPT | Same |
| eMMC hardware boot areas (`mmcblkXboot0/1`) | Many SoCs boot from these | Same, if present |
| Layout: partition start and size, `getprop`, cmdline, bootconfig, `dmesg` | Needed to rebuild images and to compare later | Same, in `layout/` |
| A stock boot log over UART, if wired | The most useful comparison when a custom build fails later | Capture it before you change anything |
| Stock `/vendor` and `/system` as files | Blobs and stock apps | `tools/30-extract-stock.sh` |
| `userdata` | Only if the user wants it | `--include-userdata` |

**Can't be backed up this way:** RPMB (a protected eMMC area, which can hold keys and rollback counters) and fuses. Tools here never write them. If DRM stops working later, this is one possible reason.

## Steps

```bash
tools/10-preflight.sh report/
tools/20-backup.sh backup/
tools/21-check-backup.py backup/
```

Then copy `backup/` to a second disk, and keep it private: it contains MAC addresses, serial numbers and possibly keys.

`20-backup.sh` hashes each partition on the device, copies it, hashes the copy, and retries once if they differ. Re-running it skips what's already verified, so an interrupted run just continues.

## Reading the check's output

`21-check-backup.py` prints what it found in the boot chain. On the first device, the correct result looked like this:

```
bootloader_a        32.0 MiB  no real bootloader (logos)
disk-mmcblk0-head   64.0 MiB  Allwinner boot0 (SPL), Allwinner u-boot package, GPT header
boot_b: first MiB is all zero, so this slot is NOT a usable fallback
```

Check these yourself:
1. **Can you point to the bootloader?** If you see no signature, find it before you continue. Search the disk head for strings such as `U-Boot`, `eGON`, `RKNS`, `@AML`, `sunxi-package`.
2. **Is slot `_b` real?** If it's zeros, you have no second slot to fall back to, whatever the partition table says.
3. **Did `super` get copied?** It's big, but the OS can't be restored without it.
4. **Is the bootloader unlocked?** Check `ro.boot.flash.locked` and `ro.boot.verifiedbootstate` in `layout/getprop.txt`.

## If you don't have root

`adb root` only works on userdebug and eng builds, and `su` needs an existing root solution. Your options, safest first:

1. **A root recovery from the device itself.** Some stock recoveries allow `adb root`. On the first device, stock recovery did.
2. **`fastboot fetch`**, on devices with a recent fastbootd or bootloader. Check `fastboot getvar all` for support.
3. **The SoC's own tool** (see `03-RECOVERY-ROUTES.md`), which may read flash directly. This is general knowledge and varies by chip: verify it before relying on it.
4. **A vendor update file** for the same model and revision, as a substitute.

**Don't unlock a bootloader just to take a backup without warning the user.** Unlocking usually wipes userdata, and on some devices it can't be undone.

## If the storage isn't eMMC

`20-backup.sh` handles `mmcblkN`, `sdX` (UFS) and `nvmeXnY`. For raw NAND (`/dev/mtd*`, or a vendor's block layer such as `nand*` or `rknand*`), it warns and copies named partitions only. Check `/proc/partitions` and `/proc/mtd`, and plan the copy by hand. Raw NAND dumps can't always be written back as plain bytes, because of bad blocks and ECC.

## Restoring

Don't improvise this. Build a dry-run script for the specific device first, and show it to the user. `reference/hermes/rescue-stick/restore-stock-fastbootd.sh` is an example. It:
- flashes the OS partitions and leaves out bootloader, env, misc and frp;
- checks hashes before writing;
- doesn't wipe or reboot by itself.

**Metadata needs care:** on the first device, `metadata` changed after the original backup. It can hold the encryption metadata for `userdata`, so restoring an old copy without wiping `userdata` can lose access to it.
