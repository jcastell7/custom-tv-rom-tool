#!/usr/bin/env bash
# READ-ONLY on the device: only dd if=, cat and getprop. A backup lowers risk but doesn't remove it: see DISCLAIMER.md.
#  Copies everything a restore could need and verifies each copy
# against a SHA-256 computed ON THE DEVICE. Resumable: a verified file is skipped on the next run.
#
# Usage: 20-backup.sh OUTPUT_DIR [--include-userdata] [--skip NAME]...
#
# Copies: every by-name partition, and for each physical disk the regions outside any partition (the head and tail hold
# the bootloader and GPT on many SoCs), plus eMMC hardware boot areas (mmcblkXbootN), which many SoCs boot from.
# Never copied: RPMB, which can't be read this way, so keys stored there can't be backed up.
set -uo pipefail
. "$(dirname "$0")/common.sh"
[ $# -ge 1 ] || die "usage: $0 OUTPUT_DIR [--include-userdata] [--skip NAME]..."
OUT=$1; shift; INCLUDE_USERDATA=0; SKIP=" "
while [ $# -gt 0 ]; do case $1 in
  --include-userdata) INCLUDE_USERDATA=1 ;;
  --skip) shift; SKIP="$SKIP$1 " ;;
  *) die "unknown option $1" ;;
esac; shift; done
mkdir -p "$OUT/layout"; OUT=$(cd "$OUT" && pwd)
[ "$($ADB get-state 2>/dev/null)" = device ] || die "needs a device in adb (booted Android or a root recovery)"
detect_root; [ "$ROOT_MODE" != none ] || die "needs root. See docs/02-BACKUP.md for what to do without it."
LOG=$OUT/backup.log; SUMS=$OUT/SHA256SUMS; touch "$SUMS"
fail=0; say() { echo "$*" | tee -a "$LOG"; }

