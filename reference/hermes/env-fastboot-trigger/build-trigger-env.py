#!/usr/bin/env python3
"""
build-trigger-env.py — generate modified u-boot env images for the hermes
projector that make fastboot reachable WITHOUT FEL.

It edits the stock env (firmware/partitions/env_a.img) with the verified
codec in uboot_env.py and writes CRC-correct, flashable env images.

Variants produced (see docs/13-fastboot-trigger-no-fel.md):

  env-fallback.img
      Normal boot is UNCHANGED, but a fastboot fallback is appended to
      bootcmd so that if `bootm` ever RETURNS (corrupt/missing boot image),
      u-boot drops into fastboot. Does not help if bootm never returns.

  env-force-fastboot.img
      bootcmd := fastboot. Device ALWAYS enters fastboot at power-on.
      Bring-up / deliberate-recovery use only — remove it (flash a normal
      env) once the device boots, or it will never load Android.

  env-widen-key.img   (only if --key-window given)
      DO NOT USE. Changes fastboot_key_value_max, but what reads that
      variable, and on what scale, is unknown. This unit has no known ADC
      buttons. Kept as a record of the attempt.

  env-powerkey-fastboot.img
      bootcmd reads the power button GPIO (PL4, active-low, KEY_POWER) with
      u-boot's `gpio` command: if HELD at power-on, enter u-boot fastboot;
      otherwise boot normally. UNTESTED. Needs hush and `gpio` in this
      u-boot, and bootcmd must survive the "update bootcmd" step. WITHOUT
      HUSH IT ENTERS FASTBOOT ON EVERY BOOT. Run uboot-powerkey-test.cmds
      before flashing. See docs/14.

  env-powerkey-recovery.img
      Same PL4 check, but a held button sets force_normal_boot=0 to select
      the recovery in the vendor_boot ramdisk. UNTESTED. Same requirements.
      Also needs a ROM containing a recovery: stock has one, our LineageOS
      build does not yet (docs/12). WITHOUT HUSH IT RUNS ON EVERY BOOT.

All outputs are full 256 KiB partition images, ready for:
    fastboot flash env  <file>          (A/B: flashes the active slot's env)

Usage:
    build-trigger-env.py [--stock PATH] [--out DIR] [--key-window MIN MAX]
                         [--powerkey-gpio PL4]
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import uboot_env as ue  # noqa: E402


def load_stock(path):
    raw = open(path, "rb").read()
    if not ue.verify_roundtrip(path):
        print("ERROR: stock env failed round-trip; refusing to edit a "
              "format we cannot reproduce.", file=sys.stderr)
        sys.exit(1)
    return ue.decode(raw)


def write_variant(name, vars_, order, leading, tail, outdir, edits):
    v = dict(vars_)
    o = list(order)
    for k, val in edits.items():
        if k not in v:
            o.append(k)
        v[k] = val
    out = ue.encode(v, o, leading, tail)
    path = os.path.join(outdir, name)
    with open(path, "wb") as f:
        f.write(out)
    # confirm it decodes back and CRC validates by re-decoding
    import binascii
    crc = binascii.crc32(out[4:ue.ENV_SIZE]) & 0xFFFFFFFF
    stored = int.from_bytes(out[0:4], "little")
    assert crc == stored, "internal CRC mismatch"
    print(f"  wrote {name:26s} ({len(out)} bytes, crc=0x{crc:08x})  "
          f"bootcmd={v['bootcmd']!r}")
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stock",
                    default=os.path.join(HERE, "..", "..", "firmware",
                                         "partitions", "env_a.img"))
    ap.add_argument("--out", default=os.path.join(HERE, "out"))
    ap.add_argument("--key-window", nargs=2, metavar=("MIN", "MAX"),
                    help="hex ADC key values, e.g. --key-window 0x2 0xf")
    ap.add_argument("--powerkey-gpio", default="PL4",
                    help="u-boot name of the power-button GPIO "
                         "(this board: PL4, active-low; default PL4)")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    vars_, order, leading, tail = load_stock(args.stock)

    print(f"stock bootcmd      = {vars_.get('bootcmd')!r}")
    print(f"stock boot_fastboot= {vars_.get('boot_fastboot')!r}")
    print(f"stock key window   = {vars_.get('fastboot_key_value_min')}"
          f"..{vars_.get('fastboot_key_value_max')}")
    print(f"writing variants to {os.path.relpath(args.out)}/\n")

    # --- Variant 1: fallback-to-fastboot on a returning bootm ---
    # Keep the exact stock boot path, then catch a returned bootm.
    fallback_bootcmd = ("run setargs_nand boot_normal;"
                        "echo [trigger-env] boot_normal returned, "
                        "entering fastboot;run boot_fastboot")
    write_variant("env-fallback.img", vars_, order, leading, tail, args.out,
                  {"bootcmd": fallback_bootcmd})

    # --- Variant 2: force fastboot every boot (bring-up only) ---
    write_variant("env-force-fastboot.img", vars_, order, leading, tail,
                  args.out, {"bootcmd": "run setargs_nand;run boot_fastboot"})

    # --- Variant 3 (optional): widen ADC fastboot key window ---
    if args.key_window:
        kmin, kmax = args.key_window
        write_variant("env-widen-key.img", vars_, order, leading, tail,
                      args.out,
                      {"fastboot_key_value_min": kmin,
                       "fastboot_key_value_max": kmax})

    # --- Variant 4: THE POWER-BUTTON TRIGGER (hold power -> fastboot) ---
    # Power button = GPIO PL4, active-low (sys_config power_key="PL4";
    # gpio-keys key_power linux,code=0x74=KEY_POWER). u-boot's `gpio input`
    # should return the pin level as its exit status: active-low => pressed
    # reads 0 => `if` TRUE => enter fastboot. With hush, a released pin or a
    # gpio error takes the normal path. This does NOT fail safe WITHOUT hush:
    # the simple parser skips the unknown if/then/else words but still runs
    # the commands between them, so the trigger fires on every boot.
    gp = args.powerkey_gpio
    pk_fastboot = (f"if gpio input {gp};"
                   f"then echo [trigger-env] POWER held -> fastboot;"
                   f"run boot_fastboot;"
                   f"else run setargs_nand boot_normal;fi")
    write_variant("env-powerkey-fastboot.img", vars_, order, leading, tail,
                  args.out, {"bootcmd": pk_fastboot})

    # --- Variant 5: power button -> recovery in the vendor_boot ramdisk ---
    # No dedicated `recovery` partition exists in ab_partition_list, so a held
    # power button sets androidboot.force_normal_boot=0. Stock's vendor_boot
    # contains a recovery; our LineageOS build's does not yet (docs/12).
    pk_recovery = (f"if gpio input {gp};"
                   f"then echo [trigger-env] POWER held -> recovery;"
                   f"setenv force_normal_boot 0;run setargs_nand boot_normal;"
                   f"else run setargs_nand boot_normal;fi")
    write_variant("env-powerkey-recovery.img", vars_, order, leading, tail,
                  args.out, {"bootcmd": pk_recovery})

    print("\nDone. Flash with:  fastboot flash env <file>   "
          "(see docs/13 and docs/14)")


if __name__ == "__main__":
    main()
