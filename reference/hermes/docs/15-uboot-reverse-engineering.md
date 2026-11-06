# u-boot reverse engineering notes

Findings from `firmware/boot-package/u-boot.bin` (U-Boot 2018.07, Feb 25 2026), recovered from RAM with a matching
package checksum (see [`13`](13-fastboot-trigger-no-fel.md)). Thumb-2 code, linked at `0x4a000000` (the literal pools
resolve correctly at that base). Addresses below are that static view; the running copy is relocated.
Method: capstone disassembly, following references to known log strings.

"Read from code" means the instructions show it. "Inferred" means it is an explanation that hasn't been tested.

## Why the old build stops at `ramdisk use init boot`
`android_image_get_ramdisk` at `0x4a019fd4`:

1. Reads `kernel_size` (`+0x08`), `+0x10` and `+0x24` from the **boot** image header.
2. If an `init_boot` partition exists, prints `ramdisk use init boot` and loads that image's header.
3. Checks the `init_boot` magic and `header_version` (`+0x28`):
   - **Above 2 (v3/v4):** takes `ramdisk_size` from `init_boot +0x0c`, and the ramdisk starts one 4 KiB page in.
   - **0–2:** skips those steps and keeps the values already read from the **boot** header.

Our `boot.img` is v4, where `+0x10` is `os_version` (`0x1c0001aa`) and `+0x24` is 0. So with a v0 `init_boot`, the
"ramdisk size" becomes about **448 MiB**. The caller at `0x4a00a264` then copies it to just after the vendor ramdisk,
which starts at `0x43300000`. A 448 MiB copy runs through the monitor and OP-TEE at `0x48000000`.

- **Read from code:** the branch and the wrong size.
- **Inferred:** that this copy is what stops the boot. The capture shows no abort message, unlike the crash below.
- **Superseded:** the earlier explanation in this project of "256 MiB, read from offset 12" was wrong about the field.
- **Fixed build:** `init_boot` v4 takes the correct branch with `0x258f1c` (2.3 MiB).

Header comparison, stock vs fixed build: same `kernel_addr` `0x40008000`, `ramdisk_addr` `0x43300000`, `dtb_addr`
`0x43200000`, tags `0x40000100`, DTB size `0x850`, page size, and v4 headers. Vendor ramdisk size differs (`0x10c4066` vs
`0x26bf9`), because ours has no recovery.

### The vendor_boot name field selects the kernel's CPU mode
`0x4a00a358` checks the name at `vendor_boot +0x820`. If it contains `arm` but not `arm64`, u-boot prints
`force run 32bit os on this device` and sets a flag (`gd +0x174`). In the kernel jump at `0x4a001538`, when a boot-header byte says
so (`0x4a002b34`) and that flag is clear, it issues SMC `0x8000ff04`, which appears to switch to AArch64 before entering the kernel.
Stock has `arm`. Our build left it empty, so the 32-bit kernel could have failed right at `Starting kernel`. **Fixed as FIX 5, `--board arm`.**
The header byte's runtime value isn't known, so whether this would have failed is unproven.

## How u-boot chooses a boot mode
`0x4a003738`, which logs `key %d`, sets `force_normal_boot=1` and then checks three sources:

1. **Key value:** a 16-bit field at `0x4a000504` (`key %d`), compared with device-tree nodes `/soc/recovery_key`,
   `/soc/fastboot_key`, `/soc/fel_key` (`key_min`, `key_max`). So this code uses the device tree, not the env's
   `*_key_value_*` variables.
2. **RTC flag:** the register at `0x07090118`, read and then cleared (`0x4a0021cc`, `0x4a0021a8`).
3. **misc:** `0x4a00328c` reads `misc` and compares strings including `efex`, `sysrecovery`, `recovery`, `bootloader`
   and `uboot`.

| Mode value | Result |
|---|---|
| `0x5a` | FEL |
| `0x5c` | Recovery: `force_normal_boot=0`, and `boot_recovery` only if a `recovery` partition exists |
| `0x5d` | `run sysrecovery` |
| `0x5f` | Replaces `boot_normal` with `boot_fastboot` in `bootcmd` |
| `0x60` | Calls `0x4a002cf4` with 1 (not traced) |

