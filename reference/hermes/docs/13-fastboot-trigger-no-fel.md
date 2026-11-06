# Reaching fastboot/recovery on the stuck unit — routes and their real status

**Branch:** `feat/fastboot-trigger-no-fel`

Every route into a flashing mode, separated into what has been observed and what is only assumed. Companion
to [`11-uart-serial-console.md`](11-uart-serial-console.md) (UART) and
[`14-power-key-boot-trigger.md`](14-power-key-boot-trigger.md) (power-button trigger).

## Corrections to the first version of this document
The first version contained claims that the evidence does not support. They are recorded here so they are
not picked up again:

| Earlier claim | What the evidence says |
|---|---|
| "No exposed FEL button" | **Wrong.** A recessed button in a port enters FEL; `lsusb` showed `1f3a:efe8` ([`07`](07-stock-backup-and-restore.md) Option C). FEL is reachable; we lack the files to use it. |
| The brick is a "hung kernel": `bootm` succeeds, then init hangs | **Wrong.** With boot0 debug mode (`d` on UART), u-boot logs past `Hit any key` and stops at `ramdisk use init boot`, with no `Starting kernel`. The stop is in u-boot. See [`12`](12-rom-boot-fixes.md). |
| `[102]key press :` is boot0 reading an ADC button | **Wrong, now confirmed.** Streaming `x` produced `key press : x`, so it reports a character read from **UART**. |
| Holding a physical button at power-on rescues the unit | **Not applicable.** The unit has only the power button and the recessed FEL button. No ADC buttons are known to exist, although the DTS describes an 8-key `keyadc0` ladder. |
| `env-fallback.img` cannot help this unit | **Unsupported**, because it relied on the hung-kernel claim. It would help if `bootm` returns. Whether it does is unknown. |
| `misc.img` being all zero "confirms" u-boot reads the BCB | **Unsupported.** Zeros show only that no boot command is set. |
| The HY300 "confirms" our mechanism | **Overstated.** It is a single unverified research note about a different SoC. Useful as a lead only. |

## Status of each route

| Route | Status | What is missing |
|---|---|---|
| **UART console** → `sunxi#` → `fastboot` | boot0 reads UART and honours `d`. u-boot ignored every stream and the blind `reset`, and with `d` it visibly carries on through autoboot | A way to make u-boot read input; none known |
| **ADC key input** (u-boot logs `key 0` during `update bootcmd`) | Untested. The env has fastboot window `0x2–0x8` and recovery window `0x10–0x13`, but no link to that line is proven | See "Testing the key value" below |
| **FEL** (recessed button) | Entry confirmed (`1f3a:efe8`) | Stock boot0/u-boot/fes1/partition layout, and tooling: sunxi-tools does not support SoC id `0x1911` |
| **Remote control keys at power-on** | Untested | Just a try. See below |
| **USB during boot** (`usb burn from boot`) | Log shows enumeration (`set address 0x4`) and a ~2 s handshake wait | Identify what the PC sees; the protocol is undocumented so far |
| **USB stick** (`sunxi update check`, `ULI/factory`) | Log shows the scan on every boot; stick never tried. **Best current lead** | See "USB stick test" below |
| **Direct eMMC wiring** | Untested; delicate soldering | External reader. Bypasses all software and needs no donor |
| **Donor unit** | Tooling ready (`tooling/donor-extract/`) | A donor. Supplies boot0/u-boot and a known-good boot log |
| **`adb reboot …` / BCB** | Needs a booted OS | A booting ROM |

