#!/usr/bin/env bash
# Times a startup. Press SPACE at the same moment you press the power button (or plug the power in), then wait.
#
# Usage: startup-timer.sh [--reboot] [-y]
#   default   the device should be off. The clock starts when you press SPACE
#   --reboot  restart a running device with "adb reboot" and start the clock at that moment. That includes the
#             shutdown, so it's for testing this script and comparing builds, not for real-world numbers
#   -y        don't ask for confirmation (with --reboot)
#
# Press SPACE again when you see the home screen: the TOTAL uses only your two presses. It also watches for the
# device on USB, for adb, and for Android's boot_completed, then reads Android's own boot report: the kernel's
# uptime gives when the kernel started, which splits the time into before the kernel (power-on and bootloader)
# and after it. Results are added to startup-times.csv next to this script.
set -u

mode=manual yes=0
for arg in "$@"; do
  case "$arg" in
    --reboot) mode=reboot ;;
    -y) yes=1 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (see --help)"; exit 2 ;;
  esac
done

command -v adb >/dev/null || { echo "ERROR: adb isn't installed or isn't on PATH"; exit 1; }
have_lsusb=1; command -v lsusb >/dev/null || have_lsusb=0
here=$(cd "$(dirname "$0")" && pwd)
csv="$here/startup-times.csv"
trap 'stty echo icanon 2>/dev/null' EXIT INT TERM

now() { date +%s.%N; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }
on_usb() { lsusb 2>/dev/null | grep -qiE "ID (${DEVICE_USB_IDS:-1f3a|18d1}):"; }
state() { adb get-state 2>/dev/null; }

if [ "$mode" = manual ]; then
  if [ "$(state)" = device ]; then
    echo "The device is on and connected over adb. Turn it off first, or use --reboot."
    exit 1
  fi
  [ "$have_lsusb" = 1 ] && on_usb && echo "Note: a device is already on USB, so the USB stage won't be timed."
  echo "Get ready: press SPACE at the same moment you press the power button. Press q to abort."
  stty -echo -icanon 2>/dev/null
  started=0
  while IFS= read -rsn1 key; do
    case "$key" in
      ' ') started=1; break ;;
      q|Q) echo "Aborted."; exit 1 ;;
    esac
  done
  stty echo icanon 2>/dev/null
  [ "$started" = 1 ] || { echo "No key press received. Run this from a terminal."; exit 1; }
  t0=$(now)
else
  [ "$(state)" = device ] || { echo "ERROR: --reboot needs the device running and on adb"; exit 1; }
  if [ "$yes" = 0 ]; then
    printf 'This will restart the device. Continue? [y/N] '
    read -r answer
    [ "$answer" = y ] || [ "$answer" = Y ] || { echo "Cancelled."; exit 0; }
  fi
  t0=$(now)
  adb reboot
  while [ "$(state)" = device ]; do sleep 0.2; done   # wait until it has really gone down
  have_lsusb=0   # the USB stage can't be told apart from the shutdown here, so it isn't timed
fi

echo "Clock started. Waiting for the device..."
[ "$mode" = manual ] && echo "Press SPACE when you see the home screen. Press q to stop."
stty -echo -icanon 2>/dev/null
t_usb='' t_adb='' t_done='' t_home=''
deadline=$(awk -v t="$t0" 'BEGIN { printf "%.3f", t + 240 }')   # printf: plain print would give 1.79e+09
while :; do
  t=$(now)
  if [ -z "$t_usb" ] && [ "$have_lsusb" = 1 ] && on_usb; then t_usb=$t; printf '\r  %6s s  on USB\n' "$(secs "$t0" "$t")"; fi
  if [ -z "$t_adb" ] && [ "$(state)" = device ]; then t_adb=$t; printf '\r  %6s s  adb ready\n' "$(secs "$t0" "$t")"; fi
  if [ -n "$t_adb" ] && [ -z "$t_done" ] && [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
    t_done=$(now); printf '\r  %6s s  Android reports boot completed\n' "$(secs "$t0" "$t_done")"
    [ "$mode" = manual ] && [ -z "$t_home" ] && echo "  Still waiting for you: press SPACE when you see the home screen."
  fi
  if [ -n "$t_done" ] && { [ "$mode" = reboot ] || [ -n "$t_home" ]; }; then break; fi
  if awk -v a="$t" -v b="$deadline" 'BEGIN { exit !(a > b) }'; then echo; echo "Gave up after 240 s."; exit 1; fi
  printf '\r  %6s s ' "$(secs "$t0" "$t")"
  if IFS= read -rsn1 -t 0.2 key; then
    case "$key" in
      ' ') if [ "$mode" = manual ] && [ -z "$t_home" ]; then t_home=$(now); printf '\r  %6s s  Home screen visible (you)\n' "$(secs "$t0" "$t_home")"; fi ;;
      q|Q) echo; echo "Stopped."; [ -n "$t_done" ] || exit 1; break ;;
    esac
  fi
