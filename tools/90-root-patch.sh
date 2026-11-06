#!/usr/bin/env bash
# Patches init_boot (or boot on older devices) with Magisk, by running Magisk's own patcher on the booted device. It writes only to
# /data/local/tmp there and to OUTPUT here; flashing is a separate step, on purpose.
#
# Usage: 90-root-patch.sh MAGISK_APK BOOT_IMAGE OUTPUT_IMAGE [ABI, default armeabi-v7a]
#
# RISK: the patched image is first-stage init, and recovery uses it too. If it fails early, fastbootd may not come up. Only do this with a
# rescue route you have PROVEN (docs/03). Keep the unpatched image. Flash with: 60-flash.sh --init-boot OUTPUT, or fastboot flash init_boot_a.
# Install the Magisk app with adb install as a USER app: it warns if it's a system app and it updates itself.
set -euo pipefail
. "$(dirname "$0")/common.sh"
[ $# -ge 3 ] || die "usage: $0 MAGISK_APK BOOT_IMAGE OUTPUT_IMAGE [ABI]"
apk=$1 img=$2 out=$3 abi=${4:-armeabi-v7a}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
[ "$($ADB get-state)" = device ] || die "needs the booted system over adb"
unzip -qo "$apk" "lib/$abi/*" 'assets/*' -d "$work"
d=/data/local/tmp/magisk
$ADB shell "rm -rf $d; mkdir -p $d"
$ADB push "$work"/assets/boot_patch.sh "$work"/assets/util_functions.sh "$d"/ >/dev/null
for pair in libmagiskboot.so:magiskboot libmagiskinit.so:magiskinit libmagisk.so:magisk libinit-ld.so:init-ld libbusybox.so:busybox; do
  $ADB push "$work/lib/$abi/${pair%%:*}" "$d/${pair##*:}" >/dev/null
done
[ -f "$work/assets/stub.apk" ] && $ADB push "$work/assets/stub.apk" "$d"/ >/dev/null
$ADB push "$img" "$d/init_boot.img" >/dev/null
$ADB shell "cd $d && chmod 755 magiskboot magiskinit magisk init-ld busybox boot_patch.sh && KEEPVERITY=true KEEPFORCEENCRYPT=true PATCHVBMETAFLAG=false sh boot_patch.sh init_boot.img"
$ADB pull "$d/new-boot.img" "$out"
$ADB shell "rm -rf $d"
[ "$(head -c 8 "$out")" = 'ANDROID!' ] || die "$out isn't a boot image"
green "Patched: $out. Header version: $(od -An -tu4 -j40 -N4 "$out" | tr -d ' ')"
