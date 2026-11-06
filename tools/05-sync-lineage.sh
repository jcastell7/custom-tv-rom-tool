#!/usr/bin/env bash
# Downloads the LineageOS source. Checks the location first and refuses a bad one. Safe to re-run: it resumes.
# Usage: 05-sync-lineage.sh TREE_DIR [BRANCH]       Default branch lineage-21.0 (Android 14).
# Takes hours, and about 160 GB. Run it in the background, and re-run it if it stops. Touches no device.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
[ $# -ge 1 ] || { echo "usage: $0 TREE_DIR [BRANCH]"; exit 2; }
TREE=$1; BRANCH=${2:-lineage-21.0}
"$HERE/00-check-host.sh" --tree "$TREE" --purpose build || { echo "Stopping: fix the FAIL items above first."; exit 1; }
mkdir -p "$TREE" && cd "$TREE" || exit 1
git lfs install --skip-repo || exit 1
[ -d .repo ] || repo init -u https://github.com/LineageOS/android.git -b "$BRANCH" --git-lfs --no-clone-bundle || exit 1
repo sync -c -j"$(nproc)" --no-clone-bundle --no-tags --optimized-fetch --prune
rc=$?
[ "$rc" = 0 ] && echo "Sync finished. Check it: $HERE/00-check-host.sh --tree $TREE" || echo "Sync stopped with status $rc. Re-run this command to resume."
exit "$rc"
