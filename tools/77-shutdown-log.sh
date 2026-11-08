#!/usr/bin/env bash
# Records one shutdown's kernel log without a UART, and shows where the time went. See docs/13-TUNING.md, section 4.
#
# Usage: 77-shutdown-log.sh OUTPUT_DIR [-y]
#
# Needs: the device booted, adb root (userdebug and "Rooted debugging" on), and Magisk (for /data/adb/service.d).
# RESTARTS THE DEVICE TWICE: once so Magisk starts the logger, once for the measured shutdown.
#
# How: a temporary Magisk service.d script waits for sys.shutdown.requested, then appends every kernel log line to
# /metadata/shutdown-log.txt, opening and closing the file per line so /metadata can still unmount. Magisk's
# processes aren't in an init service's cgroup, so init doesn't kill it. Lines written after /metadata unmounts
# are lost: that's only the very end. The script deletes itself when it starts, and this tool deletes the log
# after copying it.
#
# Status: the same steps were used on the first device. This script form hasn't been run there yet.
set -u
out=${1:-}; yes=0; [ "${2:-}" = -y ] && yes=1
[ -n "$out" ] && [ "$out" != -y ] || { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
mkdir -p "$out"

sl() { sleep "$1"; }
a() { timeout 30 adb shell "$@"; }
wait_boot() {
  for _ in $(seq 1 120); do [ "$(adb get-state 2>/dev/null)" = device ] || break; sl 0.5; done
  for _ in $(seq 1 150); do [ "$(timeout 5 adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && return 0; sl 2; done
  echo "ERROR: the device didn't finish booting within 5 minutes"; exit 1
}
get_root() { timeout 15 adb root >/dev/null 2>&1; sl 3; timeout 30 adb wait-for-device; [ "$(a id -u | tr -d '\r')" = 0 ]; }

n=$(adb devices | awk 'NR > 1 && $2 == "device"' | wc -l)
[ "$n" = 1 ] || { echo "ERROR: need exactly one device in 'adb devices', found $n"; exit 1; }
get_root || { echo "ERROR: adb root didn't work. Turn on Rooted debugging in Developer options (ask the user)."; exit 1; }
a 'test -d /data/adb/service.d' || { echo "ERROR: /data/adb/service.d is missing. Is Magisk installed and set up?"; exit 1; }
if [ "$yes" = 0 ]; then
  printf 'This restarts the device twice. Continue? [y/N] '; read -r r
  [ "$r" = y ] || [ "$r" = Y ] || { echo "Cancelled."; exit 0; }
fi

echo "Installing the logger and restarting so Magisk starts it..."
a 'cat > /data/adb/service.d/zz-shutdown-log.sh' <<'E'
#!/system/bin/sh
# Temporary, from custom-tv-rom-tool/tools/77-shutdown-log.sh: copies the kernel log to /metadata during one shutdown.
F=/metadata/shutdown-log.txt
rm -f /data/adb/service.d/zz-shutdown-log.sh
while [ -z "$(getprop sys.shutdown.requested)" ]; do sleep 0.2; done
echo "requested=$(getprop sys.shutdown.requested) uptime=$(cat /proc/uptime)" > $F
/system/bin/dmesg -c > /dev/null
# /system/bin/dmesg: Magisk runs this under BusyBox ash, whose own dmesg has no -w.
/system/bin/dmesg -w | while IFS= read -r l; do echo "$l" >> $F; done
E
a 'chmod 755 /data/adb/service.d/zz-shutdown-log.sh; rm -f /metadata/shutdown-log.txt; reboot'
wait_boot; sl 5; get_root || exit 1
a 'test -e /data/adb/service.d/zz-shutdown-log.sh' && { echo "ERROR: Magisk didn't run the logger (it's still there)."; a 'rm -f /data/adb/service.d/zz-shutdown-log.sh'; exit 1; }

echo "Measured restart..."
cmd_uptime=$(a 'cut -d" " -f1 /proc/uptime' | tr -d '\r')
a 'svc power reboot' >/dev/null 2>&1
wait_boot; sl 3; get_root || exit 1
a 'cat /metadata/shutdown-log.txt' > "$out/shutdown-log.txt"
a 'rm -f /metadata/shutdown-log.txt'
lines=$(wc -l < "$out/shutdown-log.txt")
echo "Saved $lines lines to $out/shutdown-log.txt (restart command at uptime $cmd_uptime)."
[ "$lines" -gt 5 ] || { echo "Too few lines: check the file. The logger may not have started."; exit 1; }

python3 -I - "$out/shutdown-log.txt" "$cmd_uptime" <<'P'
import re, sys
L = open(sys.argv[1], errors="replace").read().split("\n")
cmd = float(sys.argv[2] or 0)
def ts(l):
    m = re.match(r"\[\s*(\d+\.\d+)\]", l)
    return float(m.group(1)) if m else None
strip = lambda l: re.sub(r"^\[[^]]*\]\s*(\[[^]]*\]\s*)?", "", l)
keys = r"Reboot start|Shutdown timeout|Stopping \d+ services|Waiting for \d+ pids|vdc|sync\(\)|So far shutdown|packages restored|Unmounting /dev|powerctl_shutdown|Reboot ending"
print("\nKey steps (kernel uptime; the restart command was at %.2f):" % cmd)
for l in L:
    if re.search(keys, l) and "avc" not in l:
        t = ts(l)
        print("  %7.2f  (+%5.2f)  %s" % (t, t - cmd, strip(l)[:100]) if t else "  " + l[:100])
last = next((l for l in reversed(L) if ts(l)), "")
if last:
    print("  last line at %.2f (+%.2f): %s" % (ts(last), ts(last) - cmd, strip(last)[:90]))
print("\nSteps after the last line (unmounting /metadata, the final sync, the kernel's power-off) aren't logged.")
print("Compare 'So far shutdown sequence took' between builds: init measures it itself.")
P
