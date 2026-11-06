#!/usr/bin/env python3
"""Pre-flash gate. Reads build output and stock files, never touches a device. Run it before EVERY flash.

Every check here exists because skipping it cost a real failed boot on the hermes project (docs/07).
FAIL means don't flash. WARN means read it and decide. On success it records image hashes in GATE_PASS for 60-flash.sh.

Usage:
  50-gate.py --tree ANDROID_TREE --product NAME --stock-vendor DIR [--stock-images DIR] [--arch32] [--only a,b]
             [--allow-file FILE]

  --stock-vendor  stock /vendor tree (extracted from the backup's super or from a blob dump)
  --stock-images  directory with stock boot images, named boot.img or boot_a.img, and so on (a backup directory works)
  --arch32        the kernel is 32-bit: also check BPF programs for instructions its JIT can't run
  --allow-file    text file of finding IDs to downgrade to INFO, one per line, each with a comment saying why

Checks: headers, bootconfig, fstab, vintf, symbols, collisions, vendor, props, bpf, apks, launchers, sizes
"""
import argparse, collections, glob, hashlib, json, os, re, struct, subprocess, sys, zipfile

class R:
    fails, warns, infos = [], [], []
    allow = set()

def fail(i, m):
    (R.infos if i in R.allow else R.fails).append(f"[{i}] {m}")
def warn(i, m):
    (R.infos if i in R.allow else R.warns).append(f"[{i}] {m}")
def info(m):
    R.infos.append(m)

def run(*a, **k):
    return subprocess.run(a, capture_output=True, text=True, errors="replace", **k).stdout

