#!/usr/bin/env bash
# Creates a workspace for a new device. Touches no device. Won't overwrite an existing workspace.
# Usage: 01-new-device.sh CODENAME     Result: devices/CODENAME/ with an intake form, notes and a progress file.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(dirname "$HERE")
[ $# = 1 ] || { echo "usage: $0 CODENAME   (lowercase, like ro.product.device: e.g. mybox)"; exit 2; }
NAME=$1
case "$NAME" in *[!a-z0-9_-]*|"") echo "Use lowercase letters, digits, - and _ only."; exit 2 ;; esac
D=$ROOT/devices/$NAME
[ ! -e "$D" ] || { echo "$D already exists. Nothing changed. A new session should read its PROGRESS.md."; exit 1; }
mkdir -p "$D/logs" "$D/patches"
sed "s/<CODENAME>/$NAME/" "$ROOT/templates/device-intake.md" > "$D/INTAKE.md"
cat > "$D/PROGRESS.md" <<EOF
# Progress: $NAME

**Keep this current. It's how the next session continues.** Update it after each milestone, and before any long wait.

Current status: not started
Next action: fill in INTAKE.md, then run tools/00-check-host.sh

## Checklist (see docs/01-FAST-PATH.md)
- [ ] Computer checked (00-check-host.sh: 0 FAIL)
- [ ] Intake completed with the user
- [ ] Preflight run (10-preflight.sh)
- [ ] Backup verified (20-backup.sh, 21-check-backup.py)
- [ ] Second backup copy made. Location:
- [ ] Bootloader located in the backup. Where:
- [ ] Stock UART boot log captured, or ruled out
- [ ] Way back 1 proven:
- [ ] Way back 2 proven:
- [ ] Recovery plan shown to the user
- [ ] Stock features inventoried (docs/06)
- [ ] User told what stays closed source (docs/12)
- [ ] Alternatives checked for the kernel and each closed part: open source / manufacturer / stock. Decisions recorded in NOTES.md
- [ ] Device tree created
- [ ] First build done
- [ ] Gate passes (50-gate.py)
- [ ] First flash done
- [ ] sys.boot_completed reached
- [ ] Remote, Wi-Fi, Bluetooth, memory, audio and video working
- [ ] Each feature from the intake confirmed by the user
- [ ] Apps and root, if wanted
- [ ] Bring-up items removed, or the user decided to keep them

## Waiting on the user

## Open problems
EOF
cat > "$D/NOTES.md" <<EOF
# Notes: $NAME

Record every change and why, including what failed. Say whether each claim is verified, read from code, inferred or general knowledge.

## Device facts

## Way-back plan
| Boot stops at | Action | Tested? |
|---|---|---|

## Closed parts: what was chosen
| Component | Choice (open / manufacturer / stock) | Why | What was checked | Works? |
|---|---|---|---|---|

## Log of attempts
| When | Changed | Result | Next |
|---|---|---|---|
EOF
echo "Created $D"
echo "Next: fill in $D/INTAKE.md, then see QUICKSTART.md"
