#!/usr/bin/env python3
"""
make-stick.py - write update/auto_update.txt scripts to a USB stick for this projector's u-boot.
Background: docs/13-fastboot-trigger-no-fel.md and docs/15-uboot-reverse-engineering.md.

  make-stick.py rescue  MOUNT    u-boot fastboot on each boot with the stick in. Writes nothing to the eMMC.
  make-stick.py ramboot MOUNT    Boots stock recovery from RAM. Loads stock init_boot/vendor_boot from the stick. No eMMC write.
  make-stick.py restore MOUNT    WRITES the stock _a boot chain to the eMMC, then reads it back and prints CRCs.
  make-stick.py check   LOG      compare the CRCs in a UART log with those expected for the restore.

`restore` never touches boot0, u-boot, env, misc, GPT, super or userdata. u-boot runs the stick before it loads any
of these images, so if a write goes wrong the stick still works and can be run again.

Why the script looks like this:
  - Each line becomes "<word1> <word2> 0x40007000 <word4> 0x<size>", after loading <word3> from the stick.
  - Tabs inside a word survive the stick parser and act as separators in u-boot. A trailing ';' ends the command
    before the appended arguments. Lines using this print a harmless "Unknown command '0x40007000'".
  - fatload sets the env variable `filesize`, and the parser trusts it on the next line. At 8 MiB or more it takes a
    chunked path that skips the line's command, so every fatload line resets it with `setenv filesize 0`.
  - The same path silently skips the command for any file that is an exact multiple of 8 MiB, which includes
    boot_a, init_boot_a and vendor_boot_a. So those can't use the documented "sunxi_flash write <file> <part>" form.
  - Each word is limited to 63 characters, so stick files use short names.
  - "sunxi_flash read" underflows and crashes with a size below 0x8000.
  - The load address is 0x40007000 and the monitor is at 0x48000000, so stick files must stay under about 127 MiB.
"""
import hashlib
import os
import re
import shutil
import sys
import zlib

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PARTS = os.path.join(REPO, "firmware", "partitions")
SUMS = os.path.join(REPO, "firmware", "backup", "SHA256SUMS.txt")

# (image, partition, partition sectors from firmware/device-state/emmc-partition-map.txt)
RESTORE = [
    ("vbmeta_a.img", "vbmeta_a", 0x100),
    ("vbmeta_system_a.img", "vbmeta_system_a", 0x80),
    ("vbmeta_vendor_a.img", "vbmeta_vendor_a", 0x80),
    ("dtbo_a.img", "dtbo_a", 0x1000),
    ("boot_a.img", "boot_a", 0x20000),
    ("init_boot_a.img", "init_boot_a", 0x4000),
    ("vendor_boot_a.img", "vendor_boot_a", 0x10000),
]
SHORT = {"vbmeta_a.img": "vm.img", "vbmeta_system_a.img": "vs.img", "vbmeta_vendor_a.img": "vv.img",
         "dtbo_a.img": "d.img", "boot_a.img": "b.img", "init_boot_a.img": "i.img", "vendor_boot_a.img": "v.img"}
MAX_STICK_FILE = 0x48000000 - 0x40007000
MIN_READ = 0x8000
READ_ADDR = 0x41000000


def die(msg):
    sys.exit("ERROR: " + msg)


def load_line(addr, name):
    return f"fatload\tusb\t0\t{addr:#x}\tupdate/{name};setenv\tfilesize\t0;"


def check_lengths(lines):
    for line in lines:
        if len(line) >= 0x40:
            die(f"line is too long for the stick parser's 64-byte field: {line!r}")


def load_sums():
    sums = {}
    for line in open(SUMS):
        digest, name = line.split(None, 1)
        sums[name.strip()] = digest
    return sums


def checked_images():
    """Validate each stock image; return (image, partition, size, crc32)."""
    sums = load_sums()
    out = []
    for image, part, sectors in RESTORE:
        data = open(os.path.join(PARTS, image), "rb").read()
        if hashlib.sha256(data).hexdigest() != sums.get(image):
            die(f"{image} does not match {SUMS}")
        size = len(data)
        if size != sectors * 512:
            die(f"{image} is {size:#x} bytes, partition {part} is {sectors * 512:#x}")
        if size > MAX_STICK_FILE:
            die(f"{image} is too large to load at 0x40007000")
        if size < MIN_READ:
            die(f"{image} is below the {MIN_READ:#x} safe read size")
        out.append((image, part, size, zlib.crc32(data) & 0xFFFFFFFF))
    return out


def write_script(mount, lines):
    if not os.path.isdir(mount) or not os.path.ismount(mount):
        die(f"{mount} is not a mounted filesystem")
    update = os.path.join(mount, "update")
    os.makedirs(update, exist_ok=True)
    with open(os.path.join(update, "auto_update.txt"), "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n%\n")
    return update


# u-boot globals, static address + "Relocation Offset is: 2c909000" from the boot log. See docs/15.
RELOC = 0x2c909000
INIT_FLAG, INIT_PTR = 0x4a0abb74 + RELOC, 0x4a0abfac + RELOC     # android_image cache for init_boot
VENDOR_FLAG, VENDOR_PTR = 0x4a0abb78 + RELOC, 0x4a0abfb0 + RELOC  # same for vendor_boot
SKIP_SHUTDOWN = 0x4a0e6cf0 + RELOC                               # non-zero: updater returns as if no stick
RTC_MODE, RTC_RECOVERY = 0x07090118, 0x5c
RAM_VENDOR, RAM_INIT = 0x50000000, 0x52000000                    # away from u-boot's head at 0x4a000000