done
stty echo icanon 2>/dev/null

# Android's own report. Uptime counts from the kernel's start, so host time minus uptime gives that start.
sleep 2
t_read=$(now)
uptime=$(adb shell "cut -d' ' -f1 /proc/uptime" 2>/dev/null | tr -d '\r')
kernel_start=$(awk -v a="$t_read" -v b="$uptime" 'BEGIN { printf "%.3f", a - b }')
events=$(adb shell "logcat -b events -d 2>/dev/null | grep -E 'boot_progress_(start|enable_screen)|sf_stop_bootanim'" | tr -d '\r')
ms() { echo "$events" | awk -v k="$1" '$0 ~ k { v = $NF } END { if (v != "") printf "%.1f", v / 1000 }'; }
zygote=$(ms boot_progress_start); screen=$(ms boot_progress_enable_screen); anim=$(ms sf_stop_bootanim)
build=$(adb shell getprop ro.build.version.incremental 2>/dev/null | tr -d '\r')

pre=$(secs "$t0" "$kernel_start")
total=$(secs "$t0" "$t_done")
k() { [ -n "$1" ] && awk -v p="$pre" -v x="$1" 'BEGIN { printf "%.1f", p + x }'; }
echo
echo "Android's report, as seconds since you pressed SPACE (in brackets: since the kernel started):"
printf '  %-38s %6s s\n' "Power-on and bootloader, to the kernel" "$pre"
[ -n "$zygote" ] && printf '  %-38s %6s s  (%s)\n' "Android framework starts (zygote)" "$(k "$zygote")" "$zygote"
[ -n "$anim" ]   && printf '  %-38s %6s s  (%s)\n' "Loading animation ends" "$(k "$anim")" "$anim"
[ -n "$screen" ] && printf '  %-38s %6s s  (%s)\n' "Home screen enabled" "$(k "$screen")" "$screen"
printf '  %-38s %6s s\n' "Boot completed (seen from the PC)" "$total"
[ -z "$anim" ] && echo "  (The animation-end event wasn't in the log, so that line is missing.)"
home=''; [ -n "$t_home" ] && home=$(secs "$t0" "$t_home")
echo
if [ -n "$home" ]; then
  echo "TOTAL: $home s from your power button press to your home screen press."
  echo "The home screen appeared $(awk -v a="$total" -v b="$home" 'BEGIN { printf "%.1f", b - a }') s after Android reported boot completed."
else
  echo "TOTAL: not available, because you didn't mark the home screen."
fi
echo
echo "Your SPACE presses were by hand, so expect a few tenths of a second either way."

header="date,build,mode,to_kernel_s,usb_s,adb_s,zygote_s,anim_end_s,boot_completed_s,home_visible_s"
[ -f "$csv" ] || echo "$header" > "$csv"
head -1 "$csv" | grep -q home_visible_s || sed -i "1s/.*/$header/" "$csv"
echo "$(date '+%F %T'),${build:-unknown},$mode,$pre,${t_usb:+$(secs "$t0" "$t_usb")},$(secs "$t0" "$t_adb"),$(k "$zygote"),$(k "$anim"),$total,$home" >> "$csv"
echo "Saved to $csv"
