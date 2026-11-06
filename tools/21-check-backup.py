#!/usr/bin/env python3
"""Checks a backup from 20-backup.sh is complete and contains what a restore needs. Read-only. Exit status 0 means no STOP items.

Usage: 21-check-backup.py BACKUP_DIR

It recognises common signatures. An unknown bootloader isn't a failure by itself: it means you must identify it yourself (docs/03).
"""
import hashlib, os, re, struct, sys

SIGS = [
    (b"eGON.BT0", "Allwinner boot0 (SPL)"), (b"sunxi-package", "Allwinner u-boot package"),
    (b"EFI PART", "GPT header"), (b"RKNS", "Rockchip idbloader (RKNS)"), (b"LOADER  ", "Rockchip loader"),
    (b"RK3", "Rockchip marker, weak"), (b"@AML", "Amlogic boot image"), (b"MMM\x01", "MediaTek marker, weak"),
    (b"EMMC_BOOT", "MediaTek preloader"), (b"U-Boot ", "U-Boot strings"), (b"ANDROID!", "Android boot image"),
    (b"VNDRBOOT", "Android vendor_boot"), (b"AVB0", "AVB vbmeta"), (b"ELF", "ELF, e.g. Qualcomm xbl/abl, weak"),
]
BOOT_CHAIN = re.compile(r"^(preloader|boot0|bootloader|xbl|abl|uboot|u-boot|lk|tee|bl31|bl2|spl|loader|sbl|aboot|tz|trust|idbloader|mbr|gpt|boot_a?$|boot$)", re.I)
MUST_HAVE = ["boot", "vbmeta"]

def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()

def scan(path, limit=64 << 20):
    with open(path, "rb") as f:
        data = f.read(limit)
    return data, sorted({label for sig, label in SIGS if sig in data})

def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    d = sys.argv[1]
    stop, warn = [], []
    sums = os.path.join(d, "SHA256SUMS")
    if not os.path.exists(sums):
        sys.exit(f"STOP: no SHA256SUMS in {d}. This isn't a finished backup.")
    print("Checking checksums...")
    entries = [l.split() for l in open(sums) if l.strip()]
    for want, name in entries:
        p = os.path.join(d, name)
        if not os.path.exists(p):
            stop.append(f"{name} is listed but missing")
        elif sha(p) != want:
            stop.append(f"{name} has the WRONG checksum")
    print(f"  {len(entries)} files checked")

    names = {n[:-4] for _, n in entries}
    sizes = os.path.join(d, "layout", "partition-sizes.txt")
    if os.path.exists(sizes):
        for line in open(sizes):
            parts = line.split()
            if len(parts) != 2:
                continue
            sz, n = parts
            if n not in names and not re.match(r"(userdata|data|mmcblk\d+|sd.)$", n):
                stop.append(f"partition {n} ({sz} bytes) wasn't copied")
    pp = os.path.join(d, "layout", "proc-partitions.txt")
    if os.path.exists(pp):
        for line in open(pp):
            f = line.split()
            if len(f) == 4 and re.fullmatch(r"mmcblk\d+boot\d+", f[3]) and f"disk-{f[3]}" not in names:
                stop.append(f"hardware boot area {f[3]} wasn't copied. Many SoCs boot from it.")
    for m in MUST_HAVE:
        if m not in names and m + "_a" not in names:
            stop.append(f"no {m} or {m}_a partition in the backup")

    print("\nBoot chain evidence:")
    found_loader = False
    for n in sorted(names):
        p = os.path.join(d, n + ".img")
        if not os.path.exists(p):
            continue
        if n.startswith("disk-") or BOOT_CHAIN.match(n):
            _, labels = scan(p)
            size = os.path.getsize(p)
            if not any(open(p, "rb").read(1 << 16)):
                labels = labels + ["first 64 KiB are all zero"]
            print(f"  {n:28} {size/1048576:9.1f} MiB  {', '.join(labels) or 'no known signature'}")
            if n.startswith("disk-") or re.match(r"(preloader|boot0|bootloader|xbl|abl|uboot|u-boot|lk|sbl|aboot|idbloader|loader)", n, re.I):
                if any(("boot0" in l or "U-Boot" in l or "idbloader" in l or "preloader" in l or "loader" in l or "Amlogic" in l or "ELF" in l) for l in labels):
                    found_loader = True
    if not found_loader:
        warn.append("No bootloader signature recognised. Confirm by hand where boot0/u-boot/preloader lives. "
                    "Lesson from hermes: a partition NAMED bootloader held only logos, and the real bootloader sat outside every partition.")

    print("\nA/B slots:")
    for n in sorted(names):
        if n.endswith("_b"):
            p = os.path.join(d, n + ".img")
            if os.path.exists(p) and not any(open(p, "rb").read(1 << 20)):
                print(f"  {n}: first MiB is all zero, so this slot is NOT a usable fallback")

    for name, text in [("per-device data", "Treat this backup as private: env, persist, nvram, frp and similar partitions can hold MAC addresses, serials and keys.")]:
        print(f"\nNOTE ({name}): {text}")
    print("\n" + "=" * 60)
    for w in warn:
        print("WARN:", w)
    for s in stop:
        print("STOP:", s)
    if stop:
        print("Backup is NOT usable. Re-run 20-backup.sh.")
        return 1
    print("Backup is complete and checksums match. Next: make a second copy, then read docs/03 and prove a way back.")
    return 0

sys.exit(main())
