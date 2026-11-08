#!/usr/bin/env bash
# Captures stack traces of key processes at a chosen moment during boot, to see what a slow step waits on.
# See docs/13-TUNING.md, section 3b.
#
# Usage: 78-boot-stacks.sh OUTPUT_DIR [UPTIME_S] [-y]
#   UPTIME_S  seconds since the kernel started, when to capture (default 27). Pick a time inside the slow step,
#             from tools/76-boot-profile.py
#
# Needs: adb root and Magisk (for /data/adb/service.d). RESTARTS THE DEVICE ONCE.
# Captures system_server (Java stacks, debuggerd -j) and surfaceflinger plus every composer HAL process (native,
# debuggerd -b). The capture script deletes itself before it runs, so it only fires once.
#
# Why a script on the device: adb usually arrives after the slow step is over.
# Status: the same steps were used on the first device. This script form hasn't been run there yet.
set -u
out=${1:-}; at=27; yes=0
for x in "${@:2}"; do case "$x" in -y) yes=1 ;; *[!0-9]*) echo "UPTIME_S must be whole seconds"; exit 2 ;; *) at=$x ;; esac; done
[ -n "$out" ] && [ "$out" != -y ] || { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
mkdir -p "$out"
a() { timeout 30 adb shell "$@"; }
get_root() { timeout 15 adb root >/dev/null 2>&1; sleep 3; timeout 30 adb wait-for-device; [ "$(a id -u | tr -d '\r')" = 0 ]; }

n=$(adb devices | awk 'NR > 1 && $2 == "device"' | wc -l)
[ "$n" = 1 ] || { echo "ERROR: need exactly one device in 'adb devices', found $n"; exit 1; }
get_root || { echo "ERROR: adb root didn't work. Turn on Rooted debugging in Developer options (ask the user)."; exit 1; }
a 'test -d /data/adb/service.d' || { echo "ERROR: /data/adb/service.d is missing. Is Magisk installed and set up?"; exit 1; }
if [ "$yes" = 0 ]; then
  printf 'This restarts the device once, and captures stacks at %s s of uptime. Continue? [y/N] ' "$at"; read -r r
  [ "$r" = y ] || [ "$r" = Y ] || { echo "Cancelled."; exit 0; }
fi

a 'cat > /data/adb/service.d/zz-boot-stacks.sh' <<E
#!/system/bin/sh
# Temporary, from custom-tv-rom-tool/tools/78-boot-stacks.sh: one capture of stacks during boot.
rm -f /data/adb/service.d/zz-boot-stacks.sh
O=/data/local/tmp/boot-stacks; rm -rf \$O; mkdir -p \$O
while [ "\$(cut -d. -f1 /proc/uptime)" -lt $at ]; do sleep 0.2; done
echo "start \$(cat /proc/uptime)" > \$O/time
p=\$(pidof system_server); [ -n "\$p" ] && /system/bin/debuggerd -j \$p > \$O/system_server.txt 2>&1
p=\$(pidof surfaceflinger); [ -n "\$p" ] && /system/bin/debuggerd -b \$p > \$O/surfaceflinger.txt 2>&1
for p in \$(ps -A -o PID,NAME | grep -iE 'composer|hwcomposer' | awk '{print \$1}'); do /system/bin/debuggerd -b \$p > \$O/composer-\$p.txt 2>&1; done
echo "end \$(cat /proc/uptime)" >> \$O/time
E
a 'chmod 755 /data/adb/service.d/zz-boot-stacks.sh; reboot'
for _ in $(seq 1 120); do [ "$(adb get-state 2>/dev/null)" = device ] || break; sleep 0.5; done
for _ in $(seq 1 150); do [ "$(timeout 5 adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break; sleep 2; done
sleep 3; get_root || exit 1
a 'cat /data/local/tmp/boot-stacks/time' 2>/dev/null || { echo "No capture: the uptime may have passed before Magisk ran the script (it starts at late_start). Try a later UPTIME_S."; exit 1; }
timeout 60 adb pull /data/local/tmp/boot-stacks "$out/" >/dev/null && a 'rm -rf /data/local/tmp/boot-stacks'
echo "Saved to $out/boot-stacks/"
python3 -I - "$out/boot-stacks" <<'P'
import os, re, sys
d = sys.argv[1]
for f in sorted(os.listdir(d)):
    if not f.endswith(".txt"):
        continue
    s = open(os.path.join(d, f), errors="replace").read()
    print("\n== %s" % f)
    for b in re.split(r'\n(?=")', s):
        head = b.split("\n")[0][:60]
        frames = [re.sub(r"\(BuildId.*", "", re.sub(r"^\s*(native: )?#\d+ pc [0-9a-f]+\s+", "", x)).strip()
                  for x in b.split("\n") if re.search(r"#\d+ pc |^\s+at |^\s+- (waiting|locked)", x)]
        useful = [x for x in frames if not re.search(r"libc\.so|libc\+\+\.so|libbinder\.so|libutils\.so|libhidl|Looper|MessageQueue|Handler\.|android\.os\.|HandlerThread|ZygoteInit|RuntimeInit|Method\.invoke", x)]
        if useful and re.search(r'"(main|android\.display|surfaceflinger|RenderEngine|binder|composer|HwBinder)', head):
            print("  %s\n    %s" % (head, "\n    ".join(y[:110] for y in useful[:6])))
print("\nLook for a thread waiting on a lock or a binder call, then follow it to the process that serves it.")
P
