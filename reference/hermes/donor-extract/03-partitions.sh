#!/usr/bin/env bash
# Phase 3: dump every named GPT partition (the full data set). READ-ONLY. Needs root.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

section "Phase 3 — named partitions (/dev/block/by-name/*)"
require_host_tools
ensure_one_device
gain_root || die "root required for partition dumps (see README 'If adb root fails')."

BN="$OUTDIR/metadata/by-name.txt"
[ -s "$BN" ] || cap_text "$BN" ls -l /dev/block/by-name
[ -s "$BN" ] || die "could not read /dev/block/by-name — cannot enumerate partitions."

mapfile -t NAMES < <(awk '/->/{print $(NF-2)}' "$BN" | sort -u)
[ "${#NAMES[@]}" -gt 0 ] || die "no partitions parsed from $BN"
log "found ${#NAMES[@]} named partitions"

confirm "About to dump ${#NAMES[@]} partitions (incl. 'super', can be multi-GB) to $OUTDIR/partitions. Continue?"

for name in "${NAMES[@]}"; do
  case "$name" in
    ""|.|..) continue ;;
    userdata)
      if [ "$INCLUDE_USERDATA" != 1 ]; then
        log "skip userdata (personal + huge; pass --include-userdata to include)"; continue
      fi ;;
    rpmb|*rpmb*) log "skip $name (replay-protected, not dumpable/needed)"; continue ;;
  esac
  dd_block "/dev/block/by-name/$name" "$OUTDIR/partitions/$name.img" || warn "could not dump $name"
done

log "Phase 3 done. Images in $OUTDIR/partitions/"
