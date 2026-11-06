#!/usr/bin/env bash
# Phase 1: verify host + donor, print the donor's identity, probe root. READ-ONLY.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

section "Phase 1 — prerequisites & donor identity"
require_host_tools
ensure_one_device

ident="$OUTDIR/metadata/identity.txt"
log "reading donor identity -> $(basename "$ident")"
{
  echo "# captured $(date -Is)"
  for p in ro.product.brand ro.product.model ro.product.name ro.product.device \
           ro.board.platform ro.hardware ro.boot.hardware ro.build.fingerprint \
           ro.build.version.release ro.build.version.sdk ro.boot.flash.locked \
           ro.boot.verifiedbootstate ro.boot.slot_suffix ro.serialno; do
    printf '%-34s = %s\n' "$p" "$(_adb exec-out getprop "$p" 2>/dev/null | tr -d '\r')"
  done
} > "$ident"
cat "$ident" >&2

echo >&2
log "Confirm this is the DONOR (a sacrificial/working twin), NOT any device you care about."
log "Everything this suite does is read-only, but double-check the model matches the bricked unit."

gain_root || true   # non-fatal here; phases 2 warns/limits accordingly

if [ "$ROOT_METHOD" = none ]; then
  warn "Root unavailable → phases 03/04 (block dumps) will not work. See README."
else
  log "Root method: $ROOT_METHOD. Ready for full extraction."
  detect_disk >/dev/null
  log "eMMC base device detected: $DISK"
fi
log "Phase 1 done."
