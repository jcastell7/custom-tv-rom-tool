#!/usr/bin/env bash
# Build wrapper. Always goes through lunch: bare soong_ui gives a different product config and false errors.
# Usage: 40-build.sh ANDROID_TREE LUNCH_TARGET [make targets...]     Example: 40-build.sh ~/lineage-21.0 lineage_mybox-ap2a-userdebug
# Default targets rebuild every flashable image. Run it in the background, because a full build takes hours and increments take minutes.
set -uo pipefail
T=$1; TARGET=$2; shift 2
TARGETS=${*:-vendorbootimage bootimage initbootimage vbmetaimage superimage}
"$(dirname "$(readlink -f "$0")")/00-check-host.sh" --tree "$T" --purpose build > /tmp/hostcheck.$$ 2>&1 || { grep -E 'FAIL' /tmp/hostcheck.$$; rm -f /tmp/hostcheck.$$; echo "Stopping: fix these first (docs/10-SETUP-NEW-COMPUTER.md)."; exit 1; }
rm -f /tmp/hostcheck.$$
cd "$T" || exit 1
set +u
source build/envsetup.sh >/dev/null 2>&1
fixup_common_out_dir() { return 0; }   # On Lineage it can be missing or fail in a non-interactive shell.
lunch "$TARGET" >/dev/null 2>&1 || true
[ "${TARGET_PRODUCT:-}" = "${TARGET%%-*}" ] || { echo "ERROR: lunch didn't select $TARGET"; exit 1; }
echo "start $(date +%T)"
m -j"$(nproc)" $TARGETS 2>&1 | tee build.log | tail -12 | cut -c1-180
rc=${PIPESTATUS[0]}
echo "rc=$rc $(date +%T)"
[ "$rc" = 0 ] || { echo "Build failed. Errors:"; grep -E 'FAILED:|error:|Offending entries' -A2 build.log | tail -30 | cut -c1-220; echo "See docs/04 for common build errors."; }
exit "$rc"
