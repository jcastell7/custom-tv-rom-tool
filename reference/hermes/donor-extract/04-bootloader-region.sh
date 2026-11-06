#!/usr/bin/env bash
# Phase 4: capture the raw bootloader region our original backup MISSED — boot0, u-boot, GPT.
# On Allwinner these live before the first GPT partition and/or in the eMMC hardware boot areas.
# READ-ONLY. Needs root.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

section "Phase 4 — raw bootloader region (boot0 / u-boot / GPT)"
require_host_tools
ensure_one_device
gain_root || die "root required for raw dumps (see README 'If adb root fails')."

DISK="$(detect_disk)"
B="$OUTDIR/bootloader-region"
log "eMMC base: $DISK"

# 1) eMMC hardware boot partitions (some Allwinner designs stage boot0 here).
for bp in "${DISK}boot0" "${DISK}boot1"; do
  if dev_stream ls "/dev/block/$bp" >/dev/null 2>&1; then
    dd_block "/dev/block/$bp" "$B/$bp.img" || true
  else
    log "no /dev/block/$bp (fine — not all eMMC expose boot HW partitions)"
  fi
done

# 2) First 64 MiB of the user area: protective MBR + primary GPT + boot0 (eGON) + u-boot package,
#    whatever the exact offsets are. This is the belt-and-suspenders capture of the boot blobs.
dd_block "/dev/block/$DISK" "$B/${DISK}-first-64MiB.img" "count=64"

# 3) Backup GPT lives in the last sectors — grab the tail too.
secs="$(dev_stream cat "/sys/class/block/$DISK/size" 2>/dev/null | tr -d '\r\n' || true)"
if [[ "$secs" =~ ^[0-9]+$ ]] && [ "$secs" -gt 0 ]; then
  total_mib=$(( secs * 512 / 1048576 ))
  skip=$(( total_mib - 16 ))
  log "disk is ${total_mib} MiB; grabbing last 16 MiB (backup GPT) at skip=${skip}"
  [ "$skip" -gt 0 ] && dd_block "/dev/block/$DISK" "$B/${DISK}-last-16MiB.img" "skip=${skip} count=16"
else
  warn "could not read /sys/class/block/$DISK/size; skipping backup-GPT tail"
fi

# 4) Scan the captured blobs for boot0 / u-boot signatures and report offsets (host-side, read-only).
section "Scanning captured region for boot0 / u-boot signatures"
for f in "$B/${DISK}boot0.img" "$B/${DISK}-first-64MiB.img"; do
  [ -f "$f" ] || continue
  log "signatures in $(basename "$f"):"
  for sig in 'eGON.BT0' 'eGON' 'uboot' 'U-Boot' 'TOC0.GLH' 'sunxi'; do
    off="$(grep -abom1 "$sig" "$f" 2>/dev/null | cut -d: -f1 || true)"
    [ -n "$off" ] && log "   '$sig' @ byte offset $off"
  done
done

log "Phase 4 done. Raw blobs in $B/ — these are the pieces the original dump lacked."
