#!/usr/bin/env bash
# Phase 5: checksum manifest + human report + diff against our existing backup. Host-only, READ-ONLY.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

section "Phase 5 — verify, manifest, report"
require_host_tools

MAN="$OUTDIR/MANIFEST.sha256"
REP="$OUTDIR/REPORT.md"

log "building checksum manifest -> $(basename "$MAN")"
( cd "$OUTDIR" && find partitions bootloader-region metadata -type f ! -name '*.sha256' -print0 \
    | sort -z | xargs -0 sha256sum ) > "$MAN" 2>/dev/null || true

# Try to decompile the live DTB and gunzip the kernel config for convenience.
if [ -f "$OUTDIR/metadata/fdt.dtb" ] && command -v dtc >/dev/null 2>&1; then
  dtc -I dtb -O dts -o "$OUTDIR/metadata/fdt.dts" "$OUTDIR/metadata/fdt.dtb" 2>/dev/null \
    && log "decompiled DTB -> metadata/fdt.dts" || warn "dtc failed on fdt.dtb"
fi
if [ -f "$OUTDIR/metadata/config.gz" ]; then
  gunzip -kf "$OUTDIR/metadata/config.gz" 2>/dev/null && log "kernel config -> metadata/config" || true
fi

# What does the donor ADD that our original backup lacked?
existing="$REPO_ROOT/firmware/partitions"
new_list=""
if [ -d "$existing" ]; then
  for f in "$OUTDIR"/partitions/*.img "$OUTDIR"/bootloader-region/*.img; do
    [ -e "$f" ] || continue
    base="$(basename "$f" .img)"; stem="${base%_a}"
    if ! ls "$existing/${stem}"*.img >/dev/null 2>&1; then new_list+="  - ${base}\n"; fi
  done
fi

log "writing report -> $(basename "$REP")"
{
  echo "# Donor extraction report"
  echo
  echo "- Generated: $(date -Is)"
  echo "- Output dir: \`$OUTDIR\`"
  echo "- Root method: \`${ROOT_METHOD:-unknown}\`  | eMMC base: \`${DISK:-?}\`"
  echo
  echo "## Donor identity"
  echo '```'
  [ -f "$OUTDIR/metadata/identity.txt" ] && cat "$OUTDIR/metadata/identity.txt" || echo "(identity.txt missing — run 01)"
  echo '```'
  echo
  echo "## Partition images (name — size — sha256)"
  echo
  echo "| file | size | sha256 |"
  echo "|---|---|---|"
  for f in "$OUTDIR"/partitions/*.img "$OUTDIR"/bootloader-region/*.img; do
    [ -e "$f" ] || continue
    sz="$(du -h "$f" | cut -f1)"
    sh="$( [ -f "$f.sha256" ] && awk '{print $1}' "$f.sha256" || sha256sum "$f" | awk '{print $1}')"
    ft="$(file -b "$f" 2>/dev/null | cut -c1-40)"
    printf '| %s | %s | \`%s…\` |\n' "$(basename "$f") <br><sub>$ft</sub>" "$sz" "${sh:0:16}"
  done
  echo
  echo "## NEW vs our existing firmware/partitions backup"
  echo "(these are the pieces the original dump was missing — the whole reason for the donor)"
  echo
  if [ -n "$new_list" ]; then printf '%b' "$new_list"; else echo "  (none detected — check phase 3/4 ran with root)"; fi
  echo
  echo "## Key metadata captured"
  for m in by-name.txt proc-partitions.txt cmdline.txt getprop.txt fdt.dtb fdt.dts dmesg.txt config; do
    [ -e "$OUTDIR/metadata/$m" ] && echo "  - metadata/$m"
  done
  echo
  echo "## Next step"
  echo "Hand this folder back to the build session. With boot0 + u-boot + the GPT/by-name layout"
  echo "we can reconstruct \`sys_partition.fex\` and pack a PhoenixSuit image, and diff the donor's"
  echo "healthy boot (dmesg/cmdline/fdt) against the bricked unit's UART log."
} > "$REP"

cat "$REP" >&2
log "Phase 5 done. See $REP and $MAN"
