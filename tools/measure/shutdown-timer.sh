#!/usr/bin/env bash
# Times a real power-off: sends the shutdown over adb, then you press SPACE when you hear the fan stop.
#
# Usage: shutdown-timer.sh [--svc] [--dry-run] [-y]
#   default    press the power key twice, as on the remote: the first opens the power menu, the second confirms it
#   --svc      use "svc power shutdown" instead of the power menu
#   --dry-run  run the timer without shutting anything down, to try the keys
#   -y         don't ask for confirmation
#
# Prints two times: from sending the command, and from the moment Android's ShutdownThread started, read from the
# device log. The second leaves out adb's and the shell command's own startup. Results are added to
# shutdown-times.csv next to this script.
#
# This really powers the device off. Someone has to turn it back on.
set -u

method=menu dry=0 yes=0
for arg in "$@"; do
  case "$arg" in
    --svc) method=svc ;;
    --dry-run) dry=1 ;;
    -y) yes=1 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (see --help)"; exit 2 ;;
  esac
done

command -v adb >/dev/null || { echo "ERROR: adb isn't installed or isn't on PATH"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
csv="$here/shutdown-times.csv"
work=$(mktemp -d)
logpid='' pollpid=''
cleanup() {
  [ -n "$logpid" ] && kill "$logpid" 2>/dev/null
  [ -n "$pollpid" ] && kill "$pollpid" 2>/dev/null
  stty echo icanon 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT INT TERM

now() { date +%s.%N; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }

if [ "$dry" = 0 ]; then
  n=$(adb devices | awk 'NR > 1 && $2 == "device"' | wc -l)
  [ "$n" = 1 ] || { echo "ERROR: need exactly one device in 'adb devices', found $n"; exit 1; }
  build=$(adb shell getprop ro.build.version.incremental 2>/dev/null | tr -d '\r')
  echo "Device found. Build: ${build:-unknown}. Method: $method."
  if [ "$yes" = 0 ]; then
    printf 'This will POWER OFF the device, and someone will have to turn it back on. Continue? [y/N] '
    read -r answer
    [ "$answer" = y ] || [ "$answer" = Y ] || { echo "Cancelled."; exit 0; }
  fi

  # Note the host time when ShutdownThread starts, and when adb loses the device.
  adb logcat -c 2>/dev/null
  ( adb logcat -s ShutdownThread:I 2>/dev/null | while IFS= read -r line; do
      printf '%s %s\n' "$(now)" "$line"
    done > "$work/shutdown.log" ) &
  logpid=$!
  ( while [ "$(adb get-state 2>/dev/null)" = device ]; do sleep 0.2; done; now > "$work/adb_gone" ) &
  pollpid=$!
  sleep 1
fi

echo
echo "Press SPACE when you hear the fan stop. Press q to abort."
echo

t0=$(now)
if [ "$dry" = 0 ]; then
  if [ "$method" = menu ]; then
    adb shell input keyevent KEYCODE_POWER
    sleep 1.5   # give the power menu time to open, so the second press confirms it
    t0=$(now)
    adb shell input keyevent KEYCODE_POWER
  else
    adb shell svc power shutdown >/dev/null 2>&1 &
  fi
fi

stty -echo -icanon 2>/dev/null
result=''
while :; do
  printf '\r  %6s s ' "$(secs "$t0" "$(now)")"
  if IFS= read -rsn1 -t 0.1 key; then
    case "$key" in
      ' ') result=$(now); break ;;
      q|Q) echo; echo "Aborted."; exit 1 ;;
    esac
  fi
done
stty echo icanon 2>/dev/null
echo

total=$(secs "$t0" "$result")
echo
echo "From sending the command to the fan stopping:  $total s"

from_thread='' adb_gone=''
if [ "$dry" = 0 ]; then
  first=$(grep -m1 -E 'Logging pre-reboot|Sending shutdown broadcast|shutdown' "$work/shutdown.log" 2>/dev/null | cut -d' ' -f1)
  if [ -n "$first" ]; then
    from_thread=$(secs "$first" "$result")
    echo "From Android starting its shutdown:            $from_thread s"
  else
    echo "Android's shutdown start wasn't seen in the log, so only the first time is available."
  fi
  if [ -s "$work/adb_gone" ]; then
    adb_gone=$(secs "$t0" "$(cat "$work/adb_gone")")
    echo "adb lost the device after:                     $adb_gone s"
  fi
  [ -f "$csv" ] || echo "date,build,method,total_s,from_shutdown_start_s,adb_gone_s" > "$csv"
  echo "$(date '+%F %T'),${build:-unknown},$method,$total,${from_thread},${adb_gone}" >> "$csv"
  echo
  echo "Saved to $csv"
fi
