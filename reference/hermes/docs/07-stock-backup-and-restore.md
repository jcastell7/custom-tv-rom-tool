# Stock firmware backup & restore (Allwinner H723 "hermes" projector)

A complete block-level backup of the **active slot (`_a`)** so the device can be returned to
stock. Bootloader is unlocked (`verifiedbootstate=orange`), so flashing is permitted.

## Verifying the bootloader is unlocked
This device was captured **already unlocked** — no unlock step is needed before flashing. Evidence
from the dump (`firmware/device-state/getprop.txt`):

| Property | Value | Meaning |
|---|---|---|
| `ro.boot.flash.locked` | `0` | flashing is **not** locked |
| `ro.boot.verifiedbootstate` | `orange` | bootloader **unlocked**, custom images allowed |
| `ro.oem_unlock_supported` | `1` | unlock is supported by this u-boot |

> Note: `ro.boot.vbmeta.device_state` reads `locked`. That only means the *vbmeta it booted* is the
> stock-signed one; it does **not** re-lock flashing. The authoritative signals are `flash.locked=0`
> + `verifiedbootstate=orange`. This changes to your own key / disabled verification once the
> LineageOS `vbmeta` is flashed.

**Re-check it yourself on the device** (booted into Android, adb):
```
adb shell getprop ro.boot.verifiedbootstate   # expect: orange
adb shell getprop ro.boot.flash.locked        # expect: 0
```
Or from the bootloader (USB cable required — fastboot is USB-only):
```
adb reboot fastboot
fastboot getvar unlocked                      # expect: unlocked: yes
fastboot oem device-info                      # if u-boot supports it; prints lock state
```
An unlocked device also shows an **orange "device is unlocked / can't be trusted"** warning at
power-on.

### If a device ever comes back LOCKED (not the case here)
1. Android → enable **Developer options** → turn on **OEM unlocking** (sets `sys.oem_unlock_allowed=1`;
   it reads `0` in the dump only because the toggle was off at capture time).
2. `adb reboot fastboot`
3. `fastboot flashing unlock` (older u-boot: `fastboot oem unlock`) → confirm the prompt **on the
   device**. This **wipes userdata**.

**Allwinner caveat:** many Allwinner u-boots don't implement `fastboot flashing unlock` at all. If a
locked unit refuses to unlock over fastboot, use the SoC's **FEL mode** (USB boot-ROM recovery) via
`sunxi-fel` or **PhoenixSuit/PhoenixCard** — both talk to the chip's boot ROM and bypass u-boot's lock
entirely. This unit has a confirmed **recessed FEL button hidden in a port** — see Option C for the
exact procedure.

## The backup
Raw partition images live in [`../firmware/partitions/`](../firmware/partitions) (that directory
**is** the backup store). Checksums: [`../firmware/backup/SHA256SUMS.txt`](../firmware/backup/SHA256SUMS.txt).

