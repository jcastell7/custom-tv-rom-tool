#!/usr/bin/env bash
# Phase 2: capture everything textual/structural we need to rebuild an image + diagnose. READ-ONLY.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

section "Phase 2 — metadata (layout, cmdline, DTB, props, logs)"
require_host_tools
ensure_one_device
gain_root || true

M="$OUTDIR/metadata"

# --- structural: the authoritative partition map + sizes (the pieces we lacked) ---
cap_text "$M/by-name.txt"      ls -l /dev/block/by-name
cap_text "$M/proc-partitions.txt" cat /proc/partitions
cap_text "$M/mounts.txt"       cat /proc/mounts
cap_text "$M/filesystems.txt"  cat /proc/filesystems
cap_text "$M/df.txt"           df -h

# --- boot/kernel config that explains our hang + feeds sys_partition rebuild ---
cap_text "$M/cmdline.txt"      cat /proc/cmdline
cap_text "$M/kernel-version.txt" cat /proc/version
cap_text "$M/cpuinfo.txt"      cat /proc/cpuinfo
cap_text "$M/selinux.txt"      getenforce

# --- full property dump (board/soc/avb/slot/mac identity) ---
cap_text "$M/getprop.txt"      getprop

# --- the live device tree (compare vs our dtbo/vendor_boot; also for board bringup) ---
cap_bin  "$M/fdt.dtb"          cat /sys/firmware/fdt
cap_bin  "$M/config.gz"        cat /proc/config.gz

# --- kernel log (root): shows the healthy boot path to diff against our failing one ---
cap_text "$M/dmesg.txt"        dmesg

# --- Allwinner key ladder / debug nodes if exposed (best-effort, harmless if absent) ---
cap_text "$M/sunxi-version.txt" cat /sys/class/sunxi_info/sys_info 2>/dev/null || true

log "Phase 2 done. Partition map: $M/by-name.txt"