def is_elf(p):
    try:
        with open(p, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False

# ---- boot images ----
def parse_boot(path):
    with open(path, "rb") as f:
        d = f.read()
    if d[:8] == b"ANDROID!":
        return {"kind": "boot", "version": struct.unpack_from("<I", d, 40)[0], "size": len(d)}
    if d[:8] == b"VNDRBOOT":
        ver, page = struct.unpack_from("<II", d, 8)
        ram = struct.unpack_from("<I", d, 24)[0]
        cmd = d[28:28 + 2048].split(b"\0")[0].decode(errors="replace")
        name = d[2080:2096].split(b"\0")[0].decode(errors="replace")
        hsize, dtb = struct.unpack_from("<II", d, 2096)
        r = {"kind": "vendor", "version": ver, "name": name, "cmdline": cmd, "ramdisk": ram, "dtb": dtb, "size": len(d), "bootconfig": ""}
        if ver >= 4:
            tbl, _, _, bc = struct.unpack_from("<IIII", d, 2112)
            align = lambda x: (x + page - 1) // page * page
            off = align(hsize) + align(ram) + align(dtb) + align(tbl)
            r["bootconfig"] = d[off:off + bc].split(b"\0")[0].decode(errors="replace")
        return r
    return {"kind": "unknown", "size": len(d)}

def find_stock(stock, name):
    if not stock:
        return None
    for n in (name + ".img", name + "_a.img"):
        p = os.path.join(stock, n)
        if os.path.exists(p):
            return p
    return None

def bc_keys(text):
    return [l.split("=", 1)[0].strip() for l in text.splitlines() if "=" in l and l.strip()]

def check_headers(a, O):
    for n in ("boot", "init_boot", "vendor_boot"):
        ours, st = os.path.join(O, n + ".img"), find_stock(a.stock_images, n)
        if not os.path.exists(ours):
            if st:
                fail(f"headers.{n}.missing", f"stock has {n}, the build produced no {n}.img")
            continue
        o = parse_boot(ours)
        if not st:
            warn(f"headers.{n}.nostock", f"no stock {n} image to compare; pass --stock-images")
            continue
        s = parse_boot(st)
        if o.get("version") != s.get("version"):
            fail(f"headers.{n}.version", f"{n}: header version {o.get('version')}, stock {s.get('version')}. A bootloader can misread a wrong version: hermes copied 448 MiB and hung on init_boot v0 (fix: BOARD_MKBOOTIMG_INIT_ARGS += --header_version N).")
        if o["size"] > s["size"]:
            fail(f"headers.{n}.size", f"{n}: {o['size']} bytes is larger than the stock image of {s['size']} bytes")
        if n == "vendor_boot" and o["kind"] == "vendor" and s["kind"] == "vendor":
            if o["name"] != s["name"]:
                fail("headers.vendor_boot.name", f"vendor_boot name is '{o['name']}', stock '{s['name']}'. u-boot can branch on it: on hermes 'arm' meant run a 32-bit OS (fix: BOARD_MKBOOTIMG_ARGS += --board NAME).")
            if s["ramdisk"] > 4 << 20 and o["ramdisk"] < 1 << 20:
                warn("headers.vendor_boot.ramdisk", f"vendor ramdisk is {o['ramdisk']} bytes, stock {s['ramdisk']}. Stock has recovery and fastbootd there. Without BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT this build has NO way back.")

def check_bootconfig(a, O):
    p, st = os.path.join(O, "vendor_boot.img"), find_stock(a.stock_images, "vendor_boot")
    if not os.path.exists(p):
        return
    o = parse_boot(p)
    keys = bc_keys(o.get("bootconfig", ""))
    for k, c in collections.Counter(keys).items():
        if c > 1:
            fail("bootconfig.duplicate", f"bootconfig defines {k} {c} times. The kernel rejects the WHOLE bootconfig ('Value is redefined').")
    if st:
        s = parse_boot(st)
        sk = set(bc_keys(s.get("bootconfig", "")))
        extra = set(keys) - sk
        for k in sorted(extra):
            warn(f"bootconfig.extra.{k}", f"bootconfig adds {k}, which stock doesn't have. If the bootloader adds it too, the kernel rejects everything. Safest is to match stock exactly.")
        for k in sorted(sk - set(keys)):
            warn(f"bootconfig.missing.{k}", f"stock bootconfig has {k}, this build doesn't")
        so, oo = set(s.get("cmdline", "").split()), set(o.get("cmdline", "").split())
        for k in sorted(so - oo):
            warn(f"cmdline.missing.{k.split('=')[0]}", f"stock vendor cmdline has '{k}', this build doesn't")
        for k in sorted(oo - so):
            info(f"cmdline adds '{k}'")
        if "printk.devkmsg=on" in oo:
            warn("cmdline.devkmsg", "printk.devkmsg=on sends userspace logs to the kernel log. With a UART console at a high log level this can slow boot enough to time out drivers (hermes lost Wi-Fi and Bluetooth). Lower the console level before drivers load.")

def check_fstab(a, O):
    tabs = glob.glob(os.path.join(O, "vendor_ramdisk/first_stage_ramdisk/fstab.*")) + glob.glob(os.path.join(O, "ramdisk/fstab.*"))
    if not tabs:
        fail("fstab.firststage", "no fstab in any boot ramdisk, so first-stage init can't mount system or vendor")
        return
    root = os.path.join(O, "root")
    for line in open(tabs[0], errors="replace"):
        f = line.split()
        if len(f) < 5 or f[0].startswith("#"):
            continue
        mp, fstype, flags = f[1], f[2], f[4]
        # emmc entries are raw partitions for recovery, and voldmanaged is removable storage. Neither needs a mount point.
        if fstype not in ("ext4", "f2fs", "erofs", "vfat", "squashfs") or "voldmanaged" in flags or "recoveryonly" in flags:
            continue
        if mp.startswith("/") and mp not in ("/", "/system", "/vendor", "/product", "/system_ext", "/odm", "/data"):
            if not os.path.isdir(root + mp):
                fail("fstab.mountpoint" + mp.replace("/", "."), f"fstab mounts {mp}, which isn't in the system root. SwitchRoot or mount_all fails (fix: BOARD_USES_METADATA_PARTITION or BOARD_ROOT_EXTRA_FOLDERS, plus SELinux labels).")

def check_vintf(a, O, T):
    tool = os.path.join(T, "out/host/linux-x86/bin/checkvintf")
    if os.path.exists(tool):
        apex = os.path.join(O, "apex")
        out = run(tool, "--check-compat", f"--dirmap=/system:{O}/system", f"--dirmap=/vendor:{O}/vendor", f"--dirmap=/odm:{O}/odm",
                  f"--dirmap=/product:{O}/product", f"--dirmap=/system_ext:{O}/system_ext", f"--dirmap=/apex:{apex}",
                  "-D", "ro.product.first_api_level=34", "-D", "ro.boot.product.hardware.sku=", cwd=T)
        if "COMPATIBLE" not in out.splitlines()[-1:] and not out.rstrip().endswith("COMPATIBLE"):
            warn("vintf.compat", "checkvintf didn't report COMPATIBLE: " + "; ".join(out.splitlines()[-3:])[:300])
    seen = collections.defaultdict(list)
    for f in glob.glob(O + "/vendor/etc/vintf/manifest.xml") + glob.glob(O + "/vendor/etc/vintf/manifest/*.xml") + glob.glob(O + "/apex/*/etc/vintf/*.xml"):
        for h in re.findall(r"<hal[^>]*>.*?</hal>", open(f, errors="replace").read(), re.S):
            m = re.search(r"<name>(.+?)</name>", h)
            for q in re.findall(r"<fqname>(.+?)</fqname>", h):
                seen[m.group(1), q].append(os.path.basename(f))
    for (n, q), v in seen.items():
        if len(v) > 1:
            fail("vintf.duplicate", f"{n} {q} is declared in {v}. One duplicate makes servicemanager treat the WHOLE device manifest as null, and nothing can find any HAL.")

NOISE = re.compile(r"^(mem[a-z]*|str[a-z]*|stp[a-z]*|wcs[a-z]*|wmem[a-z]*|__[a-z]+_chk|__mem.*|__str.*|__aeabi.*|__cxa.*|__gnu.*|__emutls.*)$")
_cache = {}
def elfinfo(p):
    if p in _cache:
        return _cache[p]
    d = run("readelf", "-d", "-W", p)
    need = re.findall(r"\(NEEDED\).*\[(.+?)\]", d)
    und, defd = set(), set()
    for l in run("readelf", "--dyn-syms", "-W", p).splitlines():
        f = l.split()
        if len(f) < 8 or not f[0].rstrip(":").isdigit():
            continue
        n = f[7].split("@")[0]
        if f[6] == "UND":
            if f[4] != "WEAK" and n:
                und.add(n)
        else:
            defd.add(n)
    _cache[p] = (need, und, defd)
    return _cache[p]

def check_symbols(a, O):
    dirs = [O + "vendor/lib64", O + "vendor/lib", O + "vendor/lib64/hw", O + "vendor/lib/hw", O + "vendor/lib/egl", O + "system/lib64", O + "system/lib"]
    dirs += glob.glob(O + "apex/com.android.runtime*/lib*/bionic") + glob.glob(O + "apex/com.android.i18n/lib*") + glob.glob(O + "apex/com.android.vndk*/lib*")
    def find(n):
        for d in dirs:
            p = os.path.join(d, n)
            if os.path.isfile(p) and is_elf(p):
                return p
        return None
    roots = []
    for sub in ("vendor/bin", "vendor/bin/hw", "vendor/lib", "vendor/lib/hw", "vendor/lib/egl", "vendor/lib/soundfx", "vendor/lib/mediadrm", "vendor/lib64", "vendor/lib64/hw"):
        d = O + sub
        if os.path.isdir(d):
            for x in sorted(os.listdir(d)):
                p = os.path.join(d, x)
                if os.path.isfile(p) and not os.path.islink(p) and is_elf(p):
                    roots.append(p)
    # LL-NDK and APEX libraries that may not be found in the output tree in every layout.
    missing_libs = collections.defaultdict(list)
    bad = []
    for r in roots:
        need, und, own = elfinfo(r)
        seen, q, prov = set(), list(need), set(own)
        while q:
            n = q.pop()
            if n in seen:
                continue
            seen.add(n)
            p = find(n)
            if not p:
                missing_libs[n].append(r.replace(O, ""))
                continue
            nn, _, dd = elfinfo(p)
            prov |= dd
            q += nn
        miss = sorted(x for x in und - prov if not NOISE.match(x))
        if miss:
            bad.append((r.replace(O, ""), miss))
    info(f"symbol scan: {len(roots)} vendor ELF files")
    for lib, users in sorted(missing_libs.items()):
        fail(f"symbols.lib.{lib}", f"{lib} isn't in the image, needed by {users[:3]} ({len(users)} files). On a device with no VNDK APEX, stock libraries must be added as .vendor modules or copies (docs/04).")
    for f, m in bad:
        fail("symbols.unresolved." + os.path.basename(f), f"{f} needs missing symbols {m[:5]}. This fails at load with 'cannot locate symbol'. Fix with a shim library and patchelf --add-needed.")

def check_collisions(a, O, T):
    """A stock library replaced by an unrelated tree module with the same name. hermes installed Qualcomm's vendor.display.config@1.0."""
    sv = a.stock_vendor
    mi = {}
    p = O + "module-info.json"
    if os.path.exists(p):
        for name, m in json.load(open(p)).items():
            for i in m.get("installed", []):
                mi[i] = (name, m.get("path"))
    for sub in ("lib", "lib64", "lib/hw", "lib64/hw"):
        d = os.path.join(sv, sub)
        if not os.path.isdir(d):
            continue
        for x in sorted(os.listdir(d)):
            s, o = os.path.join(d, x), os.path.join(O, "vendor", sub, x)
            if not (os.path.isfile(s) and os.path.isfile(o) and is_elf(s) and is_elf(o)):
                continue
            with open(s, "rb") as f1, open(o, "rb") as f2:
                if f1.read() == f2.read():
                    continue
            _, _, sd = elfinfo(s)
            _, _, od = elfinfo(o)
            lost = sorted(n for n in sd - od if not NOISE.match(n))
            where = mi.get(f"out/target/product/{a.product}/vendor/{sub}/{x}", ("?", ["?"]))
            path = (where[1] or ["?"])[0]
            foreign = bool(re.search(r"(^|/)(qcom|qcom-caf|mediatek|nxp|samsung|broadcom|lineage)[/-]", path))
            if x.startswith("vendor.") and lost:
                fail(f"collision.{x}", f"{x} is built from {path} and differs from stock, losing {len(lost)} symbols such as {lost[:3]}. An unrelated vendor HAL can share the name, and calls then fail with HwBinder Error (-74) UNKNOWN_TRANSACTION. Rename the stock library with patchelf.")
            elif foreign:
                warn(f"collision.{x}", f"{x} comes from {path}, which looks like another vendor's code, not stock's")
            elif len(lost) > 20:
                warn(f"collision.{x}", f"{x} differs from stock and lacks {len(lost)} of its exported symbols, such as {lost[:3]}")

def check_vendor(a, O, T):
    sv = a.stock_vendor
    missing = []
    for root, _, files in os.walk(sv):
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), sv)
            if not os.path.lexists(os.path.join(O, "vendor", rel)):
                missing.append(rel)
    groups = collections.Counter(("/".join(m.split("/")[:2]) if "/" in m else m) for m in missing)
    info(f"vendor: {len(missing)} stock files aren't in the image: {groups.most_common(8)}")
    crit = [m for m in missing if re.search(r"(^bin/hw/|^lib(64)?/hw/|optee|\.ta$|^etc/init/|^etc/vintf/|keylayout|^etc/permissions/|^firmware/|\.ko$)", m)]
    for m in crit[:60]:
        warn("vendor.missing." + m, f"stock vendor file isn't in the image: {m}")

