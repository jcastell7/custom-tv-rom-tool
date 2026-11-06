#!/usr/bin/env bash
# Works on a COPY of the backup and never touches the device. Unpacks super into partition images, then copies each filesystem to a directory.
# Usage: 30-extract-stock.sh SUPER_IMG OUT_DIR [slot suffix, default _a]
# Result: OUT_DIR/img/*.img and OUT_DIR/fs/{system,vendor,product,system_ext,odm,...}. These supply the blobs, stock apps and the gate's --stock-vendor.
# Needs: python3, debugfs (e2fsprogs). EROFS images need fsck.erofs --extract (erofs-utils): the script tells you if so.
set -uo pipefail
[ $# -ge 2 ] || { echo "usage: $0 SUPER_IMG OUT_DIR [slot suffix]"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd); SUPER=$1; OUT=$2; SLOT=${3:-_a}
mkdir -p "$OUT/img" "$OUT/fs"
head -c 4 "$SUPER" | od -An -tx1 | grep -q '3a ff 26 ed' && { echo "This super is sparse. Convert it first: simg2img super.img super.raw.img"; exit 1; }
python3 -I "$HERE/bin/lpunpack.py" "$SUPER" "$OUT/img" || { echo "lpunpack failed. If this device has no super, use the partition images from the backup directly."; exit 1; }
for img in "$OUT"/img/*.img; do
  n=$(basename "$img" .img); short=${n%"$SLOT"}
  [ -s "$img" ] || continue
  case "$n" in *_b) [ "$SLOT" = _a ] && continue ;; esac
  dest="$OUT/fs/$short"; mkdir -p "$dest"
  magic=$(dd if="$img" bs=1 skip=1024 count=4 2>/dev/null | od -An -tx1 | tr -d ' ')
  if [ "$(dd if="$img" bs=1 skip=1080 count=2 2>/dev/null | od -An -tx1 | tr -d ' ')" = 53ef ]; then
    debugfs -R "rdump / $dest" "$img" >/dev/null 2>&1 && echo "OK ext4  $short"
  elif [ "$magic" = e2e1f5e0 ]; then
    if command -v fsck.erofs >/dev/null; then fsck.erofs --extract="$dest" --overwrite "$img" >/dev/null 2>&1 && echo "OK erofs $short"
    else echo "NEEDS fsck.erofs: $short"; fi
  else
    echo "UNKNOWN filesystem, not extracted: $short"
  fi
done
# System-as-root images keep the real content in /system.
[ -d "$OUT/fs/system/system" ] && echo "Note: system files are in $OUT/fs/system/system"
echo "Stock vendor tree for the gate: $OUT/fs/vendor"