def ramboot(mount):
    if not os.path.ismount(mount):
        die(f"{mount} is not a mounted filesystem")
    images = {i[0]: i for i in checked_images()}
    vendor, init = images["vendor_boot_a.img"], images["init_boot_a.img"]
    if shutil.disk_usage(mount).free < vendor[2] + init[2]:
        die("not enough free space on the stick")
    lines = [
        f"md.l\t{INIT_FLAG:#x}\t2;",
        f"md.l\t{SKIP_SHUTDOWN:#x}\t1;",
        load_line(RAM_VENDOR, SHORT[vendor[0]]),
        load_line(RAM_INIT, SHORT[init[0]]),
        f"md.b\t{RAM_VENDOR:#x}\t0x10;",
        f"md.b\t{RAM_INIT:#x}\t0x10;",
        "echo\tCRC-vendor;",
        f"crc32\t{RAM_VENDOR:#x}\t{vendor[2]:#x};",
        "echo\tCRC-init;",
        f"crc32\t{RAM_INIT:#x}\t{init[2]:#x};",
        f"mw.l\t{VENDOR_PTR:#x}\t{RAM_VENDOR:#x};",
        f"mw.l\t{VENDOR_FLAG:#x}\t1;",
        f"mw.l\t{INIT_PTR:#x}\t{RAM_INIT:#x};",
        f"mw.l\t{INIT_FLAG:#x}\t1;",
        f"mw.l\t{RTC_MODE:#x}\t{RTC_RECOVERY:#x};",
        f"md.l\t{RTC_MODE:#x}\t1;",
        f"mw.l\t{SKIP_SHUTDOWN:#x}\t1;",
    ]
    check_lengths(lines)
    for line in lines:
        if re.search(r"write|erase|saveenv|\bmmc\b", line):
            die(f"refusing a line that could change the eMMC: {line!r}")
    update = write_script(mount, lines)
    for image in (vendor[0], init[0]):
        shutil.copyfile(os.path.join(PARTS, image), os.path.join(update, SHORT[image]))
    os.sync()
    print(f"RAM boot stick ready in {update}. Nothing here writes to the eMMC. Expected in the log:")
    print(f"  CRC-vendor {vendor[3]:08x}\n  CRC-init   {init[3]:08x}")
    print("  VNDRBOOT and ANDROID! in the md.b lines, bootmode[...]:0x5c, then ramdisk use init boot and kernel output.")
    print("Unmount it before removing it.")


def rescue(mount):
    write_script(mount, ["run boot_fastboot"])
    print("Rescue stick ready. It enters u-boot fastboot (the robot screen) on each boot while inserted.")


def restore(mount):
    if not os.path.ismount(mount):
        die(f"{mount} is not a mounted filesystem")
    images = checked_images()
    needed = sum(i[2] for i in images)
    free = shutil.disk_usage(mount).free
    if free < needed:
        die(f"stick has {free} bytes free, needs {needed}")
    lines = []
    for image, part, size, _ in images:
        lines.append(load_line(READ_ADDR, SHORT[image]))
        lines.append(f"sunxi_flash\twrite\t{READ_ADDR:#x}\t{part}\t{size:#x};")
    lines.append("echo\tRESTORE-VERIFY;")
    for image, part, size, _ in images:
        lines.append(f"sunxi_flash\tread\t{READ_ADDR:#x}\t{part}\t{size:#x};")
        lines.append(f"echo\tCRC-{part};")
        lines.append(f"crc32\t{READ_ADDR:#x}\t{size:#x};")
    check_lengths(lines)
    update = write_script(mount, lines)
    for image, _, _, _ in images:
        shutil.copyfile(os.path.join(PARTS, image), os.path.join(update, SHORT[image]))
    os.sync()
    print(f"Stock restore written to {update}.\nThis stick WRITES to the eMMC when booted. Expected CRC32:")
    for _, part, _, crc in images:
        print(f"  {part:18s} {crc:08x}")
    print("Unmount it before removing it. Check afterwards with: make-stick.py check <uart.log>")


def check(log):
    text = open(log, errors="replace").read()
    bad = 0
    for _, part, _, crc in checked_images():
        m = re.search(r"CRC-" + part + r"\b.*?==>\s*([0-9a-fA-F]{8})", text, re.S)
        got = m.group(1).lower() if m else None
        ok = got == f"{crc:08x}"
        bad += not ok
        print(f"{'OK ' if ok else 'BAD'} {part:18s} expected {crc:08x} got {got}")
    errors = re.findall(r"sunxi flash write :.*ERROR.*", text)
    for line in errors:
        print("WRITE ERROR:", line)
    sys.exit(1 if bad or errors else 0)


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("rescue", "ramboot", "restore", "check"):
        sys.exit(__doc__)
    {"rescue": rescue, "ramboot": ramboot, "restore": restore, "check": check}[sys.argv[1]](sys.argv[2])


if __name__ == "__main__":
    main()
