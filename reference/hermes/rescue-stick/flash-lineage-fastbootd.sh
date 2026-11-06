#!/usr/bin/env bash
# Flash the LineageOS build to slot _a over fastbootd. Stops at the first failure.
# Doesn't reboot, and doesn't wipe userdata or metadata. Never touches boot0, u-boot, env, misc, GPT or frp.
set -euo pipefail
O=${1:-/path/to/lineage-21.0/out/target/product/hermes}
var() { timeout 15 fastboot getvar "$1" 2>&1 | sed -n "s/^$1: *//p" | head -1; }
[ "$(timeout 15 fastboot devices | wc -l)" = 1 ] || { echo "ERROR: need exactly one fastboot device"; exit 1; }
for kv in is-userspace=yes current-slot=a unlocked=yes snapshot-update-status=none; do
  [ "$(var "${kv%%=*}")" = "${kv#*=}" ] || { echo "ERROR: expected $kv"; exit 1; }
done
# vendor_boot name must be "arm", or u-boot may enter this 32-bit kernel in AArch64 mode (docs/15).
[ "$(dd if="$O/vendor_boot.img" bs=1 skip=$((0x820)) count=3 2>/dev/null)" = arm ] || { echo "ERROR: vendor_boot.img name is not arm"; exit 1; }
# header_version must be 4 in init_boot, the fix for the known u-boot stop (docs/15).
[ "$(od -An -tu4 -j40 -N4 "$O/init_boot.img" | tr -d ' ')" = 4 ] || { echo "ERROR: init_boot.img is not header v4"; exit 1; }
for img in vendor_boot init_boot boot dtbo vbmeta_vendor vbmeta_system vbmeta; do
  have=$(stat -Lc %s "$O/$img.img"); max=$(printf '%d' "$(var "partition-size:${img}_a")")
  [ "$have" -le "$max" ] || { echo "ERROR: $img.img is larger than its partition"; exit 1; }
done
# Set INIT_BOOT_IMG to a Magisk-patched image to keep root (docs/18). The default image removes root.
for img in vendor_boot init_boot boot dtbo vbmeta_vendor vbmeta_system vbmeta; do
  src="$O/$img.img"
  [ "$img" = init_boot ] && src="${INIT_BOOT_IMG:-$src}"
  echo "=== flashing ${img}_a from $src"; fastboot flash "${img}_a" "$src"
done
echo "=== flashing super"; fastboot flash super "$O/super.img"
echo "All images flashed. Not rebooted, nothing wiped."
