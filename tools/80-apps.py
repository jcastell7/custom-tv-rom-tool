#!/usr/bin/env python3
"""Generates a build module that preinstalls APKs without breaking them. Then add to device.mk:
    $(call inherit-product-if-exists, vendor/custom-apps/apps.mk)

Usage: 80-apps.py CONFIG.json ANDROID_TREE     Example config: templates/apps.example.json

Handles four traps that each cost a failed boot or a missing app:
 1. Publisher-signed APKs must stay byte-identical, or Android rejects them (No APK Signature Scheme v2 signature).
 2. Compressed native libraries aren't extracted for system apps, so they're copied to app/NAME/lib/ABI beside the APK.
 3. privileged apps need a privapp-permissions allowlist, or system_server aborts at boot.
 4. platform-signed apps need the build to re-sign them.

Config fields for each entry in "apps":
  apk         path to the APK
  name        module name
  partition   product (default), system_ext or system
  privileged  true or false, default false
  certificate "PRESIGNED" (default; for apps from their publishers) or "platform" (stock apps using system permissions)
Top-level: "abi" is the native ABI to install (default armeabi-v7a); "lib_dir" is arm or arm64 (default arm); "copies" lists
{"src": path, "dest": "system/lib/x.so"} for extra files. Don't use this for an app that warns about being a system app (Magisk: use adb install).
"""
import json, os, re, shutil, subprocess, sys, zipfile

def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    cfg = json.load(open(sys.argv[1]))
    tree = sys.argv[2]
    out = f"{tree}/vendor/custom-apps"
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(f"{out}/apps")
    abi, libdir = cfg.get("abi", "armeabi-v7a"), cfg.get("lib_dir", "arm")
    aapt = f"{tree}/out/host/linux-x86/bin/aapt2"
    mk, names, copies = ["LOCAL_PATH := $(call my-dir)", ""], [], []
    dests = {"product": "$(TARGET_COPY_OUT_PRODUCT)", "system_ext": "$(TARGET_COPY_OUT_SYSTEM_EXT)", "system": "$(TARGET_COPY_OUT_SYSTEM)"}
    xml = ['<?xml version="1.0" encoding="utf-8"?>', "<permissions>"]
    for a in cfg["apps"]:
        name, part = a["name"], a.get("partition", "product")
        cert, priv = a.get("certificate", "PRESIGNED"), a.get("privileged", False)
        apk = f"{out}/apps/{name}.apk"
        shutil.copy(a["apk"], apk)
        lines = ["include $(CLEAR_VARS)", f"LOCAL_MODULE := {name}", "LOCAL_MODULE_CLASS := APPS", "LOCAL_MODULE_TAGS := optional",
                 f"LOCAL_SRC_FILES := apps/{name}.apk", "LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)",
                 f"LOCAL_CERTIFICATE := {cert}", "LOCAL_DEX_PREOPT := false", "LOCAL_ENFORCE_USES_LIBRARIES := false"]
        if part == "product":
            lines.append("LOCAL_PRODUCT_MODULE := true")
        elif part == "system_ext":
            lines.append("LOCAL_SYSTEM_EXT_MODULE := true")
        if priv:
            lines.append("LOCAL_PRIVILEGED_MODULE := true")
        if cert == "PRESIGNED":
            lines.append(f"LOCAL_REPLACE_PREBUILT_APK_INSTALLED := $(LOCAL_PATH)/apps/{name}.apk")
            folder = "priv-app" if priv else "app"
            with zipfile.ZipFile(apk) as z:
                for i in z.infolist():
                    if re.fullmatch(rf"lib/{re.escape(abi)}/[^/]+\.so", i.filename) and i.compress_type != 0:
                        os.makedirs(f"{out}/files/{name}", exist_ok=True)
                        base = os.path.basename(i.filename)
                        with z.open(i) as s, open(f"{out}/files/{name}/{base}", "wb") as d:
                            shutil.copyfileobj(s, d)
                        copies.append(f"vendor/custom-apps/files/{name}/{base}:{dests[part]}/{folder}/{name}/lib/{libdir}/{base}")
        mk += lines + ["include $(BUILD_PREBUILT)", ""]
        names.append(name)
        if priv:
            dump = subprocess.run([aapt, "dump", "permissions", apk], capture_output=True, text=True, check=True).stdout
            pkg = re.search(r"package: (\S+)", dump).group(1)
            xml.append(f'    <privapp-permissions package="{pkg}">')
            xml += [f'        <permission name="{p}"/>' for p in sorted(set(re.findall(r"uses-permission: name='([^']+)'", dump)))]
            xml.append("    </privapp-permissions>")
    xml.append("</permissions>")
    os.makedirs(f"{out}/files", exist_ok=True)
    with open(f"{out}/files/privapp-permissions-custom.xml", "w") as f:
        f.write("\n".join(xml) + "\n")
    copies.append("vendor/custom-apps/files/privapp-permissions-custom.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/privapp-permissions-custom.xml")
    for i, c in enumerate(cfg.get("copies", [])):
        base = os.path.basename(c["src"])
        os.makedirs(f"{out}/files/extra{i}", exist_ok=True)
        shutil.copy(c["src"], f"{out}/files/extra{i}/{base}")
        part, rest = c["dest"].split("/", 1)
        copies.append(f"vendor/custom-apps/files/extra{i}/{base}:{dests.get(part, '$(TARGET_COPY_OUT_' + part.upper() + ')')}/{rest}")
    open(f"{out}/Android.mk", "w").write("\n".join(mk))
    with open(f"{out}/apps.mk", "w") as f:
        f.write("PRODUCT_PACKAGES += \\\n" + " \\\n".join("    " + n for n in names) + "\n\n")
        f.write("PRODUCT_COPY_FILES += \\\n" + " \\\n".join("    " + c for c in sorted(copies)) + "\n")
    print(f"{len(names)} apps, {len(copies)} extra files in {out}")

main()
