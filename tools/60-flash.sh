#!/usr/bin/env bash
# Flashes a build from userspace fastboot (fastbootd) only. Refuses bootloader, GPT and per-device partitions by design.
# Usage: 60-flash.sh --out PRODUCT_OUT --backup BACKUP_DIR --slot a [--images "vendor_boot init_boot boot dtbo vbmeta_vendor vbmeta_system vbmeta super"]
#                    [--wipe] [--init-boot PATCHED_IMG] [--skip-gate] [--bootloader-fastboot]
#
# Refuses unless: a verified backup exists, 50-gate.py passed for exactly these images, and the device is in fastbootd.
# Doesn't reboot unless the flash finished. Stops at the first failure, because a half-flashed device needs a person's decision.
set -euo pipefail
. "$(dirname "$0")/common.sh"
OUT=; BACKUP=; SLOT=; WIPE=0; INIT=; SKIPGATE=0; BLFB=0
IMAGES="vendor_boot init_boot boot dtbo vbmeta_vendor vbmeta_system vbmeta super"
while [ $# -gt 0 ]; do case $1 in
  --out) OUT=$2; shift ;; --backup) BACKUP=$2; shift ;; --slot) SLOT=$2; shift ;; --images) IMAGES=$2; shift ;;
  --wipe) WIPE=1 ;; --init-boot) INIT=$2; shift ;; --skip-gate) SKIPGATE=1 ;; --bootloader-fastboot) BLFB=1 ;;
  *) die "unknown option $1" ;; esac; shift; done
[ -d "$OUT" ] && [ -n "$BACKUP" ] && [ -n "$SLOT" ] || die "needs --out, --backup and --slot. See the top of this file."

# 1. A way back must exist before anything is written.
[ -s "$BACKUP/SHA256SUMS" ] || die "no verified backup at $BACKUP. Run 20-backup.sh and 21-check-backup.py."
python3 -I "$TOOLS_DIR/21-check-backup.py" "$BACKUP" > /dev/null || die "backup check failed. Run 21-check-backup.py to see why."

# 2. Never write these. Restoring them is a separate, deliberate, human job.
for img in $IMAGES; do
  case "$img" in
    boot0*|bootloader*|preloader*|xbl*|abl*|lk*|uboot*|u-boot*|tee*|trust*|tz*|bl31*|spl*|sbl*|gpt*|partition*|mbr*|env*|nvram*|persist*|frp*|misc*|modem*|efs*|metadata*|mmcblk*)
      die "$img is on the never-flash list: a mistake here can brick the device or destroy per-device data." ;;
  esac
done

# 3. The gate must have passed for these exact files.
if [ "$SKIPGATE" = 0 ]; then
  [ -f "$OUT/GATE_PASS" ] || die "no GATE_PASS. Run 50-gate.py. A partial --only run doesn't count."
  (cd "$OUT" && for img in $IMAGES; do [ -f "$img.img" ] || die "$img.img doesn't exist"; grep "  $img.img\$" GATE_PASS | sha256sum -c --quiet - ; done) \
    || die "images changed since the gate ran. Run 50-gate.py again."
fi

# 4. Check the device, using read-only queries only.
var() { timeout 15 $FASTBOOT getvar "$1" 2>&1 | sed -n "s/^$1: *//p" | head -1; }
[ "$(timeout 15 $FASTBOOT devices | wc -l)" = 1 ] || die "need exactly one fastboot device"
userspace=$(var is-userspace)
[ "$userspace" = yes ] || [ "$BLFB" = 1 ] || die "not fastbootd (is-userspace=$userspace). Bootloader fastboot often can't write logical partitions, and on hermes the PC couldn't even see it. Pass --bootloader-fastboot only if you know it works."
[ "$(var unlocked)" != no ] || die "bootloader is locked"
cur=$(var current-slot); [ -z "$cur" ] || [ "$cur" = "$SLOT" ] || die "device is on slot $cur, you asked for $SLOT"
snap=$(var snapshot-update-status); [ -z "$snap" ] || [ "$snap" = none ] || die "a snapshot update is in progress ($snap). Flashing super now could lose data."

# 5. Size-check everything before writing anything.
src_of() { local n=$1; if [ "$n" = init_boot ] && [ -n "$INIT" ]; then echo "$INIT"; else echo "$OUT/$n.img"; fi; }
part_of() { case "$1" in super) echo super ;; *) echo "${1}_$SLOT" ;; esac; }
for n in $IMAGES; do
  src=$(src_of "$n"); [ -f "$src" ] || die "missing $src"
  max=$(var "partition-size:$(part_of "$n")")
  if [ -n "$max" ] && [ "$(stat -Lc %s "$src")" -gt "$(printf '%d' "$max")" ]; then die "$src is larger than its partition"; fi
done

# 6. Write.
for n in $IMAGES; do
  echo "=== $(part_of "$n") <- $(src_of "$n")"
  $FASTBOOT flash "$(part_of "$n")" "$(src_of "$n")"
done
if [ "$WIPE" = 1 ]; then echo "=== erasing userdata"; $FASTBOOT erase userdata; fi
green "Flashed. Not rebooted. Run: $FASTBOOT reboot   then: tools/70-watch-boot.sh"
