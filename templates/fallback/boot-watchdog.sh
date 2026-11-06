#!/vendor/bin/sh
# Boot loops go to recovery on the third attempt; hangs after 15 minutes. /metadata survives reflashing the ROM.
F=/metadata/hermes_bootcount
n=$(cat $F 2>/dev/null || echo 0)
n=$((n + 1))
echo "hermes_watchdog: boot attempt $n" > /dev/kmsg
if [ "$n" -ge 3 ]; then
    rm -f $F
    sync
    echo "hermes_watchdog: boot loop, going to recovery" > /dev/kmsg
    setprop sys.powerctl reboot,recovery
    exit 0
fi
echo "$n" > $F
sync
sleep 900
if [ "$(getprop sys.boot_completed)" != "1" ]; then
    echo "hermes_watchdog: boot hung, going to recovery" > /dev/kmsg
    setprop sys.powerctl reboot,recovery
fi
