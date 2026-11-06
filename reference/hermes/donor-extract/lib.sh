#!/usr/bin/env bash
# Shared library for donor-projector extraction.
# READ-ONLY on the donor: every device operation here is dd/cat/getprop. Nothing is written to the donor.
# Source this from the phase wrappers (01..05) and run-all.sh.

set -euo pipefail

# ---- locate repo + defaults ------------------------------------------------
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$LIB_DIR/../.." && pwd)"

ADB="${ADB:-adb}"                      # override with ADB=/path/to/adb (e.g. tooling/platform-tools/adb)
SERIAL="${SERIAL:-}"                   # set by --serial; empty = single-device auto
OUTDIR="${OUTDIR:-$REPO_ROOT/firmware/donor-dump}"
INCLUDE_USERDATA="${INCLUDE_USERDATA:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
ROOT_METHOD="${ROOT_METHOD:-unknown}"  # adb_root | su | su0 | none
DISK="${DISK:-}"                       # eMMC base, e.g. mmcblk0 (auto-detected)
LOGFILE="${LOGFILE:-}"

# ---- logging ---------------------------------------------------------------
# All log output goes to STDERR so it never contaminates binary dumps captured on STDOUT.
_c() { [ -t 2 ] && printf '%s' "$1" || true; }
log()     { printf '%s[%s] %s%s\n' "$(_c $'\e[36m')" "$(date +%H:%M:%S)" "$*" "$(_c $'\e[0m')" >&2; [ -n "$LOGFILE" ] && printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >>"$LOGFILE" || true; }
warn()    { printf '%s[%s] WARN: %s%s\n' "$(_c $'\e[33m')" "$(date +%H:%M:%S)" "$*" "$(_c $'\e[0m')" >&2; [ -n "$LOGFILE" ] && printf '[%s] WARN: %s\n' "$(date +%H:%M:%S)" "$*" >>"$LOGFILE" || true; }
die()     { printf '%s[%s] FATAL: %s%s\n' "$(_c $'\e[31m')" "$(date +%H:%M:%S)" "$*" "$(_c $'\e[0m')" >&2; exit 1; }
section() { printf '\n%s===== %s =====%s\n' "$(_c $'\e[1m')" "$*" "$(_c $'\e[0m')" >&2; [ -n "$LOGFILE" ] && printf '\n===== %s =====\n' "$*" >>"$LOGFILE" || true; }

# ---- argument parsing (shared by every wrapper) ----------------------------
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --out)              OUTDIR="$2"; shift 2 ;;
      --serial)           SERIAL="$2"; shift 2 ;;
      --adb)              ADB="$2"; shift 2 ;;
      --include-userdata) INCLUDE_USERDATA=1; shift ;;
      --yes|-y)           ASSUME_YES=1; shift ;;
      -h|--help)          _usage; exit 0 ;;
      *)                  die "unknown argument: $1 (try --help)" ;;
    esac
  done
  mkdir -p "$OUTDIR"/{partitions,bootloader-region,metadata}
  LOGFILE="$OUTDIR/extract.log"
  export OUTDIR SERIAL ADB INCLUDE_USERDATA ASSUME_YES LOGFILE
}

_usage() {
  cat >&2 <<EOF
Usage: $(basename "${0:-run-all.sh}") [options]
  --out DIR            output directory      (default: $REPO_ROOT/firmware/donor-dump)
  --serial SERIAL      target a specific adb device
  --adb PATH           adb binary to use     (default: adb on PATH)
  --include-userdata   also dump userdata (huge + personal; off by default)
  --yes, -y            don't prompt before large dumps
  -h, --help           this help
EOF
}

# ---- adb plumbing ----------------------------------------------------------
_adb() { "$ADB" ${SERIAL:+-s "$SERIAL"} "$@"; }

require_host_tools() {
  command -v "$ADB" >/dev/null 2>&1 || die "adb not found ('$ADB'). Install platform-tools or pass --adb PATH."
  command -v sha256sum >/dev/null 2>&1 || die "sha256sum not found."
}

ensure_one_device() {
  local n
  n="$(_adb devices | awk 'NR>1 && $2=="device"{c++} END{print c+0}')"
  [ "$n" -ge 1 ] || die "no adb device in 'device' state. Enable USB debugging on the donor (Settings > Developer options) and authorize this PC."
  if [ -z "$SERIAL" ] && [ "$n" -gt 1 ]; then
    _adb devices >&2
    die "multiple devices connected; pass --serial SERIAL to pick the donor."
  fi
}

# Run a command on the donor as root, streaming its STDOUT to our STDOUT (binary-safe).
dev_stream() {
  case "$ROOT_METHOD" in
    adb_root) _adb exec-out "$@" ;;
    su)       _adb exec-out su -c "$*" ;;
    su0)      _adb exec-out su 0 "$@" ;;
    none)     _adb exec-out "$@" ;;   # best effort without root (works for world-readable paths)
    *)        die "root not probed yet (call gain_root)";;
  esac
}

