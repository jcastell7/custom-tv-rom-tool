#!/bin/bash
# setup-makefiles.sh — generate Android.bp / Android.mk / hermes-vendor.mk / BoardConfigVendor.mk
# from proprietary-files.txt, via LineageOS extract-utils. Run inside a LineageOS tree.
set -e

DEVICE=hermes
VENDOR=allwinner

MY_DIR="$(dirname "$(readlink -f "$0")")"
ANDROID_ROOT="${MY_DIR}/../../.."

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
[ -f "$HELPER" ] || HELPER="${ANDROID_ROOT}/vendor/lineage/build/tools/extract_utils.sh"
if [ ! -f "$HELPER" ]; then
    echo "!! extract_utils.sh not found — run this inside a synced LineageOS tree." >&2
    exit 1
fi
source "$HELPER"

# 4th arg = COMMON: false because hermes is a standalone device tree (not a shared "common" tree).
# COMMON=1 would make write_headers require a device-guard list and is wrong for a single device.
setup_vendor "$DEVICE" "$VENDOR" "$ANDROID_ROOT" false

# write_headers truncates Android.bp/Android.mk/*-vendor.mk/BoardConfigVendor.mk and writes their
# headers (soong_namespace, LOCAL_PATH, device guard). It MUST run before write_makefiles, which
# only APPENDS — without it, re-running this script stacks duplicate module definitions.
write_headers

write_makefiles "${MY_DIR}/../../../vendor/${VENDOR}/${DEVICE}/proprietary-files.txt" true

# write_footers closes the `ifeq ($(TARGET_DEVICE),hermes)` guard that write_headers opened in
# Android.mk. Must be the final step — without it, kati fails with "missing `endif'".
write_footers
