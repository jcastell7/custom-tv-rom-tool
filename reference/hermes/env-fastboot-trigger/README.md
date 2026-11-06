# env-fastboot-trigger

Env-based boot triggers for the Allwinner H723 "hermes" projector, built from our own
`firmware/partitions/env_a.img` backup. Full rationale and limits: [`../../docs/13-fastboot-trigger-no-fel.md`](../../docs/13-fastboot-trigger-no-fel.md).

> **None of these images has run on hardware. Don't flash the power-key images:** this u-boot has no `gpio` command
> (confirmed by the stick test), so they can't work. For a way back into fastboot, use the rescue stick in docs/13.

## Quick use

```bash
# 1. Prove the env codec reproduces the stock image byte-for-byte
./uboot_env.py verify ../../firmware/partitions/env_a.img

# 2. Generate flashable env variants into out/
./build-trigger-env.py
```

## What each script does
- **`uboot_env.py`** — decode/encode the u-boot env partition (non-redundant, `CONFIG_ENV_SIZE=0x20000`,
  CRC32-LE over `[4:0x20000]`). `verify` asserts a byte-exact round-trip before any edit is trusted.
- **`build-trigger-env.py`** — writes CRC-correct 256 KiB images to `out/`:
  - `env-powerkey-recovery.img` — hold POWER at power-on (GPIO `PL4`) → recovery. The owner's preferred target,
    but **needs a ROM that contains a recovery; our build doesn't yet.** See
    [`../../docs/14-power-key-boot-trigger.md`](../../docs/14-power-key-boot-trigger.md).
  - `env-powerkey-fastboot.img` — same check → u-boot fastboot. Works without a recovery.
  - `env-fallback.img` — normal boot unchanged, but a *returning* `bootm` drops to fastboot.
  - `env-force-fastboot.img` — always boots to fastboot (bring-up only; flash a normal env back after).
  - `env-widen-key.img` — only with `--key-window MIN MAX`. **Don't use:** rests on an unverified ADC assumption.
- **`find-fastboot-key.py`** — **Don't use.** It assumes `key press :` reports an ADC button value. That line
  reports a UART character (confirmed), and the unit has no such buttons. Kept as a record.
- **`uboot-powerkey-test.cmds`** — run at the u-boot prompt to check hush, `gpio input PL4`, the held/released
  level change, and the live `bootcmd` **before** flashing a power-key env.

## Important limit
Flashing any of these requires a flashing mode, which the stuck unit doesn't currently have. See docs/13. Find
the real partition name with `fastboot getvar all` first.

`out/` is regenerated from the stock backup and is git-ignored.
