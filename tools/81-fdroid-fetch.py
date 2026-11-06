#!/usr/bin/env python3
"""Downloads apps from F-Droid and checks each against the SHA-256 in F-Droid's index. Downloaded APKs are untrusted until checked.

Usage: 81-fdroid-fetch.py OUTPUT_DIR --abi armeabi-v7a PACKAGE...
Picks the newest build that supports the ABI. A package not in the main repository is reported and skipped: look for an official
release elsewhere, and never pick an unofficial mirror without telling the user. Run with python3 -I.
"""
import argparse, hashlib, json, os, urllib.request

UA = {"User-Agent": "Mozilla/5.0"}
ap = argparse.ArgumentParser()
ap.add_argument("out"); ap.add_argument("packages", nargs="+"); ap.add_argument("--abi", default="armeabi-v7a")
ap.add_argument("--repo", default="https://f-droid.org/repo")
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)
with urllib.request.urlopen(urllib.request.Request(a.repo + "/index-v2.json", headers=UA), timeout=180) as r:
    idx = json.load(r)["packages"]
bad = 0
for p in a.packages:
    e = idx.get(p)
    if not e:
        print(f"{p}: NOT IN THIS REPOSITORY")
        bad = 1
        continue
    versions = sorted(e["versions"].values(), key=lambda v: -v["manifest"]["versionCode"])
    pick = next((v for v in versions if not v["manifest"].get("nativecode") or a.abi in v["manifest"]["nativecode"]), None)
    if not pick:
        print(f"{p}: no build for {a.abi}")
        bad = 1
        continue
    m, f = pick["manifest"], pick["file"]
    dest = os.path.join(a.out, p + ".apk")
    with urllib.request.urlopen(urllib.request.Request(a.repo + f["name"], headers=UA), timeout=300) as r, open(dest, "wb") as w:
        while True:
            b = r.read(1 << 20)
            if not b:
                break
            w.write(b)
    with open(dest, "rb") as fh:
        h = hashlib.sha256(fh.read()).hexdigest()
    if h != f["sha256"]:
        os.remove(dest)
        print(f"{p}: HASH MISMATCH, file deleted")
        bad = 1
    else:
        print(f"{p}: {m['versionName']} ({m['versionCode']}), native {m.get('nativecode')}, hash ok")
raise SystemExit(bad)