Captured (slot `_a` + shared): `bootloader_a`, `boot_a`, `init_boot_a`, `vendor_boot_a`,
`dtbo_a`, `vbmeta_a`, `vbmeta_system_a`, `vbmeta_vendor_a`, `super` (2.56 GB; holds
system/system_ext/product/vendor/*_dlkm), plus `env_a`, `misc`, `frp`, `metadata`.

> **`bootloader_a.img` is the boot-*resource* partition, NOT boot0/u-boot.** Its FAT16 contents are the
> logos/fonts (`bootlogo.bmp`, `fastbootlogo.bmp`, `*_warning.bmp`, `font*.sft`, `LogoRegData.bin`,
> `magic.bin`, `bat/`). The real bootloader — **boot0 (SPL), u-boot, `sys_partition.fex`, the GPT,
> `fes1.fex`** — lives in a raw region at the start of eMMC that this backup does **not** contain. Two
> consequences: (1) we cannot hand-build a complete Allwinner LiveSuit/PhoenixSuit `.img` from this dump;
> (2) do not "restore the bootloader via FEL" from `bootloader_a.img` — it isn't one. To obtain the
> missing blobs you must dump them from a live/fastboot device first.

**Not** captured (by design): `userdata` (personal data) and the inactive `_b` slot. A stock
restore therefore rewrites the OS and leaves user data to a normal factory-reset.

## Option A — flash through the bootloader (fastboot)  ← recommended, "bootloader-flashable"
This device's u-boot has fastboot (`env`: `boot_fastboot=fastboot`, plus fastboot key-combo vars).

> **Fastboot is over USB only.** The device is currently on *wireless* adb; connect it to the PC
> with a **USB cable** before using fastboot. (Confirm with `fastboot devices` — it must list the
> device.) u-boot fastboot support is confirmed from the dumped env, but enumeration can only be
> verified over USB.

Package: [`../firmware/backup/fastboot/`](../firmware/backup/fastboot) (the `.img` files + script).
```
adb reboot fastboot                    # no hardware key combo is known on this unit (see docs/13)
cd firmware/backup/fastboot
./flash-all.sh                         # dry-run: prints the exact fastboot commands
./flash-all.sh --commit                # actually flash, then auto-reboot
```
`flash-all.sh` flashes `vbmeta*`, `dtbo_a`, `boot_a`, `init_boot_a`, `vendor_boot_a`, and the raw
`super` (u-boot sees `super` as a plain GPT partition, so the raw 2.56 GB image flashes directly —
no fastbootd needed). It deliberately **does not** flash `bootloader`/`env` (brick risk).

Manual equivalent:
```
fastboot flash vbmeta_a        vbmeta_a.img
fastboot flash vbmeta_system_a vbmeta_system_a.img
fastboot flash vbmeta_vendor_a vbmeta_vendor_a.img
fastboot flash dtbo_a          dtbo_a.img
fastboot flash boot_a          boot_a.img
fastboot flash init_boot_a     init_boot_a.img
fastboot flash vendor_boot_a   vendor_boot_a.img
fastboot flash super           super.img
fastboot reboot
```

## Option B — restore over adb-root (no USB needed)  ← works on the current wireless link
Symmetric with how the backup was made (`dd` to the named block devices). Safe-by-default
(dry-run, checksum-verified, skips userdata/metadata/frp/env/misc):
```
firmware/backup/restore-stock.sh              # dry-run
firmware/backup/restore-stock.sh --commit     # writes (prompts for YES), then: adb reboot
```

## Option C — Allwinner FEL (bootloader/brick recovery) — the unbrickable net
FEL is the SoC boot-ROM (BROM) USB recovery mode: it runs before boot0/u-boot and **cannot be bricked**
by any flash. It's the last resort when fastboot/adb are both gone (a dead bootloader). Note a plain
**Android bootloop does NOT drop to FEL** — u-boot is still valid, so use fastboot for that; FEL is only
for a broken bootloader.

> For an Android early-boot hang (no adb/fastboot) where u-boot is still alive — i.e. FEL is *not* the
> right tool — the practical path is the **UART serial console**: see
> [`11-uart-serial-console.md`](11-uart-serial-console.md). It reaches the device's own u-boot to launch
> fastboot or boot the stock `_b` slot, and diagnoses *why* the custom build hangs.

### FEL button (CONFIRMED)
This unit has a **recessed FEL button hidden inside one of the ports**. Procedure (it's sampled at
power-on; `bootdelay=0`):
1. Power the projector **fully off** (unplug).
2. **Press and hold** the recessed button.
3. **Apply power** while holding; keep holding ~8–10 s, then release.
4. Screen stays **black — this is normal** (FEL has no video output); the device is *not* bricked.
   Power-cycle without the button to boot normally again.

Confirmed FEL on the host: connect the **OTG USB port** (`usbc0` — same port as adb/fastboot) to a PC;
`lsusb` shows **`1f3a:efe8  Allwinner Technology sunxi SoC OTG connector in FEL/flashing mode`**.
(This button is FEL, **not** recovery — recovery is reached via software: `adb reboot recovery` on **stock**.
Our LineageOS build currently contains no recovery, see [`12`](12-rom-boot-fixes.md).)

**Reachable is not the same as usable.** On the stuck unit FEL can be entered but nothing can be flashed through
it yet: we lack boot0/u-boot/fes1 and the partition layout, and sunxi-tools does not support SoC id `0x1911`.

### Driving FEL from the host
```
sudo apt install sunxi-tools      # distro build is ~2022 (git20220212)
sunxi-fel ver                     # reads SoC ID from BROM even on unsupported chips
```
Caveat: the H723 (`sun50iw15`) is a 2023 SoC; the 2022 `sunxi-tools` likely reports **Unknown SOC**.
If so, build `sunxi-tools` from latest git (if sun50iw15 was added) or use the OEM **PhoenixSuit /
PhoenixCard** (Windows), which support this SoC. A single-file LiveSuit image needs the OEM packaging
tool (`awimage`/`imgRePacker`) and a `sys_partition.fex` we don't have, so per-partition fastboot
(Option A) stays the practical day-to-day route. **Update:** boot0, the u-boot package and both GPTs are now in `firmware/partition-copies/`, see [`15`](15-uboot-reverse-engineering.md). The
original note follows. **Note:** we hold **no** boot0/u-boot image to restore
via FEL — `bootloader_a.img` is only the logo/resource partition (see the backup note above). If the
real bootloader ever dies, recovery needs boot0/u-boot dumped from a live device or an OEM image.

## Option D — donor unit (fills the missing bootloader/layout, or hard-brick recovery)
An **identical** working unit (same model **and** hardware revision — same DRAM/panel/board rev) is the
clean way to obtain what this backup lacks: **boot0, u-boot, and the GPT/`sys_partition` layout**.

> **Ready-to-run tooling:** [`../tooling/donor-extract/`](../tooling/donor-extract) — a read-only suite
> that pulls everything off a booted donor over `adb`. Enable USB debugging on the donor, then:
> ```
> cd tooling/donor-extract && chmod +x *.sh && ./run-all.sh
> ```
> It dumps all named partitions, the raw boot0/u-boot/GPT region, the live DTB, cmdline, dmesg and props
> into `firmware/donor-dump/`, with checksums and a `REPORT.md`. See its README (incl. the `adb root`
> fallback). Nothing is written to the donor.

This yields the ingredients to build a valid PhoenixSuit/LiveSuit `.img`, and a **known-good UART boot
log to diff against a failing one**. Cautions:
- Reuse only **model-generic** blobs (boot0/u-boot/dtb/stock Android). Keep **this** unit's own
  per-device data — `env` (MAC addresses), `frp`, and secure-storage keys (HDCP/Widevine/EC) are unique;
  cloning the donor's breaks DRM (not boot) and changes MACs.
- Needed if this unit loses **all** recovery access or the real bootloader dies. With a way into fastboot and the
  Android backup, **Option A restores this unit without a donor.** The stuck unit currently has no such way in
  ([`13`](13-fastboot-trigger-no-fel.md)).

## Notes & cautions
- Flash **matching-slot** names (`*_a`); the device boots slot `_a`.
- vbmeta images are flashed **as stock** (the device already runs them). Only add
  `--disable-verity --disable-verification` if you later flash *modified* images.
- Verify before flashing: `cd firmware/partitions && sha256sum -c ../backup/SHA256SUMS.txt`.
- For a clean stock state, factory-reset userdata after restoring (Settings, or `fastboot -w`).