# dump NAME DEVICE [dd args]. Hash on device, copy, hash here, compare, retry once.
dump() {
  local name=$1 dev=$2 args=${3:-} f="$OUT/$1.img" want have try
  if grep -q "  $name.img\$" "$SUMS" && [ -f "$f" ] && [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$(grep "  $name.img\$" "$SUMS" | cut -d' ' -f1)" ]; then
    say "SKIP $name (already verified)"; return
  fi
  for try in 1 2; do
    want=$(rsh "dd if=$dev bs=1048576 $args 2>/dev/null | sha256sum" | awk '{print $1}')
    rexec "dd if=$dev bs=1048576 $args 2>/dev/null" > "$f"
    have=$(sha256sum "$f" | cut -d' ' -f1)
    if [ -n "$want" ] && [ "$want" = "$have" ]; then
      sed -i "/  $name.img\$/d" "$SUMS"; echo "$have  $name.img" >> "$SUMS"
      say "OK   $name $(stat -c %s "$f") bytes"; return
    fi
    say "RETRY $name (device=$want local=$have)"
  done
  say "FAIL $name"; fail=1
}

# Layout and identity first: small, and useful even if a later copy fails.
ash getprop > "$OUT/layout/getprop.txt"
ash cat /proc/partitions > "$OUT/layout/proc-partitions.txt"
rsh 'cat /proc/cmdline' > "$OUT/layout/cmdline.txt"
rsh 'cat /proc/bootconfig' > "$OUT/layout/bootconfig.txt"
rsh 'dmesg' > "$OUT/layout/dmesg.txt"
rsh 'cat /proc/device-tree/model' > "$OUT/layout/dt-model.txt"
BYNAME=$(rsh 'for d in /dev/block/by-name /dev/block/platform/*/by-name /dev/block/platform/*/*/by-name /dev/block/bootdevice/by-name; do [ -d $d ] && { echo $d; break; }; done' | head -1)
[ -n "$BYNAME" ] || say "WARN: no by-name directory. Partition names will come from /proc/partitions only."
rsh "ls -l $BYNAME" > "$OUT/layout/by-name.txt"
rsh 'cat /proc/mounts' > "$OUT/layout/mounts.txt"

# Physical disks and their sizes.
DISKS=$(awk 'NR>2 && $4~/^(mmcblk[0-9]+|sd[a-z]|nvme[0-9]+n[0-9]+)$/ {print $4}' "$OUT/layout/proc-partitions.txt")
[ -n "$DISKS" ] || say "WARN: no standard disk found in /proc/partitions. Raw NAND devices need a manual plan: see docs/02-BACKUP.md."
free_kb=$(df -Pk "$OUT" | awk 'NR==2{print $4}'); total_kb=$(awk 'NR>2 && $4~/^(mmcblk[0-9]+|sd[a-z])$/{s+=$3} END{print s+0}' "$OUT/layout/proc-partitions.txt")
say "Free here: $((free_kb/1024)) MiB. Device disks total: $((total_kb/1024)) MiB."
[ "$free_kb" -gt "$total_kb" ] || say "WARN: less free space here than the disk size. Check the total before relying on this."

for d in $DISKS; do
  # Partition table and every region outside a partition.
  secs=$(rsh "cat /sys/class/block/$d/size"); mib=$((secs*512/1048576))
  rsh "for p in /sys/class/block/$d/${d}p* /sys/class/block/$d/$d[0-9]*; do [ -f \$p/start ] && echo \$(basename \$p) \$(cat \$p/start) \$(cat \$p/size); done" | sort -k2 -n > "$OUT/layout/$d-partitions.txt"
  first=$(awk 'NR==1{print $2}' "$OUT/layout/$d-partitions.txt"); first=${first:-131072}
  head_mib=$(( (first*512 + 1048575) / 1048576 )); [ "$head_mib" -lt 64 ] && head_mib=64
  say "--- $d: ${mib} MiB, first partition at sector $first; copying the first $head_mib MiB and last 16 MiB"
  dump "disk-$d-head" "/dev/block/$d" "count=$head_mib"
  dump "disk-$d-tail" "/dev/block/$d" "skip=$((mib-16))"
  for hw in boot0 boot1; do
    rsh "[ -b /dev/block/${d}$hw ] && echo y" | grep -q y && dump "disk-$d$hw" "/dev/block/${d}$hw"
  done
done

# Every named partition, small ones first so a failure later still leaves the critical ones.
names=$(awk '{for(i=1;i<NF;i++) if($(i)=="->") print $(i-1)}' "$OUT/layout/by-name.txt")
[ -n "$names" ] || { say "FAIL: found no named partitions in $BYNAME"; fail=1; }
for n in $names; do
  dev=$BYNAME/$n
  sz=$(rsh "blockdev --getsize64 $dev"); echo "${sz:-0} $n"
done | sort -n > "$OUT/layout/partition-sizes.txt"
while read -r sz n; do
  case "$SKIP" in *" $n "*) say "SKIP $n (--skip)"; continue ;; esac
  # by-name can include whole-disk aliases: skip them, the disk regions above cover these.
  case "$n" in mmcblk*|sd?) say "SKIP $n (whole disk alias)"; continue ;; esac
  case "$n" in userdata|userdata_*|data)
    [ "$INCLUDE_USERDATA" = 1 ] || { say "SKIP $n (personal data; pass --include-userdata)"; continue; } ;;
  esac
  dump "$n" "$BYNAME/$n"
done < "$OUT/layout/partition-sizes.txt"

cp "$(dirname "$0")/21-check-backup.py" "$OUT/" 2>/dev/null
# Never report success without having copied the partitions the script set out to copy.
copied=$(grep -cvE '  disk-' "$SUMS")
[ "$copied" -gt 0 ] || { say "FAIL: no named partition was copied"; fail=1; }
if [ "$fail" = 0 ]; then
  green "All copies verified. Now run: tools/21-check-backup.py $OUT"
  green "Then make a second copy on another disk. Keep this private: it holds per-device keys and MAC addresses."
else
  red "Some copies FAILED. Re-run this script, which retries only what's missing. Don't flash anything until it passes."; exit 1
fi
