#!/usr/bin/env bash
# READ-ONLY. Run first on any new device. Saves a device report and answers: is it safe to continue, and what must be backed up?
# Usage: 10-preflight.sh [OUTPUT_DIR]     Default output: ./device-report-<serial>/
set -uo pipefail
. "$(dirname "$0")/common.sh"
[ "$($ADB get-state 2>/dev/null)" = device ] || die "no adb device. Check the cable, USB debugging and the authorization prompt."
serial=$($ADB get-serialno | tr -d '\r')
OUT=${1:-device-report-$serial}; mkdir -p "$OUT"
detect_root
p() { ash getprop "$1"; }

ash getprop > "$OUT/getprop.txt"
ash cat /proc/partitions > "$OUT/proc-partitions.txt"
ash cat /proc/version > "$OUT/kernel-version.txt"
ash uname -m > "$OUT/uname-m.txt"
ash cat /proc/cpuinfo > "$OUT/cpuinfo.txt"
ash cat /proc/meminfo > "$OUT/meminfo.txt"
ash ls -l /dev/block/by-name > "$OUT/by-name.txt"
[ -s "$OUT/by-name.txt" ] || ash "ls -l /dev/block/platform/*/by-name /dev/block/platform/*/*/by-name" > "$OUT/by-name.txt"
ash pm list packages -f > "$OUT/packages.txt"
ash pm list features > "$OUT/features.txt"
ash lsmod > "$OUT/lsmod.txt"
ash getevent -pl > "$OUT/input-devices.txt"
ash dumpsys sensorservice > "$OUT/sensors.txt"
ash lshal > "$OUT/lshal.txt"
ash service list > "$OUT/service-list.txt"
ash cat /proc/mounts > "$OUT/mounts.txt"
if [ "$ROOT_MODE" != none ]; then
  rsh 'cat /proc/cmdline' > "$OUT/cmdline.txt"
  rsh 'cat /proc/bootconfig' > "$OUT/bootconfig.txt"
  rsh dmesg > "$OUT/dmesg.txt"
  rsh 'getenforce' > "$OUT/selinux.txt"
fi

{
echo "=== Identity ==="
echo "model:        $(p ro.product.model) / device $(p ro.product.device) / board $(p ro.product.board)"
echo "SoC:          $(p ro.soc.manufacturer) $(p ro.soc.model) / platform $(p ro.board.platform) / hardware $(p ro.hardware)"
echo "Android:      $(p ro.build.version.release) (SDK $(p ro.build.version.sdk)), first API $(p ro.product.first_api_level) / vendor API $(p ro.board.first_api_level)"
echo "fingerprint:  $(p ro.build.fingerprint)"
echo "kernel:       $(cat "$OUT/kernel-version.txt" | cut -c1-90)"
echo "kernel arch:  $(cat "$OUT/uname-m.txt")   ABIs: $(p ro.product.cpu.abilist)"
echo "zygote:       $(p ro.zygote)"
echo "RAM:          $(awk '/MemTotal/{print int($2/1024)" MiB visible"}' "$OUT/meminfo.txt"), low_ram=$(p ro.config.low_ram)"
echo
echo "=== Boot and partitions ==="
echo "A/B:          slot_suffix='$(p ro.boot.slot_suffix)' virtual_ab=$(p ro.virtual_ab.enabled)"
echo "dynamic:      $(p ro.boot.dynamic_partitions) retrofit=$(p ro.boot.dynamic_partitions_retrofit)"
echo "unlocked?:    flash.locked=$(p ro.boot.flash.locked) verifiedbootstate=$(p ro.boot.verifiedbootstate) oem_unlock_supported=$(p ro.oem_unlock_supported)"
echo "recovery:     partition=$(grep -cE ' recovery(_a)? ' "$OUT/by-name.txt")  in-vendor-boot-style: vendor_boot=$(grep -c ' vendor_boot' "$OUT/by-name.txt") init_boot=$(grep -c ' init_boot' "$OUT/by-name.txt")"
echo "VNDK:         ro.vndk.version=$(p ro.vndk.version)  (if set, stock libraries come from a VNDK APEX: see docs/04)"
echo "root:         $ROOT_MODE    SELinux: $(cat "$OUT/selinux.txt" 2>/dev/null)"
echo
echo "=== Storage ==="
awk 'NR>2 && $4!~/^(loop|ram|zram|dm-|sr)/ && $4!~/[0-9]p[0-9]+$/ && $4!~/^sd[a-z][0-9]+$/ {printf "%-16s %7d MiB\n",$4,$3/1024}' "$OUT/proc-partitions.txt"
echo
echo "=== Things to look for in stock before changing anything (docs/06) ==="
grep -iE 'keystone|projector|focus|tvinput|hdmi|factory|video.?input|livetv|source' "$OUT/packages.txt" | sed 's/^package://' | cut -c1-100
} | tee "$OUT/REPORT.txt"

echo
echo "=== Go / no-go ==="
ok=1
[ "$(p ro.boot.flash.locked)" = 1 ] && { red "STOP: bootloader looks locked (ro.boot.flash.locked=1)."; ok=0; }
[ "$ROOT_MODE" = none ] && { red "STOP: no root. A full backup needs root (or a root recovery). See docs/02."; ok=0; }
[ "$(p ro.boot.verifiedbootstate)" = green ] && yellow "WARN: verifiedbootstate=green usually means locked. Confirm unlock before planning any flash."
[ "$ROOT_MODE" = su ] && yellow "NOTE: root comes from su. The backup works, but check su still works from recovery if you rely on it."
[ "$ok" = 1 ] && green "Continue to 20-backup.sh. Do NOT flash anything yet." || red "Fix the STOP items first."
echo "Report saved in $OUT/. Read docs/03: you need a tested way back BEFORE the first flash."
[ "$ok" = 1 ]
