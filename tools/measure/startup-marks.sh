#!/usr/bin/env bash
# Times a startup with your own marks as well as automatic ones. The device must be off and on USB.
#
#   SPACE 1  when you press the power button (or plug the power in): starts the clock
#   SPACE 2  when you see the picture change (for example, the loading animation appears)
#   SPACE 3  when you see the home screen
#   q        finish early and show what was recorded so far
#
# Automatic marks: the device appears on USB, adb is ready, Android reports boot completed. At the end it reads
# Android's own boot report and lists everything in order, in seconds from SPACE 1. The total uses only your
# presses: SPACE 1 to SPACE 3. Results are added to startup-marks.csv next to this script.
set -u

case "${1:-}" in
  -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  '') ;;
  *) echo "Unknown option: $1 (see --help)"; exit 2 ;;
esac

command -v adb >/dev/null || { echo "ERROR: adb isn't installed or isn't on PATH"; exit 1; }
have_lsusb=1; command -v lsusb >/dev/null || have_lsusb=0
here=$(cd "$(dirname "$0")" && pwd)
csv="$here/startup-marks.csv"
trap 'stty echo icanon 2>/dev/null' EXIT INT TERM

now() { date +%s.%N; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }
on_usb() { lsusb 2>/dev/null | grep -qiE "ID (${DEVICE_USB_IDS:-1f3a|18d1}):"; }
state() { adb get-state 2>/dev/null; }

if [ "$(state)" = device ]; then
  echo "The device is on and connected over adb. Turn it off first, then run this again."
  exit 1
fi
[ "$have_lsusb" = 1 ] || echo "Note: lsusb isn't installed, so the USB mark is skipped."
[ "$have_lsusb" = 1 ] && on_usb && { echo "Note: a device is already on USB, so the USB mark is skipped."; have_lsusb=0; }

labels=("Picture changed" "Home screen visible")
prompts=("Press SPACE when you see the picture change." "Press SPACE when you see the home screen.")

echo "Press SPACE at the same moment you press the power button. Press q to abort."
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
echo "Clock started. ${prompts[0]}"

# Every mark is kept as "seconds<TAB>label", printed as it happens.
marks=()
mark() { local s; s=$(secs "$t0" "$2"); marks+=("$s"$'\t'"$1"); printf '\r  %6s s  %s\n' "$s" "$1"; }

t_usb='' t_adb='' t_done='' manual=0 finished=0
deadline=$(awk -v t="$t0" 'BEGIN { printf "%.3f", t + 300 }')
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
  if [ -z "$t_usb" ] && [ "$have_lsusb" = 1 ] && on_usb; then t_usb=$t; mark "Device on USB" "$t"; fi
  if [ -z "$t_adb" ] && [ "$(state)" = device ]; then t_adb=$t; mark "adb ready" "$t"; fi
  if [ -n "$t_adb" ] && [ -z "$t_done" ] && [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
    t_done=$(now); mark "Android reports boot completed" "$t_done"
    [ "$manual" -lt "${#labels[@]}" ] && echo "  Still waiting for your marks. ${prompts[$manual]}"
  fi
  if [ -n "$t_done" ] && [ "$manual" -ge "${#labels[@]}" ]; then finished=1; break; fi
  if awk -v a="$t" -v b="$deadline" 'BEGIN { exit !(a > b) }'; then echo; echo "Stopped after 300 s."; break; fi
  printf '\r  %6s s ' "$(secs "$t0" "$t")"
done
stty echo icanon 2>/dev/null
echo

# Android's own report. Uptime counts from the kernel's start, so host time minus uptime gives that start.
pre='' zygote='' anim='' screen='' build=''
if [ "$(state)" = device ]; then
  t_read=$(now)
  uptime=$(adb shell "cut -d' ' -f1 /proc/uptime" 2>/dev/null | tr -d '\r')
  if [ -n "$uptime" ]; then
    pre=$(awk -v a="$t0" -v b="$t_read" -v u="$uptime" 'BEGIN { printf "%.1f", (b - u) - a }')
    marks+=("$pre"$'\t'"Kernel starts (Android's uptime)")
  fi
  events=$(adb shell "logcat -b events -d 2>/dev/null | grep -E 'boot_progress_(start|enable_screen)|sf_stop_bootanim'" | tr -d '\r')
  at() { echo "$events" | awk -v k="$1" -v p="$pre" '$0 ~ k { v = $NF } END { if (v != "" && p != "") printf "%.1f", p + v / 1000 }'; }
  zygote=$(at boot_progress_start); anim=$(at sf_stop_bootanim); screen=$(at boot_progress_enable_screen)
  [ -n "$zygote" ] && marks+=("$zygote"$'\t'"Android framework starts (Android's log)")
  [ -n "$screen" ] && marks+=("$screen"$'\t'"Home screen enabled (Android's log)")
  [ -n "$anim" ] && marks+=("$anim"$'\t'"Loading animation ends (Android's log)")
  build=$(adb shell getprop ro.build.version.incremental 2>/dev/null | tr -d '\r')
else
  echo "adb never connected, so Android's own report isn't available."
fi

echo "Everything in order, in seconds after you pressed the power button:"
printf '%s\n' "${marks[@]}" | sort -n | awk -F'\t' '{ printf "  %6s s  %s\n", $1, $2 }'

get() { printf '%s\n' "${marks[@]}" | awk -F'\t' -v l="$1" 'index($2, l) == 1 { print $1; exit }'; }
home=$(get "Home screen visible"); done_s=$(get "Android reports boot completed")
if [ -n "$home" ] && [ -n "$done_s" ]; then
  echo
  echo "The home screen appeared $(awk -v a="$done_s" -v b="$home" 'BEGIN { printf "%.1f", b - a }') s after Android reported boot completed (negative means before)."
fi
echo
# The total uses only your own presses, never the automatic marks.
pic=$(get "Picture changed")
echo "Your presses:"
[ -n "$pic" ] && echo "  power button to picture change:  $pic s"
[ -n "$pic" ] && [ -n "$home" ] && echo "  picture change to home screen:   $(awk -v a="$pic" -v b="$home" 'BEGIN { printf "%.1f", b - a }') s"
if [ -n "$home" ]; then
  echo "TOTAL: $home s from your power button press to your home screen press."
else
  echo "TOTAL: not available, because you didn't mark the home screen."
fi
echo
echo "Your marks are by hand, so expect a few tenths of a second either way."
[ "$finished" = 1 ] || echo "Not every mark was recorded."

[ -f "$csv" ] || echo "date,build,to_kernel_s,usb_s,picture_change_s,adb_s,zygote_s,anim_end_s,home_enabled_s,boot_completed_s,home_visible_s" > "$csv"
echo "$(date '+%F %T'),${build:-unknown},$pre,$(get 'Device on USB'),$(get 'Picture changed'),$(get 'adb ready'),$zygote,$anim,$screen,$done_s,$home" >> "$csv"
echo "Saved to $csv"
