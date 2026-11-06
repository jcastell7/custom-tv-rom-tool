#!/usr/bin/env bash
# Adds libhermes_wpa_shim.so to stock's wpa_supplicant and hostapd. Run once on freshly extracted blobs (docs/12, FIX 17).
# Usage: patch-wpa-blobs.sh PATCHELF VENDOR_DIR...   where VENDOR_DIR contains bin/hw/
set -euo pipefail
pe=$1; shift
for v in "$@"; do
  for b in wpa_supplicant hostapd; do
    f=$v/bin/hw/$b
    if readelf -d "$f" | grep -q libhermes_wpa_shim.so; then
      echo "already patched: $f"
    else
      "$pe" --add-needed libhermes_wpa_shim.so "$f"
      echo "patched: $f"
    fi
  done
done
