#!/usr/bin/env python3
"""Boot profile: where the last boot's time went. Read-only.

Usage: 76-boot-profile.py [--save DIR] [--from DIR]
  (no options)  read logs from the connected device over adb
  --save DIR    also save the raw logs into DIR, to compare builds later
  --from DIR    read logs saved earlier with --save, with no device

Run it right after a boot, on the second boot after a flash (the first is slower), before the logs roll over. It
prints Android's boot stages, the slowest system_server and init steps, gaps in the log, and hints from
docs/13-TUNING.md. Times are seconds since the kernel started. Root (adb root) gives a fuller dmesg.
"""
import os, re, subprocess, sys

def adb(cmd):
    try:
        r = subprocess.run(["adb", "shell", cmd], capture_output=True, text=True, errors="replace", timeout=60)
        return r.stdout.replace("\r", "")
    except Exception as e:
        return ""

def main():
    a = sys.argv[1:]
    save = a[a.index("--save") + 1] if "--save" in a else None
    src = a[a.index("--from") + 1] if "--from" in a else None
    if "-h" in a or "--help" in a:
        print(__doc__); return
    names = {"events": "logcat -b events -d", "all": "logcat -b all -d -v monotonic", "dmesg": "dmesg",
             "props": "getprop", "printk": "cat /proc/sys/kernel/printk", "cmdline": "cat /proc/cmdline"}
    logs = {}
    for k, c in names.items():
        if src:
            p = os.path.join(src, k + ".txt")
            logs[k] = open(p, errors="replace").read() if os.path.exists(p) else ""
        else:
            logs[k] = adb(c)
    if not src and not logs["events"]:
        sys.exit("No logs. Is exactly one device connected and booted? (adb devices)")
    if save:
        os.makedirs(save, exist_ok=True)
        for k, v in logs.items():
            open(os.path.join(save, k + ".txt"), "w").write(v)
        print(f"Saved raw logs to {save}\n")

    # Android's boot stages
    stages = [("boot_progress_start", "Zygote starts (Android framework)"),
              ("boot_progress_system_run", "system_server runs"),
              ("boot_progress_pms_ready", "Package manager ready"),
              ("boot_progress_ams_ready", "Activity manager ready"),
              ("boot_progress_enable_screen", "Screen enabled (home)"),
              ("sf_stop_bootanim", "Boot animation ends")]
    val = {}
    for line in logs["events"].splitlines():
        m = re.search(r"(boot_progress_\w+|sf_stop_bootanim): (\d+)", line)
        if m:
            val[m.group(1)] = int(m.group(2)) / 1000
    print("Android's boot stages (seconds since the kernel started):")
    prev = None
    for k, label in stages:
        if k in val:
            d = f"  (+{val[k] - prev:.1f})" if prev is not None else ""
            print(f"  {val[k]:6.1f}  {label}{d}")
            prev = val[k]
    if not val:
        print("  none found: the event log may have rolled over, or this isn't a fresh boot")

    # system_server steps
    rows, zyg = [], []
    for line in logs["all"].splitlines():
        m = re.search(r"SystemServerTiming(?:Async)?:\s*(.+?) took to complete:\s*(\d+)ms", line)
        if m:
            rows.append((int(m.group(2)), m.group(1)))
        m = re.search(r"Zygote\d*Timing:\s*(.+?) took to complete:\s*(\d+)ms", line)
        if m:
            zyg.append((int(m.group(2)), m.group(1)))
    agg = re.compile(r"^(StartServices|startOtherServices|startBootstrapServices|startCoreServices|OnBootPhase_\d+$|"
                     r"PhaseActivityManagerReady|StartActivityManagerReadyPhase|SystemServerTiming)")
    print("\nSlowest system_server steps (ms; totals of other steps left out):")
    for ms, name in sorted([r for r in rows if not agg.match(r[1])], reverse=True)[:15]:
        print(f"  {ms:6d}  {name[:90]}")
    if zyg:
        print("Zygote:", ", ".join(f"{n} {ms} ms" for ms, n in sorted(zyg, reverse=True)[:4]))

    # init and kernel
    dm = logs["dmesg"].splitlines()
    def strip(l):
        return re.sub(r"^\[[^]]*\]\s*(\[[^]]*\]\s*)?", "", l)
    def ts(l):
        m = re.match(r"\[\s*(\d+\.\d+)\]", l)
        return float(m.group(1)) if m else None
    first = next((ts(l) for l in dm if ts(l) is not None), None)
    zy = val.get("boot_progress_start", 30)
    print(f"\nSlow init steps before zygote (from dmesg):")
    n = 0
    for l in dm:
        t = ts(l)
        if t is None or t > zy:
            continue
        m = re.search(r"took (\d+)ms|took (\d+\.\d+) ?s|waiting took (\d+\.\d+)", l)
        if m:
            v = float(m.group(1)) / 1000 if m.group(1) else float(m.group(2) or m.group(3))
            if v >= 0.15:
                print(f"  {t:6.2f}  {v:5.2f} s  {strip(l)[:100]}")
                n += 1
    if not n:
        print("  none over 0.15 s found")
    gaps = []
    for x, y in zip(dm, dm[1:]):
        tx, ty = ts(x), ts(y)
        if tx is not None and ty is not None and ty <= zy and ty - tx > 0.3:
            gaps.append((ty - tx, tx, strip(x)[:90]))
    if gaps:
        print("Gaps over 0.3 s before zygote (what was logged just before):")
        for g, t, l in sorted(gaps, reverse=True)[:6]:
            print(f"  {t:6.2f}  gap {g:4.2f} s after: {l}")

    # Hints from docs/13
    print("\nHints:")
    hints = 0
    if first is None:
        print("  - No dmesg. Try adb root, then run this again."); hints += 1
    elif first > 1.0:
        print(f"  - dmesg starts at {first:.1f} s, so the kernel's log buffer rolled over. Add log_buf_len=1M to "
              "the vendor command line to see the whole boot."); hints += 1
    early = sum(1 for l in dm if (ts(l) or 99) < 6)
    lv = re.findall(r"(?<![\w.])loglevel=(\d+)", logs["cmdline"])
    console = "console=" in logs["cmdline"]
    if lv and int(lv[-1]) > 4 and console:
        print(f"  - The kernel console prints at loglevel {lv[-1]} (command line values in order: {', '.join(lv)}; the "
              f"last wins), with {early} log lines before 6 s. Each printed line waits for the serial port. "
              "loglevel=4 on the vendor command line saved 6 s on the first device (docs/13, 3d)."); hints += 1
    elif not logs["cmdline"].strip():
        print("  - Couldn't read /proc/cmdline (try adb root). Check the kernel console loglevel: a high one with a "
              "UART console slows the kernel (docs/13, 3d)."); hints += 1
    for ms, name in rows:
        if name == "WaitForDisplay" and ms > 1000:
            print(f"  - WaitForDisplay took {ms} ms. Capture stacks during the wait (tools/78-boot-stacks.sh). On the "
                  "first device it was the GPU driver compiling shaders: service.sf.prime_shader_cache=0 (docs/13, 3b)."); hints += 1
            break
    if "sf_stop_bootanim" in val and "boot_progress_enable_screen" in val:
        tail = val["sf_stop_bootanim"] - val["boot_progress_enable_screen"]
        if tail > 2:
            print(f"  - The animation ran {tail:.1f} s after the screen was enabled. Parts marked 'c' in its desc.txt "
                  "play to the end (docs/13, 3c)."); hints += 1
    if not hints:
        print("  - nothing obvious")
    print("\nCompare against a previous run: --save DIR now, --from DIR later.")

main()
