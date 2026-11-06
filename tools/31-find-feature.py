#!/usr/bin/env python3
"""Searches a stock filesystem for a feature, to find what implements it. Read-only.

Usage: 31-find-feature.py STOCK_DIR REGEX [REGEX...]
Example: 31-find-feature.py stock/fs 'keystone|trapezoid' 'hdmi.?in|tvinput' 'autofocus'

STOCK_DIR can be the fs/ directory from 30-extract-stock.sh, or any tree. It searches inside APK and JAR dex files, native libraries and
binaries, and init and config files. It counts matches per file, with samples.

How to read the result (this is how keystone was traced on the first device):
 - An app with many hits is probably the user-facing tool.
 - services.jar or framework.jar with hits means stock CHANGED THE FRAMEWORK. Read what those classes call: it may only forward to a vendor HAL.
 - A vendor *.so with hits is the implementation, and it's probably already in your image.
 - Then disassemble with: dexdump -d classes.dex (out/host/linux-x86/bin/dexdump in the Android tree), or jadx if you have it.
"""
import os, re, sys, zipfile

SKIP_EXT = (".png", ".jpg", ".webp", ".ogg", ".mp3", ".ttf", ".bmp", ".wav", ".mp4", ".prof", ".profm", ".art", ".vdex", ".oat", ".odex")
TEXT_EXT = (".rc", ".xml", ".prop", ".conf", ".cfg", ".ini", ".kl", ".sh", ".txt", ".json")
MAX = 300 << 20

def strings(data):
    return re.findall(rb"[\x20-\x7e]{4,}", data)

def scan(data, pats):
    found = {}
    for s in strings(data):
        for i, p in enumerate(pats):
            if p.search(s):
                found.setdefault(i, []).append(s.decode("ascii", "replace"))
    return found

def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    root = sys.argv[1]
    raw = sys.argv[2:]
    pats = [re.compile(r.encode(), re.I) for r in raw]
    results = {r: [] for r in raw}
    files = 0
    for d, _, fs in os.walk(root):
        for f in fs:
            p = os.path.join(d, f)
            if os.path.islink(p) or not os.path.isfile(p) or f.lower().endswith(SKIP_EXT):
                continue
            try:
                if os.path.getsize(p) > MAX:
                    continue
                if f.endswith((".apk", ".jar", ".apex", ".capex")) and zipfile.is_zipfile(p):
                    blobs = []
                    with zipfile.ZipFile(p) as z:
                        for n in z.namelist():
                            if n.endswith(".dex") or (n.endswith(".so") and "armeabi" in n) or n == "AndroidManifest.xml":
                                blobs.append(z.read(n))
                    data = b"\0".join(blobs)
                else:
                    with open(p, "rb") as fh:
                        head = fh.read(4)
                        if not (head == b"\x7fELF" or f.endswith(TEXT_EXT)):
                            continue
                        data = head + fh.read()
            except (OSError, zipfile.BadZipFile):
                continue
            files += 1
            for i, hits in scan(data, pats).items():
                results[raw[i]].append((len(hits), os.path.relpath(p, root), sorted(set(hits))[:4]))
    print(f"Searched {files} files.\n")
    for r in raw:
        print(f"=== {r}")
        for n, p, sample in sorted(results[r], reverse=True)[:25]:
            print(f"{n:6} {p}")
            for s in sample:
                print(f"         {s[:90]}")
        if not results[r]:
            print("  no matches")
        print()

main()