DANGEROUS = {
    "ro.vndk.version": "only valid if a VNDK APEX ships; otherwise the linker config breaks",
    "ro.incremental.enable": "only valid if that module ships",
    "ro.lmk.use_new_strategy": "false keeps the old lmkd strategy, which ignores swap and kills on-screen apps; hermes broke Google sign-in this way",
    "ro.lmk.critical": "low values let lmkd kill nearly anything in the old strategy",
    "ro.lmk.critical_upgrade": "belongs to the old lmkd strategy",
    "ro.lmk.upgrade_pressure": "belongs to the old lmkd strategy",
    "ro.lmk.downgrade_pressure": "belongs to the old lmkd strategy",
    "persist.bluetooth.bqr.event_mask": "enables a vendor HCI command the controller may reject; hermes crash-looped Bluetooth until the shim handled it",
}
IMPORTANT = re.compile(r"^(ro\.hardware\.egl|ro\.hardware\.vulkan|ro\.opengles\.version|ro\.sf\.lcd_density|ro\.surface_flinger\.|ro\.vendor\.build\.security_patch|ro\.vendor\.boot_security_patch|dalvik\.vm\.heap|ro\.config\.low_ram|ro\.hdmi\.)")

def props(path):
    d = {}
    if os.path.exists(path):
        for l in open(path, errors="replace"):
            l = l.strip()
            if l and not l.startswith(("#", "import")) and "=" in l:
                k, v = l.split("=", 1)
                d[k] = v
    return d

