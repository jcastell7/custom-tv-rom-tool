#!/usr/bin/env bash
# Read-only copy of the eMMC over adb from root recovery into firmware/partition-copies/. See docs/13.
# Every read is `dd if=`; nothing is written to the device. Skips super and userdata unless named as arguments.
set -uo pipefail
OUT="$(cd "$(dirname "$0")/../.." && pwd)/firmware/partition-copies"; mkdir -p "$OUT"; cd "$OUT"
DISK=/dev/block/mmcblk0; fail=0
copy() { # name device extra-dd-args
  local n=$1 dev=$2 args=${3:-}
  local want; want=$(adb shell "dd if=$dev bs=1M $args 2>/dev/null | sha256sum" | awk '{print $1}')
  adb exec-out "dd if=$dev bs=1M $args 2>/dev/null" > "$n.img"
  local have; have=$(sha256sum "$n.img" | awk '{print $1}')
  if [ -n "$want" ] && [ "$want" = "$have" ]; then echo "OK  $n $(stat -c %s "$n.img") $have"; echo "$have  $n.img" >> SHA256SUMS.txt.new
  else echo "BAD $n device=$want local=$have"; fail=1; fi
}
: > SHA256SUMS.txt.new
adb shell "getprop ro.bootmode; cat /proc/partitions; ls -l /dev/block/by-name" > device-layout.txt 2>&1
if [ $# -gt 0 ]; then for p in "$@"; do copy "$p" "/dev/block/by-name/$p"; done
else
  secs=$(adb shell cat /sys/class/block/mmcblk0/size | tr -d '\r\n'); mib=$((secs*512/1048576))
  copy emmc-first-64MiB "$DISK" "count=64"
  copy emmc-last-16MiB "$DISK" "skip=$((mib-16))"
  for p in bootloader_a bootloader_b env_a env_b boot_a boot_b vendor_boot_a vendor_boot_b init_boot_a init_boot_b \
           dtbo_a dtbo_b vbmeta_a vbmeta_b vbmeta_system_a vbmeta_system_b vbmeta_vendor_a vbmeta_vendor_b \
           misc frp metadata empty treadahead private media_data customapp Reserve0_a Reserve0_b; do
    copy "$p" "/dev/block/by-name/$p"
  done
fi
cat SHA256SUMS.txt.new >> SHA256SUMS.txt; rm -f SHA256SUMS.txt.new
[ "$fail" = 0 ] && echo "ALL OK" || { echo "SOME COPIES FAILED"; exit 1; }