### USB stick test
On every boot u-boot logs `sunxi update check`, scans USB for storage, prints `** Bad device usb 0 **` and
`skip update boot_param`, then `List file under ULI/factory`. The
[HY300 USB guide](https://github.com/YuujiLab/HY300-H713-Research/blob/main/Firmware/USB_BURN_GUIDE.md) describes
a stick that u-boot acts on at cold boot: FAT32 on MBR, a USB 2.0 stick, the rear USB-A port, and these files:

```
update/auto_update.txt     contains:  sunxi_flash write update/update.img firmware
                                      %
update/update.img
```

That guide is for a different SoC (H713), and its `auto_update_check` name does not appear in our logs, so **none of
this is confirmed here**. Whether `auto_update.txt` runs arbitrary commands is also unknown. Our dumps contain no
copy of u-boot to check. The guide also describes anti-rollback on `update.img`: same-or-older firmware is refused.

**Test 1 (cannot flash, as there is no image on the stick):** `update/auto_update.txt` containing `printenv` then
`%`, plus an empty `ULI/factory/` folder. Stream `d`, cold boot, and compare with a boot without the stick.
If `printenv` runs, the next test is `fastboot` then `%`. Never use an HY300 firmware image on this unit.

**Test 1 result: u-boot reads the stick and appears to run its commands.** Without a stick the log ends at
`ramdisk use init boot`. With it:

```
scanning usb for storage devices... 1 Storage Device(s) found
file_size:0x2a3038 temp_buf:fatsize usb 0  from:
** Unable to read file  **
## Error: "0x40007000" not defined
## Error: "0x2a3038" not defined
update_next_work=3
SUNXI_UPDATE_NEXT_ACTION_SHUTDOWN
```

Those `## Error` lines are what `printenv` prints for undefined variables, so the likely reading is that u-boot tried
to load a file named by the line (none here), then ran `printenv 0x40007000 0x2a3038`: the first word plus a load
address and size. The projector then shut down, and nothing appears to have been written. **The exact line format
is inferred.**

Because those arguments get appended, `setenv` and similar commands could store wrong values, so don't use them
here. `run boot_fastboot` should be safe, as `run` runs each name in turn and `fastboot` wouldn't return.

**Test 2 (still cannot flash):** `auto_update.txt` with `help sunxi_flash`, `help fastboot`, `help gpio`,
`printenv bootcmd`, `printenv slot_suffix`, `run boot_fastboot`, then `%`, one per line. **Never put `saveenv`,
`sunxi_flash write`, `mmc` or `env` lines in this file without a reviewed plan.**

**Test 2 result: u-boot entered fastboot from the stick.** The log ends with:

```
sunxi_fastboot_init
start to display fastbootlogo.bmp
usb init ok
sunxi_usb_fastboot_status=0
```

Also confirmed:
- Lines run in order, each becoming `<first word> <second word> 0x40007000 0x2a3038`.
- **`Unknown command 'gpio'`: this u-boot has no `gpio` command**, so the power-button env images can't work as built
  ([`14`](14-power-key-boot-trigger.md)).
- `sunxi_flash write <mem_addr> <part_name> [size]` exists; not yet used.

Whether the PC connects has not been confirmed yet.

### Rescue stick (the practical trigger)
A FAT32 stick on MBR with `update/auto_update.txt` containing `run boot_fastboot` then `%` enters fastboot before any
kernel or ROM loads. It needs no flashing or soldering, so it is independent of how broken the ROM is. Remove the stick
for a normal boot.

**Test 3 (memory only, nothing saved or flashed):** u-boot appends arguments to each line, which breaks commands like
`setenv`. Try ending the line first: `help;`, then `setenv<TAB>testtrig<TAB>hello;`, `printenv testtrig`, `printenv;`,
then `%`. The tabs survive the stick parser, which appears to split on spaces, and then act as normal separators in
u-boot's own parser.

**Test 3 result: it works, so the stick can run u-boot commands.** The log printed `testtrig=hello`, the full env and
the command list. Useful commands present: `mmc`, `part`, `gpt`, `fatload`, `fatwrite`, `fatls`, `md`, `mw`, `itest`,
`setexpr`, `source`, `usb`, `sunxi_flash`, `pst`, `ab_select`, `efex`, `sunxi_fel`, `boot`, `bootm`, `reset`, `poweroff`.
Absent: `gpio`, `test`. These commands run before the `update part info`, `update bootcmd` and `update dts` steps, so
booting from the stick may not match a normal boot. `saveenv`, `erase`, `mmc write` and `sunxi_flash write` can
change the unit: don't use them without a reviewed plan.

**Test 4 (reads only):** lists the partitions, checks whether `boot_b`, `init_boot_b` and `vendor_boot_b` hold images,
and tests hush with a harmless `if`. Addresses avoid the monitor and OP-TEE region at `0x48000000`.

**Test 4 results:**
- **GPT obtained:** `firmware/device-state/emmc-partition-map.txt`. The first partition starts at sector `0x12000`, so
  the area before it should hold the GPT and boot code.
- **No hush:** `Unknown command 'if'`, `'then'`, `'fi'`. The commands between them still ran, which confirms the
  power-button env images would fire on every boot. Stick lines can't use conditions, at least via `if`.
- `mmc list` printed `No MMC device available`, while `part list mmc 2` worked.
- **The log stopped** right after `partinfo: name boot_b` while running `sunxi_flash read 0x45000000 boot_b 0x1000`.
  Cause unknown: the address, the size argument, or that partition's contents.

**Test 5 (reads the eMMC, writes only to the stick):** `mmc dev 2`, then `mmc read` of the `_b` headers by sector into
`0x41000000` (the buffer fastboot itself uses), then a copy of sectors `0`–`0x11fff` to `emmchead.img` on the stick
with `fatwrite`. Expected markers, from memory of Allwinner layouts: `eGON.BT0` in boot0 at sector 16 (`0x10`) and
256 (`0x100`), and `sunxi-package` at sector 32800 (`0x8020`).

**Test 5 results:**
- **The `mmc` command can't reach the eMMC here.** `mmc dev 2` printed `No MMC device available`, the current device
  stayed at 0 (the absent SD slot), and every read failed with `mmc_init: -95`. So `emmchead.img` is **not** an eMMC
  dump. It is a dump of RAM from `0x41000000`.
- **`fatwrite` works:** `37748736 bytes written`, so data can be saved from u-boot to the stick.
- **That RAM dump contains the boot package.** First described as junk, which was wrong; the owner had kept the file.
  At RAM `0x42E00000` there is a `sunxi-package`, 4 items, `0x130000` bytes, and **its checksum matches**. Extracted to
  `firmware/boot-package/` (git-ignored): `u-boot.bin`, `monitor.bin`, `scp.bin`, `optee.bin`, the whole package
  `boot_package-from-ram.fex`, the raw dump, and `SHA256SUMS.txt`. This is the first copy of u-boot we have.
- boot0 was later copied over `adb`, and the eMMC package matches this RAM copy ([`15`](15-uboot-reverse-engineering.md)).

**What u-boot's own strings say about the stick:** `auto_update_v2` documents the format as
`sunxi_flash write <file path> <load partition>`, for example `sunxi_flash write update/boot.fex boot`. `#` starts a
comment and everything after `%` is ignored. So **writing a partition from the stick is a built-in feature**, not a trick.
Not yet tried. Also present: `update/FIRMWARE.bin`, `ULI/factory`, `sunxi_auto_update_gpadc_key_check`, and messages for
`[boot recovery] set misc`. `yellow`/`orange` verified-boot strings show it handles those states.

**Test 6 (reads only):** `fatls mmc 2:1` plus `sunxi_flash read` of `env_a` as a known-good baseline, then
`init_boot_b`, `vendor_boot_b` and `boot_b`, with `echo` markers. `boot_b` goes last because that form stopped in Test 4.

**Test 6 result:** `fatls mmc 2:1` printed `No partition table - mmc 2`. `sunxi_flash read 0x41000000 env_a 0x1000`
crashed (`prefetch abort`, registers full of disk data). u-boot's code shows why: sizes under `0x8000` underflow the
sector count and overrun RAM ([`15`](15-uboot-reverse-engineering.md)). Test 4's stop was probably the same bug.

**Test 7 (reads only):** the same reads with size `0x8000`.

**Test 7 result:** reads work. `env_a` starts `25 04 0d 25 ... BOOTMODE=standby`, the same as our backup, including its
CRC. **`init_boot_b`, `vendor_boot_b` and `boot_b` start with zeros, so slot `_b` looks empty and has no recovery to
boot.** (`exceed env_a scope` messages come from a memory-overlap tracker and did no harm.)

**Reaching `fastbootd`:** it lives in stock's `vendor_boot` recovery, slot `_a` holds our build without it, and slot `_b`
looks empty. It first looked as if that needed a write, but stock recovery can be booted from RAM off the stick:
`tooling/rescue-stick/make-stick.py ramboot MOUNT`, explained in [`15`](15-uboot-reverse-engineering.md). Untested.

**Test 8 (PC detection, writes nothing to the eMMC):** every stick log so far says
`do_burn_from_boot usb : no usb exist`, while the first capture with the PC cable attached reached `set address 0x4`. So
the PC cable may not have been connected or detected when fastboot started. The stick sets the RTC flag and resets:
`mw.l<TAB>0x07090118<TAB>0x5f;` then `reset;`. Remove the stick when `HELLO! BOOT0` reappears, with the PC cable connected,
so that fastboot starts through the normal path, without the stick being used as a USB host.

**Test 8 result: failed.** It rebooted, then stopped at `ramdisk use init boot`, so fastboot wasn't selected. The cause
isn't known yet: the flag may not survive the reset, or may be consumed earlier in the boot.

**Test 9 (writes nothing to the eMMC):** `usb<TAB>stop;` then `run boot_fastboot`, to release the USB host before fastboot
starts.

**Stick restore (WRITES to the eMMC):** `tooling/rescue-stick/make-stick.py restore MOUNT` copies the stock `_a` boot
chain to the stick after checking it, then each line writes one partition and reads it back with `crc32`. It doesn't
touch boot0, u-boot, env, misc, GPT, `super` or userdata. `make-stick.py check LOG` compares the CRCs.
u-boot's format string is `%s %s 0x%lx %s 0x%x`, so `sunxi_flash write update/x.img part` becomes
`sunxi_flash write 0x40007000 part 0x<size>`. Files must stay under about 127 MiB, because the monitor is at
`0x48000000`. `super` (2.56 GB) therefore needs another route: fastbootd from recovery, or chunks loaded by hand.

**The two screens:** the robot on its back is u-boot's fastboot. The log prints `start to display fastbootlogo.bmp`,
and `fastbootlogo.bmp` extracted from `bootloader_a.img` is that robot image.
The black screen with options is the menu in Android recovery, which lives in `vendor_boot`, so our build's `_a` slot
doesn't have it. On the first try the projector showed the robot, but the PC saw no USB device at all, so USB
connection was still unsolved at this point.

### Testing the key value
Debug mode prints `[05.119]key 0` followed by `misc partition found`, just before `update bootcmd`. That may be the
value compared with the env's fastboot and recovery windows. To test it, stream `d` and watch that line:
1. Hold the power button through the whole boot. **Result: still `key 0`, same stop** (assuming the button was held
   for the capture received). Not the route.
2. Look for a keypad connector or pad on the board, as the DTS describes an ADC key ladder (`keyadc0`).
   Connect a candidate to ground through a resistor, starting with a high value. **Only ever pull toward ground: never
   apply voltage**, as the ADC input may be limited to about 1.8 V.

Debug mode also shows `secure enable bit: 0` and `non secure`, so secure boot appears to be off.

### Remote-control keys
Debug mode prints **`ir boot recovery not used`**, so u-boot has an IR recovery feature that is switched off on this
unit. A remote key is therefore unlikely to work. The owner reports the remote's volume keys navigate the
fastboot/recovery menus. A [research note on the HY300](https://github.com/YuujiLab/HY300-H713-Research/blob/main/Boot/BOOT_MODES.md)
says its u-boot polls IR early, with Vol+ entering FEL and Home entering recovery. To rule it out, hold one remote
key through a boot with `d` streaming and compare the log.

**Caution:** the same note says Home on the HY300 also triggers a **factory data wipe**. Assume that could happen
here too.

## The env partition

`firmware/partitions/env_a.img` is a real u-boot environment, and `uboot_env.py` reproduces it byte for byte:
partition `0x40000`, env block `0x20000`, non-redundant, little-endian CRC32 over `bytes[4:0x20000]` (stock
`0x250d0425`). The upper 128 KiB is preserved verbatim.

**Editing env is powerful but it is not yet known to work:**
- It contains these variables: `bootcmd`, `boot_fastboot`, `fastboot_key_value_min/max`,
  `recovery_key_value_min/max`. What reads the `*_key_value_*` windows, and on what scale, is unknown.
- The log line `[06.539]update bootcmd` suggests u-boot **rewrites `bootcmd` at boot**. From memory of public
  Allwinner u-boot source it substitutes strings and can replace the whole command depending on boot mode.
  A custom `bootcmd` may therefore not survive unchanged.
- Which partition is read (`env`, `env_a`, or a slot-dependent choice) is unconfirmed. Check `fastboot getvar all`
  for the name before flashing.
- This is a deliberate exception to the "never flash `env`" rule in [`10`](10-flashing-the-build.md). A bad env
  can leave u-boot on defaults or stop it booting, and writing it again needs a flashing mode. Do it only after
  the checks in `tooling/env-fastboot-trigger/uboot-powerkey-test.cmds` have passed on this u-boot.

### Generated images
All are CRC-valid. **None has been tested on hardware.**

| Image | `bootcmd` behaviour | Works without hush? |
|---|---|---|
| `env-fallback.img` | Stock boot, then fastboot if `bootm` returns | Yes |
| `env-force-fastboot.img` | Fastboot on every boot; reflash env to leave | Yes |
| `env-powerkey-fastboot.img` | PL4 held → fastboot, else normal ([`14`](14-power-key-boot-trigger.md)) | **No: fastboot on every boot** |
| `env-powerkey-recovery.img` | PL4 held → recovery, else normal ([`14`](14-power-key-boot-trigger.md)) | **No: recovery on every boot** |
| `env-widen-key.img` | Widens the key window | Do not use: it rests on the unverified ADC assumption |

Generate with `tooling/env-fastboot-trigger/build-trigger-env.py`, output in `tooling/env-fastboot-trigger/out/`.

## After a ROM boots
`adb reboot bootloader` should reach u-boot fastboot. `adb reboot fastboot` needs `fastbootd`, which **our build
does not currently contain** (see [`12`](12-rom-boot-fixes.md)). Neither has been tested on our build.

## Tooling (`tooling/env-fastboot-trigger/`)
| File | Purpose | Status |
|---|---|---|
| `uboot_env.py` | Decode/encode env; `verify` proves the round trip | Verified on the stock image |
| `build-trigger-env.py` | Generates the images above | Output CRC-checked; behaviour untested |
| `uboot-powerkey-test.cmds` | Checks to run at `sunxi#` before flashing any power-key env | Not yet run |
| `find-fastboot-key.py` | Reads `key press :` as a button value | **Do not use**: based on the ADC assumption above |

## Result: stock recovery and fastbootd booted from the USB stick, with no eMMC write
`make-stick.py ramboot` (explained in [`15`](15-uboot-reverse-engineering.md)) booted stock recovery from RAM on a unit whose flash is
still unbootable. Choosing fastboot in the menu reached **fastbootd, and the PC detected it** (`18d1:4ee0`, `is-userspace: yes`,
`unlocked: yes`, `current-slot: a`, `max-download-size: 0x10000000`).

**This is the practical rescue path for any future broken ROM**, as long as u-boot is intact: stick in, power on, recovery menu, fastbootd.
Addresses in the script are specific to this u-boot build (`Relocation Offset is: 2c909000`). A different u-boot needs them recomputed.

**Stock restore over fastbootd:** `tooling/rescue-stick/restore-stock-fastbootd.sh` does a dry run by default and writes only with
`--commit`. It flashes `vendor_boot_a` first, so recovery stops depending on the stick.

**Root access in the RAM-booted recovery:** the UART has a root shell. At that `#` prompt, `setprop sys.usb.config none` then
`setprop sys.usb.config adb` switches USB to adb, and `adb root` works. `fastboot` in place of `adb` returns to fastbootd.
`tooling/rescue-stick/copy-partitions-adb.sh` copied boot0, the u-boot package, both GPTs and the missing partitions.

**First flash of the fixed build:** `tooling/rescue-stick/flash-lineage-fastbootd.sh` wrote all images, including `super`, with no errors.
`userdata` was then formatted at the owner's request, as it held nothing of value and could interfere with a first boot of a different ROM.
fastbootd reports it as `raw`, so plain `fastboot format userdata` refuses; `fastboot format:ext4 userdata` is the form to use. `metadata` was not touched.