def check_props(a, O):
    s, o = props(os.path.join(a.stock_vendor, "build.prop")), props(O + "vendor/build.prop")
    for k, why in DANGEROUS.items():
        if k in o:
            v = o[k]
            if (k == "ro.lmk.use_new_strategy" and v == "true") or (k == "ro.vndk.version" and glob.glob(O + "apex/com.android.vndk*")):
                continue
            warn(f"props.dangerous.{k}", f"{k}={v} is set: {why}")
    for k, v in s.items():
        if IMPORTANT.match(k) and o.get(k, "") in ("",):
            fail(f"props.missing.{k}", f"{k}={v} is in stock's vendor build.prop but empty or absent here. Our build.prop is generated, not copied, and keymint aborts on an empty security_patch while the GPU needs ro.hardware.egl.")
    swap_script = glob.glob(O + "vendor/bin/*swap*")
    if swap_script and "ro.lmk.swap_free_low_percentage" not in o:
        warn("props.lmk.swap", "the image adds swap, but ro.lmk.swap_free_low_percentage isn't set. lmkd compares easily reclaimable RAM with 10% of TOTAL swap, so a large swap on low RAM makes it kill with swap free. Consider 3.")
    missing = [k for k in s if k not in o]
    info(f"props: {len(missing)} stock vendor properties aren't set here. Review with care; don't copy them blindly.")

