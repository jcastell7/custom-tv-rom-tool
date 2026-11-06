#!/usr/bin/env bash
# Stock's vendor.display.config@1.0.so has the same path as a Qualcomm module in this tree, whose interface has no keystone
# methods. The build won't allow both, so the stock library gets its own name, and the stock files that link to it are updated (docs/18).
# Usage: rename-display-config.sh PATCHELF VENDOR_DIR...   Run once on freshly extracted blobs.
set -euo pipefail
pe=$1; shift
old=vendor.display.config@1.0.so
new=vendor.display.config.aw@1.0.so
for v in "$@"; do
  if [ -f "$v/lib/$old" ]; then
    mv "$v/lib/$old" "$v/lib/$new"
    "$pe" --set-soname "$new" "$v/lib/$new"
  fi
  find "$v/lib" "$v/bin" -type f | while read -r f; do
    if [ "$(head -c4 "$f" | tr -d '\0')" = "$(printf '\177ELF')" ] && readelf -d "$f" 2>/dev/null | grep -q "NEEDED.*\[$old\]"; then
      "$pe" --replace-needed "$old" "$new" "$f"
      echo "updated: ${f#"$v"/}"
    fi
  done
done
