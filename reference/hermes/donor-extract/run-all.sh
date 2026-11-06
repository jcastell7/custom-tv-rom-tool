#!/usr/bin/env bash
# Run the full donor extraction end-to-end (phases 01 -> 05). READ-ONLY on the donor.
#
#   ./run-all.sh                     # dump everything except userdata, to firmware/donor-dump/
#   ./run-all.sh --include-userdata  # also dump userdata (huge + personal)
#   ./run-all.sh --out /path --yes   # custom dir, no prompts
#
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"
DIR="$(dirname "${BASH_SOURCE[0]}")"

section "DONOR EXTRACTION — full run"
log "Output : $OUTDIR"
log "adb    : $ADB ${SERIAL:+(serial $SERIAL)}"
log "userdata included: $([ "$INCLUDE_USERDATA" = 1 ] && echo yes || echo no)"
log "This is READ-ONLY on the donor. Nothing is written to the device."
echo >&2

# Re-exec each phase with the SAME arguments. Phases are idempotent: completed, checksum-verified
# dumps are skipped on re-run, so this is safe to resume after an interruption.
bash "$DIR/01-prereqs.sh"          "$@"
bash "$DIR/02-metadata.sh"         "$@"
bash "$DIR/03-partitions.sh"       "$@"
bash "$DIR/04-bootloader-region.sh" "$@"
bash "$DIR/05-verify.sh"           "$@"

section "ALL PHASES COMPLETE"
log "Everything is under: $OUTDIR"
log "Send me (or keep for the build session): $OUTDIR/REPORT.md + $OUTDIR/metadata/"