**Possible use (untested):** writing the RTC flag from the stick, `mw.l 0x07090118 0x5f`, then `reset`, should select the
mode on the next boot without writing to flash. The stick must be out before the next scan, or the script runs again.

Recovery uses `force_normal_boot=0` on the slot's normal images, so the recovery must be in `vendor_boot`.

## `sunxi_flash read` with a size crashes on small sizes
Handler at `0x4a00ffa8`. It always reads the first `0x40` sectors (32 KiB), then computes the rest as:

```
remaining_sectors = ((size + 0x1ff) >> 9) - 0x40
```

With `size` `0x1000` that is `8 - 0x40`, which **underflows to a huge count**. The read then overruns RAM from the
destination upward, including the stack. That matches Test 6: 3.5 s of reading, then `prefetch abort` with registers full
of disk data. **Use a size of at least `0x8000`.** The crash only overwrote RAM; this path issues reads.

## Stick script format
The help text for `auto_update_v2`: `sunxi_flash write <file path> <load partition>`, `#` starts a comment, and everything
after `%` is ignored. Observed handling: each line runs `fatsize` on the file, then a command built from the first two
words plus `0x40007000` and the size. Tabs and `;` allow any command to be run; see [`13`](13-fastboot-trigger-no-fel.md).

## Booting stock recovery from RAM, without writing the eMMC
`init_boot` and `vendor_boot` are each read from flash in exactly one place, and the result is cached:

| Function | Cache flag | Cached pointer | Live address (flag / pointer) |
|---|---|---|---|
| `init_boot` loader `0x4a019f64` | `0x4a0abb74` | `0x4a0abfac` | `0x769b4b74` / `0x769b4fac` |
| `vendor_boot` loader `0x4a0196e8` | `0x4a0abb78` | `0x4a0abfb0` | `0x769b4b78` / `0x769b4fb0` |

If the flag is set, the loader returns the pointer and doesn't touch flash. So the stick can load stock images into
RAM and set those values. Live addresses add the logged `Relocation Offset is: 2c909000`, the same in every capture.

The other two pieces:
- **Normal boot continues after the script.** At `0x4a065932`, a non-zero `0x4a0e6cf0` (live `0x769efcf0`) takes the same
  exit as "no `auto_update.txt`", instead of the shutdown. The rest of u-boot's setup still runs.
- **Recovery is selected in the same boot.** `mw.l 0x07090118 0x5c` is read a little later by `0x4a003738`, which sets
  `force_normal_boot=0`. Test 8 tried this across a `reset`, and that failed; this doesn't reset.

AVB checks run in `0x4a008ac8` **before** the ramdisk step, on the eMMC contents, and passed in every capture. `boot_a` is
read from eMMC as normal; its kernel is the same size as stock (`0x2375ba0`), which is expected since we reuse that kernel.

Images load at `0x50000000` and `0x52000000`, because `0x4a003738` reads a field at `0x4a000504`, and the usual
`0x49000000` buffer would overwrite that once a 32 MiB file is loaded. Each stick line also clears 8 MiB at `0x40007000`.

**Works: it booted stock recovery and fastbootd** (see below and `13`). `tooling/rescue-stick/make-stick.py ramboot MOUNT` generates it. Its only writes are to RAM and one RTC
register. u-boot's normal boot also rewrites secure-storage HDCP entries, as every capture shows, with or without this.
A booted stock recovery could also write to the eMMC by itself, for example logs, and its menu has destructive options.

### First RAM boot attempt
**Result: the projector powered off during the first `fatload`** (`vendor_boot_a.img`, 32 MiB to `0x50000000`), with no
abort or further output. Its two `md.l` lines printed zeros, which confirms the computed live addresses look right. The
cause isn't known. The updater's own loader reads files in 8 MiB chunks with pauses (`0x4a065a6a`), unlike a plain `fatload`.

