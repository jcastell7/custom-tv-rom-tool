# Shared helpers. Source this file; don't run it.
# ADB and FASTBOOT can be overridden, and SERIAL selects a device: SERIAL=abc ./10-preflight.sh
ADB=${ADB:-adb}; FASTBOOT=${FASTBOOT:-fastboot}
[ -n "${SERIAL:-}" ] && { ADB="$ADB -s $SERIAL"; FASTBOOT="$FASTBOOT -s $SERIAL"; }
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }
die()   { red "ERROR: $*" >&2; exit 1; }

# Runs a command on the device and strips the carriage returns adb can add.
ash()   { $ADB shell "$@" 2>/dev/null | tr -d '\r'; }

# Finds how to run commands as root. Sets ROOT_MODE to direct, su, or none. Changes no setting, but `adb root` can restart adbd,
# and `su` can show a prompt on the device if a root app is installed.
detect_root() {
  ROOT_MODE=none
  [ "$(ash id -u)" = 0 ] && { ROOT_MODE=direct; return; }
  $ADB root >/dev/null 2>&1 && { sleep 3; $ADB wait-for-device; [ "$(ash id -u)" = 0 ] && { ROOT_MODE=direct; return; }; }
  [ "$(ash "su -c 'id -u'")" = 0 ] && ROOT_MODE=su
}

# rsh 'cmd' runs cmd as root and strips carriage returns. Text only.
rsh() {
  case "$ROOT_MODE" in
    direct) ash "$1" ;;
    su)     ash "su -c '$1'" ;;
    *)      die "no root on this device" ;;
  esac
}

# rexec 'cmd' runs cmd as root with a binary-safe stdout, for dd. Never use rsh for binary data.
rexec() {
  case "$ROOT_MODE" in
    direct) $ADB exec-out "$1" ;;
    su)     $ADB exec-out "su -c '$1'" ;;
    *)      die "no root on this device" ;;
  esac
}

# Asks for an exact phrase, so a stray "y" or a script can't approve something dangerous.
confirm_phrase() {
  local phrase=$1; echo; yellow "Type exactly: $phrase"; local got; read -r got
  [ "$got" = "$phrase" ] || die "not confirmed"
}
