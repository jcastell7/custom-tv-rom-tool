# Power-button boot trigger — "hold POWER at power-on → recovery"

**Branch:** `feat/fastboot-trigger-no-fel`

**Status: not possible as built.** The stick test printed `Unknown command 'gpio'`, so this u-boot has no `gpio`
command and the `if gpio input PL4` images **must not be flashed**. `if` is unknown too, so they would fire on every boot.
The recovery target does not exist in our build either. Reaching this goal would now need a modified u-boot.

**Use the rescue stick instead** ([`13`](13-fastboot-trigger-no-fel.md)): it gives a way back to fastboot from any
broken ROM with no changes to the unit. The rest of this document is kept as a record of the design.

Goal (owner's request): holding the power button while connecting power boots into **recovery**, from which
fastboot can be reached. That gives a way back in when a future custom ROM fails to boot.

The choice has to happen before the kernel starts, so it belongs in u-boot or its environment. It cannot live in
`boot.img` or `super`.

## Corrections to the first version of this document
- **"Fails safe" was wrong.** Without the hush parser, `if`, `then`, `else` and `fi` are unknown commands, but
  (from memory of u-boot's simple parser) the `;`-separated commands between them **still run**. The trigger
  would then fire on **every boot**.
- **"From recovery you reach fastboot" does not apply to our build.** It contains no recovery (see below).
- **"Everything else is ready to flash" was wrong**, for the reasons in "What has to happen".
- **"The current brick is a post-`bootm` hang" is unsupported.** No capture shows `Starting kernel`
  ([`13`](13-fastboot-trigger-no-fel.md)).
- **"No donor needed" was too strong.** See "Do we need the donor?".
- **The HY300 "direct confirmation" was overstated.** It is an unverified note about a different SoC.

## What has to happen

| # | Requirement | State |
|---|---|---|
| 1 | Power button readable as GPIO | Device tree says yes; never read in u-boot |
| 2 | u-boot has hush and the `gpio` command | **Both absent** (`Unknown command 'gpio'`, `'if'`, at least when run from the stick) |
| 3 | The PL4 level changes when the button is held during boot | **Unknown** |
| 4 | A custom `bootcmd` survives the `update bootcmd` step in the log | **Unknown** |
| 5 | The installed ROM contains a recovery | **Stock yes; our build no** |
| 6 | A way to write `env` to the unit | **Not available** on the stuck unit |

## Our build has no recovery
Compared against the stock `vendor_boot`:

| Item | Stock | Our build |
|---|---|---|
| `system/bin/recovery` | Present | **Missing** |
| `system/bin/fastbootd` | Present | **Missing** |
| `init.recovery.sun50iw15p1.rc`, `res/`, recovery UI libraries | Present | **Missing** |
| Top level of ramdisk | Full recovery root | Only `lib/` and `first_stage_ramdisk/` |

Stock keeps recovery in the `vendor_boot` ramdisk, and `ab_partition_list` has no `recovery` partition. Our
`BoardConfig.mk` has `BOARD_USES_RECOVERY_AS_BOOT := false` and does not move recovery into `vendor_boot`, so no
recovery is built. Setting `force_normal_boot=0` on our build would not give a recovery; it would most likely
just fail to boot.

**Required before recovery can be the target:** build recovery into `vendor_boot`, most likely with
`BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true` and a recovery fstab. This has **not been done or tried**.

**Consequence for choosing a target:** recovery depends on the kernel and `vendor_boot` being intact, so a ROM
that breaks those takes recovery down with it. `boot_fastboot` runs inside u-boot and depends on neither. The
owner's preference is recovery, and `env-powerkey-recovery.img` is kept as that option.
`env-powerkey-fastboot.img` remains the variant that works without a recovery.

## Hardware, from our own dumps (`firmware/extracted/dts/vendor_boot.dts`)
- **PMIC:** AXP1530 at `pmu@36`; its power-key node `axp1530-pek` is `status = "disabled"`.
- **Power button:** `power_key = "PL4"`, plus `gpio-keys` node `key_power` with `gpios = <0x69 0x0 0x4 0x1>`.
  Phandle `0x69` is in `pinctrl@7022000` (the PL/PM controller), flag 1 means active-low, and `linux,code = 0x74`
  is `KEY_POWER`.
- **IR receiver:** the DTS lists `ir_power_key_code0..11`; see the remote-key test in
  [`13`](13-fastboot-trigger-no-fel.md).

This describes the Linux side. It does not prove that u-boot sees the pin the same way at that point in the boot.

## The mechanism
From memory, u-boot's `gpio input` returns the pin level as its exit status, so an active-low button held down
reads 0 and `if` is true. `uboot-powerkey-test.cmds` checks this before anything is flashed.

```
# env-powerkey-recovery.img (owner's preferred target; needs requirement 5)
bootcmd=if gpio input PL4;then echo [trigger-env] POWER held -> recovery;setenv force_normal_boot 0;run setargs_nand boot_normal;else run setargs_nand boot_normal;fi

# env-powerkey-fastboot.img (no recovery needed)
bootcmd=if gpio input PL4;then echo [trigger-env] POWER held -> fastboot;run boot_fastboot;else run setargs_nand boot_normal;fi
```

`force_normal_boot=0` is used because stock's `boot_recovery` reads a `recovery` partition that is not in
`ab_partition_list`.

## Failure modes

| Situation | Result |
|---|---|
| No hush parser | Trigger fires on **every boot** |
| `gpio` command missing or pin name rejected | With hush: normal boot, trigger never fires |
| PL4 reads low when not pressed | Trigger fires on **every boot** |
| `update bootcmd` overwrites the command | Trigger ignored, or the command is mangled |
| Recovery target with no recovery in the ROM | Held power leads to a failed boot; normal boot unaffected |

## How to apply
Only once a flashing mode and a live `sunxi#` prompt are both available:

```
# 1. Run tooling/env-fastboot-trigger/uboot-powerkey-test.cmds at sunxi#. All checks must pass.
# 2. Check that the stock env really is the one in use: printenv at sunxi#, compare with env_a.img.
# 3. Find the real partition name:  fastboot getvar all
# 4. Generate the images:
tooling/env-fastboot-trigger/build-trigger-env.py
# 5. Flash one image, to the partition found in step 3:
fastboot flash <partition> tooling/env-fastboot-trigger/out/env-powerkey-fastboot.img
#    Use env-powerkey-recovery.img only if the installed ROM contains a recovery.
fastboot reboot
# 6. Test released first (must boot normally), then held.
```

Keep a way back before step 5: the stock `env_a.img`, and a confirmed way to re-enter fastboot.

## Do we need the donor?
**Not to build the images. Possibly to apply them**, depending on whether the unit can be reached at all:

- **RX is confirmed working as far as boot0.** If u-boot also accepts input ([`11`](11-uart-serial-console.md) §5),
  no donor is needed: the prompt covers the validation, and `fastboot` covers the flashing.
- **If u-boot ignores input:** the remaining routes are direct eMMC wiring, the untested USB and remote leads in
  [`13`](13-fastboot-trigger-no-fel.md), or a **donor**. A donor would supply boot0/u-boot for FEL, but FEL also
  needs tooling that supports this SoC.
- **Without a prompt anywhere**, requirements 2–4 can only be tested by flashing and watching, or on a donor's
  u-boot if it can be reached.

## If hush or `gpio` are not available
1. `env-force-fastboot.img` while developing a ROM. It needs no hush, but it enters fastboot on every boot, and
   leaving it requires flashing another env. Not the power-button behaviour.
2. Patch the u-boot binary. Needs the binary (from a donor or a dump) and reverse engineering. Risky: a bad
   u-boot needs FEL or eMMC wiring to repair.
3. Rebuild the boot chain. The [minpeter/allwinner-h713-linux](https://github.com/minpeter/allwinner-h713-linux)
   project built an open boot chain for the related H713 and is a reference, not something that can be applied
   directly to the H723.

## HY300 notes (H713, related SoC, not this chip)
From the [YuujiLab research note](https://github.com/YuujiLab/HY300-H713-Research/blob/main/Boot/BOOT_MODES.md),
unverified:
- Its env has the same shape as ours (`bootcmd=run setargs_nand boot_normal`, `boot_fastboot=fastboot`), which
  suggests a shared vendor u-boot lineage. It does not show that our build has hush or `gpio`.
- The note says editing `bootcmd` redirects boot without changing u-boot.
- It describes IR triggers (Vol+ → FEL, Home → recovery with a factory wipe), not a power-button trigger. The
  behaviour the owner remembers from the HY300 may be IR-based or may simply not be covered by this note.