BAD_OPS = {"3f": "64-bit div", "37": "64-bit div", "9f": "64-bit mod", "97": "64-bit mod", "db": "64-bit atomic", "c3": "32-bit atomic"}
def check_bpf(a, O, T):
    tools = glob.glob(T + "/prebuilts/clang/host/linux-x86/*/bin/llvm-objdump")
    if not tools:
        warn("bpf.notool", "no llvm-objdump found")
        return
    od = sorted(tools)[-1]
    for f in glob.glob(O + "apex/com.android.tethering/etc/bpf/**/netd.o", recursive=True):
        sec, found = None, collections.defaultdict(set)
        for l in run(od, "-d", f).splitlines():
            m = re.match(r"Disassembly of section (.+):", l)
            if m:
                sec = m.group(1)
                continue
            m = re.match(r"\s*[0-9a-f]+:\s+([0-9a-f]{2}) ", l)
            if m and m.group(1) in BAD_OPS:
                found[sec].add(BAD_OPS[m.group(1)])
        for s, ops in found.items():
            fail(f"bpf.{s}", f"netd.o section {s} uses {sorted(ops)}. The 32-bit ARM JIT can't run these (BPF_JIT_ALWAYS_ON gives ENOTSUPP), netd aborts, and zygote restarts forever. See templates/patches.")

def check_apks(a, O, T):
    aapt = T + "/out/host/linux-x86/bin/aapt2"
    if not os.path.exists(aapt):
        return
    for partition in ("product", "system_ext", "system"):
        for f in glob.glob(f"{O}{partition}/app/*/*.apk") + glob.glob(f"{O}{partition}/priv-app/*/*.apk"):
            try:
                with zipfile.ZipFile(f) as z:
                    comp = [i.filename for i in z.infolist() if re.match(r"lib/[^/]+/.*\.so$", i.filename) and i.compress_type != 0]
                    arches = {i.filename.split("/")[1] for i in z.infolist() if re.match(r"lib/[^/]+/.*\.so$", i.filename)}
            except zipfile.BadZipFile:
                fail("apks.bad." + os.path.basename(f), f"{f} isn't a valid zip")
                continue
            if comp:
                libdir = os.path.join(os.path.dirname(f), "lib")
                if not os.path.isdir(libdir):
                    warn("apks.jni." + os.path.basename(f), f"{f} has compressed native libraries and no lib/ directory. Android doesn't extract these for system apps, so it crashes at load.")
    priv = glob.glob(f"{O}*/priv-app/*/*.apk")
    allow = ""
    for x in glob.glob(f"{O}*/etc/permissions/*.xml") + glob.glob(f"{O}system/etc/permissions/*.xml"):
        allow += open(x, errors="replace").read()
    for f in priv:
        out = run(aapt, "dump", "permissions", f)
        m = re.search(r"package: (\S+)", out)
        if m and f"package=\"{m.group(1)}\"" not in allow and re.search(r"(system|product|system_ext)/priv-app/Aw|Stock", f):
            warn("apks.privapp." + m.group(1), f"priv-app {m.group(1)} has no privapp-permissions entry. Android can refuse to boot: 'Signature|privileged permissions not in privapp-permissions allowlist'.")