**Test 10 (RAM only, ends in the usual shutdown):** an 8 MiB `fatload` to `0x41000000`, then to `0x50000000`, then the updater's
own loader for the 32 MiB file. A line `echo x;cp.b update/vendor_boot_a.img 0x50000000` becomes
`echo x;cp.b 0x40007000 0x50000000 0x2000000` after loading the file in chunks. Expected CRCs: `706fc7b2` and `0d329a6b`.

**Test 10 result: an 8 MiB `fatload` to `0x41000000` worked (20.9 MiB/s), but the next lines' commands didn't run**, and the run
ended in the usual shutdown. Cause, read from the parser at `0x4a065a0a`: `filesize` is read from the env, and `fatload` had set it
to `0x800000`. Above `0x7fffff`, the chunked path at `0x4a065a6a` runs instead, and when the remainder reaches exactly 0 it
moves to the next line **without running the command**. So:
- After a large `fatload`, reset it on the same line: `fatload ...;setenv filesize 0;`.
- **The documented `sunxi_flash write <file> <part>` form silently skips any file that is an exact multiple of 8 MiB**, including
  `boot_a`, `init_boot_a` and `vendor_boot_a`. `make-stick.py` now loads and writes these explicitly.
- The 32 MiB file also went through the chunked read without a crash, though nothing used the data.

**Test 11 (RAM only):** 8 MiB to `0x50000000`, 32 MiB to `0x41000000`, 32 MiB to `0x50000000`, with CRCs and short file names.

**Test 11 result: all loads worked and every CRC matched:** 8 MiB to `0x50000000` (`706fc7b2`), 32 MiB to `0x41000000` and to
`0x50000000` (both `0d329a6b`), at about 25 MiB/s, ending in the usual shutdown. So neither the address nor the size explains the
power-off in the first RAM boot attempt, which remains unexplained. The next step is `make-stick.py ramboot` with the parser fix.

**RAM boot result: it worked.** With the parser fix, the projector booted stock recovery and fastbootd with no eMMC write from the stick.
The unexplained power-off happened once, on the first attempt, and did not recur.

## Verified from the eMMC over adb
With the root recovery running from RAM, `tooling/rescue-stick/copy-partitions-adb.sh` copied the eMMC to `firmware/partition-copies/`
(git-ignored, may hold per-device data). Each copy was checked against a SHA-256 computed on the device.

- **boot0 found and intact:** `eGON.BT0` at sectors `0x10` and `0x100`, length `0xf000`, identical, stored checksum `0x628e7b8c` matches.
- **u-boot package found:** `sunxi-package` at sectors `0x6000` and `0x8020`, both byte-identical to the copy recovered from RAM.
- **Old `init_boot_a` confirmed as header v0**, with `0x10008000` at `+0x0c`, as inferred from the rebuilt image.
- **Slot `_b` is fully zero:** all pages of `boot_b`, `init_boot_b`, `vendor_boot_b`, `dtbo_b`, `vbmeta_b`, `env_b` and `bootloader_b`.
- `bootloader_a`, `env_a`, `misc` and `frp` match the original backup. `metadata` differs, so it must not be overwritten from the old backup without
  checking, because it can hold encryption metadata for `userdata`.
- `private` and `empty` are all zero. `Reserve0_a` and `media_data` start with FAT boot sectors; `customapp` and `treadahead` hold some data.
- Not copied: `super` (the stock copy is in `firmware/partitions/`) and `userdata`.

Other details: the running recovery is `userdebug`, SELinux permissive, with a root shell on the UART and `adb root` available.

## First kernel boot from our images
With FIX 1 and FIX 5, the unit passed `ramdisk use init boot`, printed `force run 32bit os on this device` and `Starting kernel ...`, and the
kernel booted to first-stage init. That supports the `init_boot` diagnosis. It then failed on the duplicate bootconfig keys (FIX 6, `12`).

Also seen: `reboot: Restarting system with command 'bootloader'` stored `0x5f` in the RTC, and the next boot printed `bootmode[2]:0x5f` and
entered u-boot fastboot. So the RTC mechanism works across a kernel reboot, unlike the stick's `reset` in Test 8. The PC did not see that
u-boot fastboot, so the stick and fastbootd stay the way to flash.
