#!/usr/bin/env bash
# Times a power-off with your own marks. The device must be on and connected over adb. This script sends nothing:
# you turn the device off yourself, with the remote.
#
#   SPACE 1  when you press the power button that powers it off (the press that confirms the power menu)
#   SPACE 2  when you see the picture go dark
#   SPACE 3  when you hear the fan stop
#   q        finish early and show what was recorded so far
#
# Automatic marks, for context only: Android starts its shutdown (from the device log), adb loses the device,
# the device leaves USB. The total uses only your presses: SPACE 1 to SPACE 3. Results are added to
# shutdown-marks.csv next to this script.
set -u

case "${1:-}" in
  -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  '') ;;
  *) echo "Unknown option: $1 (see --help)"; exit 2 ;;
esac

command -v adb >/dev/null || { echo "ERROR: adb isn't installed or isn't on PATH"; exit 1; }
have_lsusb=1; command -v lsusb >/dev/null || have_lsusb=0
here=$(cd "$(dirname "$0")" && pwd)
csv="$here/shutdown-marks.csv"
work=$(mktemp -d)
logpid=''
cleanup() { [ -n "$logpid" ] && kill "$logpid" 2>/dev/null; stty echo icanon 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT INT TERM

now() { date +%s.%N; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }
on_usb() { lsusb 2>/dev/null | grep -qiE "ID (${DEVICE_USB_IDS:-1f3a|18d1}):"; }
state() { adb get-state 2>/dev/null; }

n=$(adb devices | awk 'NR > 1 && $2 == "device"' | wc -l)
[ "$n" = 1 ] || { echo "The device needs to be on and connected over adb (found $n). Turn it on, then run this again."; exit 1; }
build=$(adb shell getprop ro.build.version.incremental 2>/dev/null | tr -d '\r')
[ "$have_lsusb" = 1 ] || echo "Note: lsusb isn't installed, so the USB mark is skipped."

# Note the host time when Android's ShutdownThread logs its first line.
adb logcat -c 2>/dev/null
( adb logcat -s ShutdownThread:I 2>/dev/null | while IFS= read -r line; do
    printf '%s %s\n' "$(now)" "$line"
  done > "$work/shutdown.log" ) &
logpid=$!

labels=("Power button pressed" "Picture went dark" "Fan stopped")
prompts=("" "Press SPACE when you see the picture go dark." "Press SPACE when you hear the fan stop.")

echo "Open the power menu with the remote if you like. Then press SPACE at the same moment you press the"
echo "power button that turns it off. Press q to abort."
stty -echo -icanon 2>/dev/null
started=0
while IFS= read -rsn1 key; do
  case "$key" in
    ' ') started=1; break ;;
    q|Q) echo "Aborted."; exit 1 ;;
  esac
done
[ "$started" = 1 ] || { echo "No key press received. Run this from a terminal."; exit 1; }
t0=$(now)

marks=()
mark() { local s; s=$(secs "$t0" "$2"); marks+=("$s"$'\t'"$1"); printf '\r  %6s s  %s\n' "$s" "$1"; }
mark "${labels[0]} (you)" "$t0"
manual=1
echo "  ${prompts[1]}"

t_thread='' t_adb='' t_usb='' finished=0
deadline=$(awk -v t="$t0" 'BEGIN { printf "%.3f", t + 120 }')
while :; do
  if IFS= read -rsn1 -t 0.2 key; then
    case "$key" in
      ' ')
        if [ "$manual" -lt "${#labels[@]}" ]; then
          mark "${labels[$manual]} (you)" "$(now)"
          manual=$((manual + 1))
          [ "$manual" -lt "${#prompts[@]}" ] && echo "  ${prompts[$manual]}"
        fi ;;
      q|Q) echo; echo "Finishing early."; break ;;
    esac
  fi
  t=$(now)
  if [ -z "$t_thread" ] && [ -s "$work/shutdown.log" ]; then
    t_thread=$(head -1 "$work/shutdown.log" | cut -d' ' -f1); mark "Android starts its shutdown" "$t_thread"
  fi
  if [ -z "$t_adb" ] && [ "$(state)" != device ]; then t_adb=$t; mark "adb lost the device" "$t"; fi
  if [ -z "$t_usb" ] && [ "$have_lsusb" = 1 ] && ! on_usb; then t_usb=$t; mark "Device left USB" "$t"; fi
  if [ "$manual" -ge "${#labels[@]}" ]; then finished=1; break; fi
  if awk -v a="$t" -v b="$deadline" 'BEGIN { exit !(a > b) }'; then echo; echo "Stopped after 120 s."; break; fi
  printf '\r  %6s s ' "$(secs "$t0" "$t")"
done
stty echo icanon 2>/dev/null
echo

echo "Everything in order, in seconds after you pressed the power button:"
printf '%s\n' "${marks[@]}" | sort -n | awk -F'\t' '{ printf "  %6s s  %s\n", $1, $2 }'

get() { printf '%s\n' "${marks[@]}" | awk -F'\t' -v l="$1" 'index($2, l) == 1 { print $1; exit }'; }
dark=$(get "Picture went dark"); fan=$(get "Fan stopped")
echo
echo "Your presses:"
[ -n "$dark" ] && echo "  power button to picture dark:  $dark s"
[ -n "$dark" ] && [ -n "$fan" ] && echo "  picture dark to fan stopped:   $(awk -v a="$dark" -v b="$fan" 'BEGIN { printf "%.1f", b - a }') s"
if [ -n "$fan" ]; then
  echo "TOTAL: $fan s from your power button press to your fan-stopped press."
else
  echo "TOTAL: not available, because you didn't mark the fan stopping."
fi
echo
echo "Your marks are by hand, so expect a few tenths of a second either way."
[ "$finished" = 1 ] || echo "Not every mark was recorded."

[ -f "$csv" ] || echo "date,build,picture_dark_s,fan_stopped_s,android_shutdown_start_s,adb_lost_s,usb_left_s" > "$csv"
echo "$(date '+%F %T'),${build:-unknown},$dark,$fan,$(get 'Android starts'),$(get 'adb lost'),$(get 'Device left USB')" >> "$csv"
echo "Saved to $csv"
