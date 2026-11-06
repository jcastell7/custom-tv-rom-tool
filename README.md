# Custom Android TV ROM toolkit

> **⚠️ WARNING: this process could very well fully and permanently brick your device.** Only use it on a device you own and can afford to lose. It's provided as is, with no warranty, and **we accept no responsibility** for how it's used or what happens. Not affiliated with LineageOS in any way: we just use and recommend their work, so [please donate to them](https://lineageos.org/about/) when you can. Read [`DISCLAIMER.md`](DISCLAIMER.md).

For building a custom Android TV ROM (LineageOS) for a set-top box or projector, reusing closed-source stock files where no open or manufacturer alternative fits. Written for an agent or person with **no knowledge of the project this came from**. It was built from one real device, an Allwinner H723 projector. On any other device, expect differences.

**Your first priority is not to brick the device.** Read [`docs/00-SAFETY.md`](docs/00-SAFETY.md) before you run anything. The device this came from got stuck, and rescuing it took days.

**New here? Start with [`QUICKSTART.md`](QUICKSTART.md).** If you're the person running this: [`docs/11-HOW-TO-USE.md`](docs/11-HOW-TO-USE.md). If you're an agent: continue reading, then `docs/00-SAFETY.md`.

## Know this before you start

- **It can fully brick the device.** See the warning above. Only use a device you can afford to lose.
- **The result isn't fully open source.** By default, this reuses the device's closed-source stock binaries: bootloader, TEE, kernel, drivers, GPU and media libraries, and any stock apps you keep. LineageOS runs on top of them. They can't be inspected or fixed, they get no security updates from LineageOS, and their licences may not let you share a finished image.
- **Stock isn't the only option.** For the kernel and each other closed part, check for an open source replacement, or something the manufacturer provides, such as source, an SDK or drivers. Use one when it fits, case by case. Stock is the fallback. The first device mixed all three, and kept its stock kernel as no suitable one was found.

Details and how to choose: [`docs/12-KERNEL-AND-CLOSED-SOURCE.md`](docs/12-KERNEL-AND-CLOSED-SOURCE.md). **Agents: tell the user this before starting work.**

## How long it takes

**Expect about 2–4 days for a complete ROM,** with about 15–25 hours hands-on, as an estimate from one project. On a 12-thread PC with an NVMe SSD, the first compile alone takes about 5.5 hours, and the source download takes one to several hours. After that, each fix-and-test cycle takes about 10 minutes. Details and scaling: [`docs/01-FAST-PATH.md`](docs/01-FAST-PATH.md#how-long-it-takes).

## Do these in order

| Step | What | Read | Run |
|---|---|---|---|
| 0 | **Check this computer and where LineageOS lives** | [`docs/10`](docs/10-SETUP-NEW-COMPUTER.md) | `tools/00-check-host.sh --tree PATH` |
| 1 | Ask the user what the device does and which features matter | [`docs/01-FAST-PATH.md`](docs/01-FAST-PATH.md) Phase 0, [`docs/06`](docs/06-FEATURE-PARITY.md) | |
| 2 | Study the device, read-only | | `tools/10-preflight.sh` |
| 3 | **Full backup, verified, with a second copy** | [`docs/02`](docs/02-BACKUP.md) | `tools/20-backup.sh`, `tools/21-check-backup.py` |
| 4 | **Prove two ways back** | [`docs/03`](docs/03-RECOVERY-ROUTES.md) | |
| 5 | Unpack stock and find its features | [`docs/06`](docs/06-FEATURE-PARITY.md) | `tools/30-extract-stock.sh`, `tools/31-find-feature.py` |
| 6 | Create the device tree and build | [`docs/04`](docs/04-ROM-BUILD.md) | `tools/40-build.sh` |
| 7 | **Run the gate** | | `tools/50-gate.py` |
| 8 | Flash, watch, read the logs | [`docs/05`](docs/05-DEBUG-CATALOG.md) | `tools/60-flash.sh`, `tools/70-watch-boot.sh`, `tools/75-triage.py` |
| 9 | Repeat 6–8 until it boots, then bring up hardware | | |
| 10 | Add apps, then root if wanted | | `tools/80-apps.py`, `tools/81-fdroid-fetch.py`, `tools/90-root-patch.sh` |

**If the device is already stuck, stop and go straight to [`docs/09-BRICK-RECOVERY.md`](docs/09-BRICK-RECOVERY.md).** Build failed: [`docs/08`](docs/08-BUILD-ERRORS.md).

**Stop conditions:** don't flash until steps 3 and 4 are done. Don't flash a build that hasn't passed step 7.

## Example session

```bash
export PATH="$PWD/tools:$PATH"

# Read-only
10-preflight.sh report/
20-backup.sh backup/
21-check-backup.py backup/
cp -r backup/ /some/other/disk/
30-extract-stock.sh backup/super.img stock/
31-find-feature.py stock/fs 'keystone|hdmi.?in|tvinput|factory'

# Build (TREE is your LineageOS tree)
40-build.sh $TREE lineage_mybox-ap2a-userdebug

# Check, then flash
50-gate.py --tree $TREE --product mybox --stock-vendor stock/fs/vendor --stock-images backup --arch32   # --arch32 only for a 32-bit kernel
adb reboot fastboot
60-flash.sh --out $TREE/out/target/product/mybox --backup backup --slot a --wipe
fastboot reboot
70-watch-boot.sh logs/

# Something failed?
75-triage.py logs/logcat-partial.txt
```

## What's here

| Path | Contents |
|---|---|
| `LICENSE`, `NOTICE.md` | GPL-3.0, and the third-party exceptions |
| `DISCLAIMER.md` | **The risk of bricking, no warranty, no affiliation with LineageOS, and how to donate to them** |
| `QUICKSTART.md` | The short version, with prompts to paste |
| `CLAUDE.md`, `AGENTS.md` | Rules that agents load automatically |
| `devices/<codename>/` | One device's intake form, progress and notes. Create with `tools/01-new-device.sh` |
| `docs/11-HOW-TO-USE.md` | Guide for the person: what to supply, what only you can do, resuming, supervision |
| `docs/00-SAFETY.md` | Rules, and when to stop and ask |
| `docs/01-FAST-PATH.md` | The whole process in the best order, with what to include from day one |
| `docs/02-BACKUP.md` | What a complete backup is, and what to do without root |
| `docs/03-RECOVERY-ROUTES.md` | Ways back, how to prove them, SoC USB modes, bootloader updaters |
| `docs/04-ROM-BUILD.md` | Boot settings, vendor partition traps, properties, build errors |
| `docs/05-DEBUG-CATALOG.md` | Symptom, log line, cause and fix, for every failure we hit |
| `docs/06-FEATURE-PARITY.md` | Finding and keeping stock features |
| `docs/07-CASE-STUDY.md` | What happened on the first device, and its status |
| `docs/08-BUILD-ERRORS.md` | Every compile and packaging error, by stage, with fixes |
| `docs/09-BRICK-RECOVERY.md` | **The device is stuck now:** diagnosing it, every route, and what to do afterwards |
| `docs/10-SETUP-NEW-COMPUTER.md` | Hardware needed, preparing the drive, installing every tool on any Linux, moving to another computer, host problems |
| `docs/12-KERNEL-AND-CLOSED-SOURCE.md` | What stays closed and what that means; open source, manufacturer and stock options for each part, and choosing a kernel |
| `tools/` | The scripts below |
| `templates/fallback/` | Boot watchdog, auto-fastbootd: failed boots return to fastboot on their own |
| `templates/memory/` | zram and swap script, low-RAM properties |
| `templates/shim/` | Providing missing symbols, renaming colliding libraries, with `patchelf` |
| `templates/patches/` | Tree patches for BPF, Bluetooth, Wi-Fi, right-click |
| `templates/remove-apps/` | Removing inherited apps properly |
| `templates/companion-app-example/` | Small system app: launcher icon and boot tasks for a stock tool |
| `reference/hermes/` | The first device's device tree, without its stock files, so it's for reading only, docs, rescue stick, env tools and read-only donor extractor |

## Tools

| Tool | Touches the device? | Purpose | Tested on hermes? |
|---|---|---|---|
| `01-new-device.sh` | No | Create a device workspace | Yes |
| `00-check-host.sh` | No | Hardware, tools and whether LineageOS is on a suitable drive with enough space | Yes: on the real tree, and it rejected tmpfs, too little space, a non-tree directory and no location |
| `05-sync-lineage.sh` | No | Downloads LineageOS, after checking the location | Syntax only. The refusal path uses the tested check |
| `10-preflight.sh` | Writes nothing | Report and go/no-go | Yes, once on real hardware with a custom ROM, which found and fixed 2 bugs. Not yet on a stock ROM. It can show a root prompt on the device |
| `20-backup.sh` | Read-only | Full backup, hash-verified on both sides | Against a simulated device (`tools/test/fake-adb.example.txt`): copies identical, resume, corrupted transfer, tampered file, no partitions. Based on a script used on the real device. **Not yet run in this form on real hardware, so check the first partitions by hand** |
| `21-check-backup.py` | No | Completeness, and finding the bootloader | Yes, on the real backup |
| `30-extract-stock.sh` | No | Unpack `super` to files | Yes, on the real `super` |
| `31-find-feature.py` | No | Search stock for a feature | Yes |
| `40-build.sh` | No | Build through `lunch` | Syntax only. Same steps as the script that built hermes |
| `50-gate.py` | No | **Pre-flash checks** | Yes: passes the working build and catches five real bugs |
| `60-flash.sh` | **Writes** | Guarded flashing | All refusals tested. Actual writes not tested through this script |
| `70-watch-boot.sh` | Read-only | Follow a boot and save logs | Syntax only |
| `75-triage.py` | No | Log line to known cause | Yes, on real logs |
| `80-apps.py` | No | Preinstall APKs correctly | Yes, generation only; same logic as what built hermes |
| `81-fdroid-fetch.py` | No | Download and hash-check from F-Droid | Syntax only. Same logic as what fetched the hermes apps |
| `90-root-patch.sh` | Writes to `/data/local/tmp` only | Magisk patch | Same steps as the script that worked on hermes |

"Syntax only" means it hasn't been run in this exact form. Read those scripts, and expect to fix small things.

`tools/bin/` holds `lpunpack.py` and `unpack_bootimg.py`.

## Requirements

**Run `tools/00-check-host.sh` first:** it checks all of this. How to meet each item is in [`docs/10-SETUP-NEW-COMPUTER.md`](docs/10-SETUP-NEW-COMPUTER.md).

- **Computer:** x86_64 Linux, any distribution. To build: 8+ threads, 16 GB RAM plus swap at minimum (32 GB recommended), SSD.
- **LineageOS drive:** a local ext4 or xfs drive, not NTFS, exFAT or tmpfs, mounted `exec`, with **350 GB free**. A tree with one built device measured 232 GB.
- **Device:** unlocked bootloader, and root `adb` or another way to read all partitions.
- **Hardware:** a data USB cable, a USB 2 stick, and a 3.3 V USB-UART adapter.

Tell the tools where the tree is by setting `LINEAGE_TREE`.

## This is a git repository

It has no remote. **It must contain no personal data:** see "No personal data" below. Commit changes as you work: device notes, new checks and fixes. `.gitignore` keeps out images, APKs, device backups, logs and keys. Read the Git section of [`docs/11-HOW-TO-USE.md`](docs/11-HOW-TO-USE.md) before you push it anywhere.

## No personal data

Nothing in this toolkit, including commit metadata, may identify a person or a specific unit. That covers names, usernames, home paths, email addresses, serial numbers, MAC addresses, IP addresses, Wi-Fi names and account details. Use placeholders like `<serial>` and `/path/to/...`.

`tools/02-check-pii.py` checks for this, and runs before each commit. Turn the hook on in each new clone, once:
```bash
git config core.hooksPath .githooks
git config user.name custom-tv-rom-tool
git config user.email noreply@example.invalid
```
Real logs, device backups and the intake form's answers contain this kind of data. `devices/*/` is ignored by git for that reason, so keep them out of the repository, and mask anything you copy into a doc.

## Rules for agents

1. **Follow the order.** If you want to skip a step, tell the user why and let them decide.
2. **Read a script before you run it.** Fix it if it doesn't fit this device, and keep your improvements here.
3. **Say what you verified.** "It built" and "the service accepted the call" don't mean "it works". See `docs/00-SAFETY.md`.
4. **Add what you learn.** New failure: add it to `docs/05` and `tools/75-triage.py`. If a static check could have caught it, add one to `tools/50-gate.py`. Test new checks against the real broken file.
5. **Check logs before theories.** Check your own recent fixes before anything else.
6. **Keep notes for your device** in `devices/<codename>/`, and record each change and the reason for it, including what failed.
7. **Don't assume hermes details apply.** Addresses, module names, chip names and partition names in these documents are examples.
8. **Commit often, and save progress** in `devices/<codename>/PROGRESS.md`. Long work can be interrupted, and only files survive.

## Credit

This toolkit exists because of [LineageOS](https://lineageos.org) and its community. It isn't affiliated with them, and builds made with it are unofficial, so don't ask them for support. **Please [donate to LineageOS](https://lineageos.org/about/) when you can.**

## License

**Free and open source, under the [GNU GPL version 3](LICENSE).** A few third-party files keep their own licenses: see [`NOTICE.md`](NOTICE.md). No manufacturer firmware is included. **The ROM you build normally still contains closed-source binaries,** which this license doesn't cover. Contributions: [`CONTRIBUTING.md`](CONTRIBUTING.md).
