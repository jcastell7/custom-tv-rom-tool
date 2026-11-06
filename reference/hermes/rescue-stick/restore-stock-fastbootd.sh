#!/usr/bin/env bash
# Restore the stock _a images from firmware/partitions/ over fastbootd. See docs/13.
#   restore-stock-fastbootd.sh            dry run: checks everything, writes nothing
#   restore-stock-fastbootd.sh --commit   WRITES to the eMMC; stops at the first failure and doesn't reboot
# Never touches boot0, u-boot, env, misc, GPT, frp, metadata or userdata.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; P="$ROOT/firmware/partitions"
COMMIT=0; [ "${1:-}" = "--commit" ] && COMMIT=1

# Boot chain first: once vendor_boot_a is written, recovery no longer needs the stick.
PARTS=(vendor_boot_a init_boot_a boot_a dtbo_a vbmeta_vendor_a vbmeta_system_a vbmeta_a super)

var() { timeout 15 fastboot getvar "$1" 2>&1 | sed -n "s/^$1: *//p" | head -1; }

(cd "$P" && grep -E " ($(IFS='|'; echo "${PARTS[*]}")).img$" "$ROOT/firmware/backup/SHA256SUMS.txt" | sha256sum --quiet -c -) \
  || { echo "ERROR: a backup image fails its checksum"; exit 1; }
echo "Backup images: checksums OK"

[ "$(timeout 15 fastboot devices | wc -l)" = 1 ] || { echo "ERROR: need exactly one fastboot device"; exit 1; }
[ "$(var is-userspace)" = yes ] || { echo "ERROR: not in fastbootd"; exit 1; }
[ "$(var current-slot)" = a ] || { echo "ERROR: current slot is not a"; exit 1; }
[ "$(var unlocked)" = yes ] || { echo "ERROR: device is not unlocked"; exit 1; }
[ "$(var snapshot-update-status)" = none ] || { echo "ERROR: snapshot update in progress"; exit 1; }

for p in "${PARTS[@]}"; do
  want=$(printf '%d' "$(var "partition-size:$p")"); have=$(stat -Lc %s "$P/$p.img")
  [ "$want" = "$have" ] || { echo "ERROR: $p.img is $have bytes, partition is $want"; exit 1; }
  echo "  $p: $have bytes, size matches"
done

if [ "$COMMIT" != 1 ]; then echo "Dry run passed. Nothing was written."; exit 0; fi
for p in "${PARTS[@]}"; do
  echo "=== flashing $p"; fastboot flash "$p" "$P/$p.img"
done
echo "All images flashed. Not rebooted. To boot: remove the USB stick, then run: fastboot reboot"