def check_launchers(a, O, T):
    aapt = T + "/out/host/linux-x86/bin/aapt2"
    if not os.path.exists(aapt):
        return
    homes = []
    for f in glob.glob(f"{O}*/app/*/*.apk") + glob.glob(f"{O}*/priv-app/*/*.apk"):
        if "android.intent.category.HOME" in run(aapt, "dump", "xmltree", "--file", "AndroidManifest.xml", f):
            homes.append(os.path.relpath(f, O))
    info(f"HOME handlers: {homes}")
    if any("/Settings/" in h for h in homes):
        warn("launchers.settings", "phone Settings is installed on a TV build. It's a HOME handler and uses memory.")
    wizards = [h for h in homes if re.search(r"SetupWizard|SetupWraith", h)]
    if len(wizards) > 1:
        warn("launchers.wizards", f"more than one setup wizard: {wizards}. On low RAM, Google's SetupWraith left hermes with a black screen, and Lineage's wizard exits when it's present.")

def check_sizes(a, O):
    sizes = os.path.join(a.stock_images or "", "layout", "partition-sizes.txt")
    if not os.path.exists(sizes):
        return
    part = {}
    for l in open(sizes):
        f = l.split()
        if len(f) == 2 and f[0].isdigit():
            part[f[1]] = int(f[0])
    for img in glob.glob(O + "*.img"):
        n = os.path.basename(img)[:-4]
        cap = part.get(n) or part.get(n + "_a")
        if cap and os.path.getsize(img) > cap:
            fail(f"sizes.{n}", f"{n}.img is {os.path.getsize(img)} bytes, the partition holds {cap}")

CHECKS = ["headers", "bootconfig", "fstab", "vintf", "symbols", "collisions", "vendor", "props", "bpf", "apks", "launchers", "sizes"]

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tree", required=True); ap.add_argument("--product", required=True)
    ap.add_argument("--stock-vendor", required=True); ap.add_argument("--stock-images")
    ap.add_argument("--arch32", action="store_true"); ap.add_argument("--only"); ap.add_argument("--allow-file")
    a = ap.parse_args()
    T = os.path.abspath(a.tree)
    O = f"{T}/out/target/product/{a.product}/"
    if not os.path.isdir(O):
        sys.exit(f"no build output at {O}")
    if a.allow_file:
        R.allow = {l.split("#")[0].strip() for l in open(a.allow_file) if l.split("#")[0].strip()}
    only = a.only.split(",") if a.only else CHECKS
    calls = {"headers": lambda: check_headers(a, O), "bootconfig": lambda: check_bootconfig(a, O), "fstab": lambda: check_fstab(a, O),
             "vintf": lambda: check_vintf(a, O, T), "symbols": lambda: check_symbols(a, O), "collisions": lambda: check_collisions(a, O, T),
             "vendor": lambda: check_vendor(a, O, T), "props": lambda: check_props(a, O),
             "bpf": lambda: check_bpf(a, O, T) if a.arch32 else info("bpf: skipped, no --arch32"),
             "apks": lambda: check_apks(a, O, T), "launchers": lambda: check_launchers(a, O, T), "sizes": lambda: check_sizes(a, O)}
    for c in only:
        print(f"-- {c}", flush=True)
        calls[c]()
    print()
    for x in R.infos:
        print("INFO", x[:260])
    for x in R.warns:
        print("WARN", x[:330])
    for x in R.fails:
        print("FAIL", x[:360])
    print(f"\n{len(R.fails)} FAIL, {len(R.warns)} WARN")
    gate = os.path.join(O, "GATE_PASS")
    if os.path.exists(gate):
        os.remove(gate)
    if R.fails:
        print("Don't flash. Fix each FAIL, or put its ID in an --allow-file with a comment saying why it's safe.")
        return 1
    if only == CHECKS:
        with open(gate, "w") as f:
            for img in sorted(glob.glob(O + "*.img")):
                h = hashlib.sha256()
                with open(img, "rb") as i:
                    for c in iter(lambda: i.read(1 << 20), b""):
                        h.update(c)
                f.write(f"{h.hexdigest()}  {os.path.basename(img)}\n")
        print(f"Gate passed. Wrote {gate}, which 60-flash.sh checks.")
    return 0

sys.exit(main())