gain_root() {
  section "Acquiring root on the donor (needed for block-level dumps)"
  _adb root >/dev/null 2>&1 || true
  _adb wait-for-device
  sleep 2
  if [ "$(_adb exec-out id -u 2>/dev/null | tr -d '\r\n')" = "0" ]; then
    ROOT_METHOD=adb_root; export ROOT_METHOD; log "root OK via adbd (uid=0)"; return 0
  fi
  if [ "$(_adb exec-out su -c id -u 2>/dev/null | tr -d '\r\n')" = "0" ]; then
    ROOT_METHOD=su; export ROOT_METHOD; log "root OK via 'su -c'"; return 0
  fi
  if [ "$(_adb exec-out su 0 id -u 2>/dev/null | tr -d '\r\n')" = "0" ]; then
    ROOT_METHOD=su0; export ROOT_METHOD; log "root OK via 'su 0'"; return 0
  fi
  ROOT_METHOD=none; export ROOT_METHOD
  warn "NO ROOT on the donor. Metadata that is world-readable will still be captured,"
  warn "but block-level partition/bootloader dumps CANNOT run. See README 'If adb root fails'."
  return 1
}

# ---- capture helpers -------------------------------------------------------
# Text capture (root if available, else plain). Keep commands simple (no pipes/globs → quoting-safe).
cap_text() { # cap_text <outfile> <cmd> [args...]
  local out="$1"; shift
  if dev_stream "$@" 2>/dev/null | tr -d '\r' > "$out" && [ -s "$out" ]; then
    log "meta: $(basename "$out")"
  else
    _adb exec-out "$@" 2>/dev/null | tr -d '\r' > "$out" || true
    if [ -s "$out" ]; then log "meta (no-root): $(basename "$out")"; else warn "empty, dropped: $(basename "$out")"; rm -f "$out"; fi
  fi
}

cap_bin() { # cap_bin <outfile> <cmd> [args...]  (binary, e.g. cat /sys/firmware/fdt)
  local out="$1"; shift
  if dev_stream "$@" > "$out" 2>/dev/null && [ -s "$out" ]; then
    log "meta(bin): $(basename "$out") ($(du -h "$out"|cut -f1))"
  else
    _adb exec-out "$@" > "$out" 2>/dev/null || true
    if [ -s "$out" ]; then log "meta(bin,no-root): $(basename "$out")"; else warn "empty, dropped: $(basename "$out")"; rm -f "$out"; fi
  fi
}

# Dump a block device to a file with checksum + resume-skip. extra = extra dd args string.
dd_block() { # dd_block <remote_block_path> <outfile> [extra_dd_args]
  local rpath="$1" out="$2" extra="${3:-}"
  if [ -f "$out" ] && [ -f "$out.sha256" ] && (cd "$(dirname "$out")" && sha256sum -c "$(basename "$out").sha256" >/dev/null 2>&1); then
    log "skip (already dumped & verified): $(basename "$out")"; return 0
  fi
  [ "$ROOT_METHOD" = none ] && { warn "no root; cannot dump $rpath"; return 1; }
  log "dumping $rpath -> $(basename "$out")"
  if dev_stream dd if="$rpath" bs=1048576 $extra > "$out" 2>>"$LOGFILE"; then
    ( cd "$(dirname "$out")" && sha256sum "$(basename "$out")" > "$(basename "$out").sha256" )
    log "  ok  $(du -h "$out"|cut -f1)  $(awk '{print $1}' "$out.sha256")"
  else
    warn "dd FAILED: $rpath"; rm -f "$out"; return 1
  fi
}

confirm() { # confirm "<prompt>"
  [ "$ASSUME_YES" = 1 ] && return 0
  printf '%s [y/N] ' "$1" >&2
  local a; read -r a || true
  case "$a" in y|Y|yes|YES) return 0;; *) die "aborted by user";; esac
}

# Detect the eMMC base device (e.g. mmcblk0) from a by-name symlink target.
detect_disk() {
  [ -n "$DISK" ] && { echo "$DISK"; return; }
  local bn="$OUTDIR/metadata/by-name.txt" tgt=""
  [ -s "$bn" ] || cap_text "$bn" ls -l /dev/block/by-name
  # ls -l lines look like:  lrwxrwxrwx ... misc -> /dev/block/mmcblk0p5  (or ../../mmcblk0p5)
  tgt="$(awk '/->/{print $NF}' "$bn" 2>/dev/null | grep -m1 -oE '[a-z]+[0-9]+p[0-9]+' || true)"
  if [ -n "$tgt" ]; then
    DISK="$(echo "$tgt" | sed -E 's/p[0-9]+$//')"
  else
    DISK="mmcblk0"; warn "could not auto-detect eMMC base; defaulting to $DISK"
  fi
  export DISK; echo "$DISK"
}
