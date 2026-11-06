# ADT-3 / MSI Android-TV Firmware Security Assessment — Methodology

**Date:** 2026-11-04
**Target:** Android-TV device enumerated over ADB as `ADT_3` / `adt3`, actually an
**MSI (Micro-Star) `h723_evb1` Allwinner-based** build (see findings).
**Analyst tooling:** REA (`rea-agents` 6.8.0) + unblob, jadx, apktool, adb. See [`../tooling/README.md`](../tooling/README.md).

## Scope & authorization
Physical-access security review of a developer/engineering Android-TV box the operator
controls, connected locally over wireless ADB-TLS. Goal: extract firmware, decompile, and
identify security issues. No external/production systems were touched; all network endpoints
found are documented, **not** contacted.

## Procedure

### 1. Device triage (adb, root)
- Confirmed the live transport and build identity via `getprop`.
- Build is `userdebug`, so `adb root` succeeded → raw block devices became readable.
- Captured a full `getprop` dump, `getenforce`, and the `/dev/block/by-name` partition map.

### 2. Firmware extraction (stored in [`../firmware/`](../firmware))
- **Raw partitions** (`firmware/partitions/`): streamed active-slot (`_a`) and non-slotted
  partitions off the device with `adb exec-out "su 0 dd if=/dev/block/by-name/<p>"`, each with
  a SHA-256. `super` (2.56 GB dynamic-partition blob), boot chain, vbmeta, bootloader, env,
  misc, frp, metadata were pulled. **`userdata` and the whole disk were deliberately skipped**
  (personal data, not firmware).
- **Boot image unpack** (`firmware/extracted/boot_a/`): `rea extract-firmware` (unblob backend)
  carved the kernel (xz) and ramdisk (gzip) blobs from `boot_a.img`.
- **Live filesystem capture** (`firmware/device-state/`): because the root-owned mount blocks
  REA's output-owner check and `lpunpack` isn't available to split `super`, the read-only
  `/system`, `/vendor`, `/product` content of interest (build.prop files, OTA certs) was read
  directly from the live mounts with root — cleaner than carving and sufficient for review.

### 3. Application analysis (`firmware/apks/`, `firmware/analysis/`)
- Inventoried all 130 APKs across the firmware partitions (`firmware/device-state/apk-inventory.txt`).
- Pulled the custom OEM apps (OTA updater, AppMarket, MosAppStore, auth-Launcher, factory
  menu, FacTest, GSettings) for deep review.
- **Signatures:** `rea inspect-apk-signature` on each.
- **Manifests:** `apktool d -s` → reviewed exported components, `sharedUserId`,
  `usesCleartextTraffic`, privileged permissions.
- **Code:** `jadx` decompiled the OTA updater (2,306 Java files) to trace the update mechanism
  (endpoints, download integrity, package installation).

### 4. Reporting
- Firmware inventory + checksums: [`01-device-and-firmware-inventory.md`](01-device-and-firmware-inventory.md)
- Security findings: (security notes, not included here)

## Limitations / not done
- **Native code** (`.so`, bootloader, TEE) was not decompiled — REA's native path needs a
  Ghidra install that isn't present. The raw partitions are retained so this can be added later.
- `super` was pulled raw but not split into system/vendor/product images (`lpunpack` absent);
  file-level review used the live mounts instead.
- Dynamic/runtime analysis (Frida, traffic interception) was out of scope; findings are static.
- Findings about key reuse/leakage are stated as **risk** — a shared generic signing key was
  observed, but no private key material was recovered or proven leaked.
