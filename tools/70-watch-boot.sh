#!/usr/bin/env bash
# Run right after a reboot. Follows the device until it finishes booting or returns to fastboot, saves logs, runs triage.
# Usage: 70-watch-boot.sh [LOG_DIR] [MINUTES]      Default 15 minutes: a first boot on a slow device can take several.
set -uo pipefail
. "$(dirname "$0")/common.sh"
DIR=${1:-boot-logs-$(date +%H%M%S)}; MIN=${2:-15}; mkdir -p "$DIR"
end=$(( $(date +%s) + MIN*60 )); last=
while [ "$(date +%s)" -lt "$end" ]; do
  if [ "$(timeout 3 $ADB get-state 2>/dev/null)" = device ]; then s=adb
  elif [ -n "$(timeout 3 $FASTBOOT devices 2>/dev/null)" ]; then s=fastboot
  else s=none; fi
  [ "$s" = "$last" ] || { echo "$(date +%T) state: $s"; last=$s; }
  case $s in
    adb)
      [ "$(ash getprop sys.boot_completed)" = 1 ] && { green "$(date +%T) boot completed"; sleep 30; break; }
      # Save partial logs too, because the device may reboot soon.
      timeout 25 $ADB logcat -d > "$DIR/logcat-partial.txt" 2>/dev/null ;;
    fastboot)
      red "$(date +%T) device is in fastboot: the boot failed and the fallback worked. Read your UART log, or logcat from the failed boot if you saved it."
      [ -s "$DIR/logcat-partial.txt" ] && python3 -I "$TOOLS_DIR/75-triage.py" "$DIR/logcat-partial.txt"
      exit 2 ;;
  esac
  sleep 5
done
if [ "$s" != adb ]; then
  red "No adb after $MIN minutes (state: $s). Use UART if wired, wait for the boot watchdog, then see docs/05."
  exit 3
fi
timeout 40 $ADB logcat -d > "$DIR/logcat.txt" 2>/dev/null
timeout 20 $ADB logcat -d -b crash > "$DIR/crash.txt" 2>/dev/null
timeout 20 $ADB logcat -d -b events > "$DIR/events.txt" 2>/dev/null
ash dmesg > "$DIR/dmesg.txt"
{ ash uptime; ash getprop sys.boot_completed; ash cat /proc/swaps; ash cat /proc/meminfo | grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree'; ash getprop | grep -E 'init.svc' ; } > "$DIR/state.txt"
$ADB exec-out screencap -p > "$DIR/screen.png" 2>/dev/null
echo "Logs and a screenshot are in $DIR/. A black screenshot doesn't always mean a black screen: check with the user."
python3 -I "$TOOLS_DIR/75-triage.py" "$DIR/logcat.txt" "$DIR/crash.txt" "$DIR/dmesg.txt" "$DIR/events.txt"
