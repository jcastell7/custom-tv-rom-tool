# Donor-projector full extraction

Scripts to pull **everything** off an identical, working "donor" projector so we can recover the bricked
unit — specifically the pieces our original backup was missing (**boot0, u-boot, the GPT/partition
layout**) plus a complete reference set (all partitions, the live DTB, kernel cmdline, dmesg, props).

**Everything here is READ-ONLY on the donor.** Every device operation is `dd`/`cat`/`getprop`. Nothing is
written or flashed to the donor — it stays a working unit.

## Why we need it

Our dump of the bricked unit lacks boot0, u-boot and `sys_partition`/GPT (what we thought was the
bootloader turned out to be the logo partition). Those can't be downloaded for this SoC. A working twin
can be fully dumped over `adb root` + `dd`, giving us the ingredients to pack a PhoenixSuit-flashable
image and a healthy boot log to diff against the bricked unit's UART output. See
[`../../docs/07-stock-backup-and-restore.md`](../../docs/07-stock-backup-and-restore.md) "Option D".

## Prerequisites

1. **Same model AND hardware revision** as the bricked unit (boot0/u-boot/dtb/DRAM params are board-matched).
2. On the donor: **Settings → (About → tap Build 7×) → Developer options → enable USB debugging**, connect
   it to this PC by USB, and **authorize** the RSA prompt.
3. Host tools: `adb` (platform-tools) and `sha256sum`. Optional but nice: `dtc` (decompile DTB), `file`.
   - If `adb` isn't on PATH: `export ADB=/path/to/adb` or pass `--adb /path/to/adb`.
4. Free disk space for the dump (super alone can be a few GB; userdata is skipped by default).

## Run it

```bash
cd tooling/donor-extract
chmod +x *.sh                 # first time only
./run-all.sh                  # full read-only extraction -> ../../firmware/donor-dump/
```

Useful flags (any phase or run-all accepts them):

| flag | effect |
|---|---|
| `--out DIR` | output directory (default `firmware/donor-dump/`) |
| `--serial S` | pick a specific adb device |
| `--adb PATH` | use a specific adb binary |
| `--include-userdata` | also dump `userdata` (huge + personal; off by default) |
| `--yes`, `-y` | don't prompt before the big dumps |

Phases are **idempotent and resumable** — a completed, checksum-verified dump is skipped on re-run, so if
a transfer is interrupted just run again.

## Run phases individually

```bash
./01-prereqs.sh            # check host+donor, print identity, probe root
./02-metadata.sh           # layout, cmdline, DTB, props, dmesg, kernel config
./03-partitions.sh         # dump every named GPT partition (skips userdata)
./04-bootloader-region.sh  # raw boot0 / u-boot / GPT (the pieces we lacked)
./05-verify.sh             # checksum manifest + REPORT.md + diff vs our backup
```

## Output

```
firmware/donor-dump/
  partitions/            <name>.img + <name>.img.sha256   (boot, super, vbmeta*, dtbo, …)
  bootloader-region/     mmcblk0boot0/1.img, mmcblk0-first-64MiB.img, mmcblk0-last-16MiB.img
  metadata/              by-name.txt, proc-partitions.txt, cmdline.txt, getprop.txt,
                         fdt.dtb (+ fdt.dts), dmesg.txt, config(.gz), identity.txt, …
  MANIFEST.sha256        checksums of everything
  REPORT.md              human summary + what's NEW vs our old backup
  extract.log            full run log
```

Keep the whole `firmware/donor-dump/` folder; `REPORT.md` + `metadata/` are the high-value bits for the
build session.

## If `adb root` fails

Many stock Android-TV "user" builds block `adb root`, and block-level dumps need root. Options, best first:

1. **`su` present?** The scripts auto-try `su -c` / `su 0` — if the donor is rooted, dumps just work.
2. **Enrol the donor into our workflow temporarily:** if the donor's bootloader is unlocked, you can boot
   (not flash) a rooted/userdebug boot image via `fastboot boot <img>` to get `adb root` for the dump,
   leaving the donor's storage untouched. (Ask me to prepare that image.)
3. **No root at all:** phases 01/02/05 still capture all world-readable metadata (props, cmdline, DTB,
   partition map), but 03/04 (the actual blobs) can't run. In that case the donor must instead be dumped
   from its own recovery/FEL — tell me and we'll plan that route.

## Safety notes

- Read-only on the donor; no `fastboot flash`, no writes. The donor remains fully functional.
- `userdata` is **skipped by default** (personal data + size). Add `--include-userdata` only if you
  specifically want it.
- `env`, `frp`, `misc` and secure-storage keys are **per-device** — when we later flash the bricked unit
  we reuse *its* own copies of these, not the donor's (see Option D caveats).
