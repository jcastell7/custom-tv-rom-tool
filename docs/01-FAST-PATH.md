# The fast path

> **⚠️ WARNING: this process could very well fully and permanently brick your device.** Only use it on a device you own and can afford to lose. It's provided as is, with no warranty, and **we accept no responsibility** for how it's used or what happens. Not affiliated with LineageOS in any way: we just use and recommend their work, so [please donate to them](https://lineageos.org/about/) when you can. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

This is the order I'd use if I started over with what the first device taught me. The first project reached a working ROM after about 25 flashes, and most of them were preventable. Follow the phases in order. Don't skip a gate.

The phase times below assume a build tree is already synced, and are rough. For the whole picture, see "How long it takes".

## How long it takes

**Tell the user this before you start.** These come from the first project (12 threads, 31 GB RAM, NVMe SSD). "Measured" means taken from build logs, file timestamps or session logs. "Estimate" is my judgement, not tested on a second device.

### One complete ROM, from nothing

| Stage | Time | Basis |
|---|---|---|
| Computer setup and tools | 30–60 minutes, plus waiting for a `sudo` user | Estimate |
| Sync LineageOS | Under about 1 hour on that connection; **plan for 2–6 hours** on ordinary broadband (about 160 GB) | Measured from tree timestamps; the plan figure is an estimate |
| **First complete compile** | **About 5.5 hours** | Calculated: Ninja recorded about 66 CPU-hours across all steps. Timestamps are consistent with this. Not a single stopwatch run |
| Device backup | Under 1 hour on USB 2 for about 3 GB without userdata | Estimate |
| Studying stock, proving a way back | 1–3 hours. **Days if no route exists** | Estimate |
| Device tree, blobs, fixing build errors | 2–6 hours, with `docs/08` | Estimate |
| Boot failures | 1–3 hours with the gate | Estimate |
| Hardware and features | 3–8 hours | Estimate |
| Apps, root, cleanup | 1–2 hours | Estimate |

**Total: expect about 2–4 days in practice,** of which about 15–25 hours is hands-on and the rest is waiting. Add to that time for the user's own testing. Most of the waiting is the sync and first compile, which can run overnight, and need no device. **A device with its own problems can take much longer, and a device with no way back can't be scheduled at all.**

### What the first project actually took

| Milestone | Clock time | Hands-on time |
|---|---|---|
| Start to `sys.boot_completed` | About 46 hours | About 23 hours |
| Start to all features installed | About 50 hours | About 26 hours |

Hands-on time is what's left after subtracting pauses over an hour. It still includes waiting on builds. It **also includes the rescue of the stuck device, and about 25 flashes**, so with this toolkit it should be shorter. Those hours don't include user testing, or the firmware extraction done before this session. Some features still awaited the user's confirmation when this was written.

### Scaling the first compile

About 66 CPU-hours divided by your threads, with these rough results:

| Computer | First compile |
|---|---|
| 32+ threads, NVMe | 2–3 hours |
| 12 threads, NVMe | 5–6 hours (the only one with real data) |
| 8 threads, SSD | 8–10 hours |
| 4 threads, SSD | 16–24 hours |
| Spinning disk, or RAM under 16 GB | Much longer, and harder to predict |

Only the 12-thread row has real data. Android builds don't scale perfectly, and the slowest steps run one at a time.

### One fix-and-test cycle

| Step | Time | Basis |
|---|---|---|
| Incremental build | Typically 1.5 minutes, 4 minutes at worst. Soong re-analysis alone took about 1.5 minutes when a `.bp` or `.mk` changed | Measured over 32 builds |
| `50-gate.py` | 12 seconds | Measured |
| Reboot to fastbootd and flash | 2–3 minutes, `super` included | Measured |
| First boot after a wipe | 2.5–4 minutes, until `sys.boot_completed` | Measured |
| Boot without a wipe | 1–2 minutes | Measured |
| **Total** | **About 8–10 minutes** | |

Failed Android boots take longer to show up. The watchdog can wait 15 minutes on a hang, and a wrong boot may need the whole time. A full-rebuild change, like a framework or BoringSSL edit, can take much longer than these figures, though we didn't hit one here.

**Plan work around these.** Batch fixes when you can, as each cycle costs about 10 minutes, and the gate costs 12 seconds. Start the sync and the first compile when you start work, or at night.

## Before anything: check the computer

```bash
tools/00-check-host.sh --tree "$LINEAGE_TREE"
```
Fix each FAIL using [`10-SETUP-NEW-COMPUTER.md`](10-SETUP-NEW-COMPUTER.md). If there's no tree yet, start `tools/05-sync-lineage.sh` in the background now: it takes hours, and it needs no device.

## Phase 0: Talk to the user (10 minutes)

Do this while the stock ROM still works. Ask:

1. **What do you use this device for?** Have them use it while you list every feature. The first project found keystone correction, HDMI input and the factory menu only after the ROM was working, which forced extra rounds of work.
2. **What physical controls exist?** Buttons, hidden holes, remote types.
3. **Is there a second identical unit?**
4. **Is the data on it disposable?** Once they say yes, stop asking before each wipe.
5. **Which apps must be preinstalled, and exact package names?** For paid apps, ask how they hold the license.
6. **Do you understand this reuses closed-source binaries, and does open source matter to you?** Explain it using `docs/12`. It affects the kernel choice.
7. **Is UART wired, or can it be?** Strongly recommended. Find out whether you can read their serial log: on the first project, the user ran `picocom` and I read its log file.

Record the answers in `devices/<codename>/NOTES.md`.

## Phase 1: Read-only study (30 minutes)

```bash
tools/10-preflight.sh report/
tools/20-backup.sh backup/
tools/21-check-backup.py backup/
tools/30-extract-stock.sh backup/super.img stock/
```

**Gate:** the backup passes, a second copy exists, you can name where the bootloader is, and you know whether slot `_b` is real.

Then do [`06-FEATURE-PARITY.md`](06-FEATURE-PARITY.md) step 1 against the running stock ROM: **you can't inspect a stock feature once it's gone.**

## Phase 2: Prove a way back (30 minutes to several days)

Work through [`03-RECOVERY-ROUTES.md`](03-RECOVERY-ROUTES.md) on the stock ROM.

**Gate:** at least two tested routes, including one that doesn't need Android to boot. Show the user the plan.

If you can't find a second route, tell the user what the risk is, and let them decide. On the first device, a capture of stock booting over UART would have saved days. Get that now.

## Phase 3: Decide whether to port at all (10 minutes)

Check for a shortcut before you build anything:
- Is there a maintained LineageOS or community ROM for this chip? Search first.
- If the device is Treble-capable with a sane vendor, a GSI may save most of this work, though features like keystone would still need work.
- Does the kernel's arch match the ROM you plan to build? `uname -m`, `ro.product.cpu.abilist`.

- **Are there open source or manufacturer-provided alternatives,** for the kernel or any other closed part? Search now, and use them where they fit: see [`12-KERNEL-AND-CLOSED-SOURCE.md`](12-KERNEL-AND-CLOSED-SOURCE.md). Apart from cheap swaps, replace them after the ROM works on stock parts, one at a time.

**Tell the user now what will stay closed source,** and what that means. Then let them choose. This guide's steps and times assume reuse of the stock kernel and vendor blobs.

**Match the Android version as closely as you can.** The first device was stock Android 14 on LineageOS 21 (Android 14), and even that hit library mismatches between QPR versions.

## Phase 4: First build, with everything from day one (hours)

Follow [`04-ROM-BUILD.md`](04-ROM-BUILD.md). **Include these from the very first build**, as each took at least one failed flash to discover:

| Item | Why |
|---|---|
| Recovery and fastbootd in `vendor_boot`, watchdog, auto-fastbootd (`templates/fallback/`) | Every later failure comes back on its own |
| Stock's cmdline and bootconfig, exactly | Bootloaders add their own keys, and a duplicate kills all of bootconfig |
| `init_boot` and `vendor_boot` headers and name matching stock | Bootloaders branch on these |
| Every mount point in the fstab | SwitchRoot fails otherwise |
| Boot control HAL | `update_verifier` reboots without it |
| Stock's `/vendor`, complete, plus TAs and keylayouts | Composer, audio, keymint and more depend on it |
| Security patch properties | keymint aborts without them |
| 32-bit kernel: patched BPF programs (`templates/patches/connectivity-bpf-32bit.patch`) | `netd` aborts without them |

**Don't add GApps to the first build.** Prove the base boots first: GApps add memory pressure and their own failures.

Don't copy stock's `ro.lmk.*` properties or `persist.bluetooth.bqr.*`. See the debug catalog.

## Phase 5: The gate and first flash (minutes each)

```bash
tools/50-gate.py --tree TREE --product NAME --stock-vendor stock/fs/vendor --stock-images backup [--arch32]
adb reboot fastboot
tools/60-flash.sh --out TREE/out/target/product/NAME --backup backup --slot a --wipe
fastboot reboot
tools/70-watch-boot.sh logs/
```

## Phase 6: Iterate (minutes per cycle)

The loop:
1. Read logs with `tools/75-triage.py`, then read the first real error yourself.
2. Fix the cause. Add a gate check if a check could have found it.
3. Build, gate, flash, watch.

Expect to pass through these stages, in this order:
```
u-boot -> kernel -> first-stage init -> SwitchRoot -> second-stage init -> bpfloader
       -> netd, keystore2 -> composer, boot animation -> zygote -> system_server -> sys.boot_completed
```
When you see `adbd` start, stop reading UART and use `adb`: logcat tells you far more.

**Boot animation running means display works.** It doesn't mean the system is close to finished.

## Phase 7: Bring up hardware (hours)

In this order, because each helps you debug the next:
1. **Input:** IR remote and Bluetooth remote. The user can't test anything without these.
2. **Wi-Fi, Bluetooth:** often the same chip, so one problem can break both.
3. **Memory:** swap, zram and lmkd, on anything under 2 GB. Do this before GApps.
4. **Audio, video, HDMI.**
5. **Device features** from Phase 0.

## Phase 8: GApps and apps (about 1 hour)

`tools/80-apps.py` and `tools/81-fdroid-fetch.py`. Watch memory after adding GApps. Use the Android TV package for TV devices, and the minimal one for low RAM. On 1 GB, leave out Google's setup app (`SetupWraith`): it gave us a black screen with its intro video audible.

## Phase 9: Root, if wanted (30 minutes)

Do this last, after a stable build. `tools/90-root-patch.sh`. It's the riskiest step after the first flash, so check your rescue route is still valid first.

## Phase 10: Finish (1 hour)

Before calling it done:
- Remove bring-up items: watchdog, auto-fastbootd, `ro.adb.secure=0`, `printk.devkmsg=on`.
- Decide about SELinux. Permissive with a placeholder policy isn't production-ready.
- Test a boot from a full wipe, with the final build.
- Walk through the Phase 0 list with the user. Only they can confirm that a feature works.

Tell the user plainly what's left: a test build with open `adb`, permissive SELinux and root is fine for a hobby device, and shouldn't be treated as secure.
