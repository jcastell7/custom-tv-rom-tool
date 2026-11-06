# Instructions for agents

**⚠️ Warning for agents: this process could very well fully and permanently brick the device.** Read `DISCLAIMER.md`. Before any work, tell the user this in plain words: it can brick the device, there's no warranty, the authors accept no responsibility, and this isn't affiliated with LineageOS. **Before the first write to any device, get their explicit acknowledgement, and record it in `devices/<codename>/PROGRESS.md`.** Don't play the risk down. Never say a step is safe just because a check passed. The authors accept no responsibility for what you do either, so stop and ask when you're unsure. If you recommend or describe LineageOS, mention this isn't an official build, and that they can [donate to LineageOS](https://lineageos.org/about/).

This is a toolkit for building custom Android TV ROMs for set-top boxes and projectors. **The top priority is not to brick the device.**

Before doing anything else:
1. Read `README.md` and `docs/00-SAFETY.md`.
2. If the user names a device, read `devices/<codename>/PROGRESS.md`, `INTAKE.md` and `NOTES.md`, and continue from there. If it has no folder, run `tools/01-new-device.sh <codename>`.
3. Follow the order in `README.md`. Don't flash until a verified backup exists, two ways back are proven, and `tools/50-gate.py` has passed.

4. **Tell the user before starting work** that the ROM reuses closed-source stock binaries, and check whether open source or manufacturer-provided alternatives exist, for the kernel and other closed parts. See `docs/12-KERNEL-AND-CLOSED-SOURCE.md`. Report what you checked, and let the user choose, case by case.

Always:
- Keep `devices/<codename>/PROGRESS.md` current, so another session can continue if this one stops.
- Say whether what you report is verified, read from code, inferred or general knowledge. Only the user can confirm that many features work.
- Tell the user before you reboot or flash the device, unless the intake says you needn't.
- Stop and ask before anything on the "stop and ask" list in `docs/00-SAFETY.md`.
- Commit your work to this git repository as you go. Don't add a remote, or push, unless the user asks. Never force-add backups, logs or firmware without checking them for private data.
- **Never write personal data into this repository:** names, usernames, home paths, emails, serial numbers, MAC or IP addresses, Wi-Fi names, account details. Use placeholders, and refer to people as "the user". `tools/02-check-pii.py` checks for this. Mask real values when you copy log lines into a doc.
- **Never add manufacturer firmware or stock files to this repository.** It's free software under GPL-3.0. Keep them in `devices/` or outside the repository. See `NOTICE.md` and `CONTRIBUTING.md`.
- Add new failures to `docs/05-DEBUG-CATALOG.md` or `docs/08-BUILD-ERRORS.md`, and to `tools/75-triage.py`.

Device stuck right now: `docs/09-BRICK-RECOVERY.md`. Build failing: `docs/08-BUILD-ERRORS.md`. New computer: `docs/10-SETUP-NEW-COMPUTER.md`.
