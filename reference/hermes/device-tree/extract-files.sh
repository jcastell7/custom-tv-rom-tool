#!/bin/bash
# extract-files.sh — pull proprietary blobs for hermes using LineageOS extract-utils.
# Run from inside a LineageOS source tree (device/allwinner/hermes/), OR point it at the
# pre-staged dump with --only-target <path-to>/vendor/allwinner/hermes/proprietary.
set -e

DEVICE=hermes
VENDOR=allwinner

# Locate the LineageOS source root (expects this tree under device/allwinner/hermes).
MY_DIR="$(dirname "$(readlink -f "$0")")"
ANDROID_ROOT="${MY_DIR}/../../.."

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
[ -f "$HELPER" ] || HELPER="${ANDROID_ROOT}/vendor/lineage/build/tools/extract_utils.sh"
if [ ! -f "$HELPER" ]; then
    echo "!! extract_utils.sh not found — run this inside a synced LineageOS tree." >&2
    echo "   The blob manifest is proprietary-files.txt in vendor/${VENDOR}/${DEVICE}/." >&2
    exit 1
fi
source "$HELPER"

# Default source: the dump staged by tooling/stage-proprietary.sh.
SRC="${1:-${ANDROID_ROOT}/vendor/${VENDOR}/${DEVICE}/proprietary}"

setup_vendor "$DEVICE" "$VENDOR" "$ANDROID_ROOT" false false
extract "${MY_DIR}/../../../vendor/${VENDOR}/${DEVICE}/proprietary-files.txt" "$SRC" "" "" ""
"${MY_DIR}/setup-makefiles.sh"
