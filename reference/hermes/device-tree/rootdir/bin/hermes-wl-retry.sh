#!/vendor/bin/sh
# The Seekwave driver gives up if its SDIO scan takes over about a second, and then Bluetooth and Wi-Fi have no device (docs/12, FIX 16).
# Rerun stock's loader once if that happened. A later boot stage is much quieter, so the scan normally succeeds.
[ -e /dev/BTBOOT ] && exit 0
echo "hermes_wl_retry: chip driver missing, reloading" > /dev/kmsg
setprop ctl.start wl_info
