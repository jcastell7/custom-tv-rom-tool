# How to use this toolkit

This guide is for you, the person running it. The quick version is in [`QUICKSTART.md`](../QUICKSTART.md).

## How it works

An agent does most of the work: reading the device, building, fixing, flashing. You provide what it can't get itself: decisions, physical actions, and what you see on the screen. The toolkit provides its memory, since a new agent starts knowing nothing:

| A new agent needs | It gets it from |
|---|---|
| Rules and working order | `CLAUDE.md` or `AGENTS.md` (many agents load these automatically), `README.md`, `docs/00-SAFETY.md` |
| What the device is and what you want | `devices/<codename>/INTAKE.md`, from you |
| What's been done, and what's next | `devices/<codename>/PROGRESS.md`, `NOTES.md` |
| How to do each job | `tools/`, `templates/`, `docs/` |
| A worked example | `reference/hermes/` |

## Before you start

Set up the computer: `tools/00-check-host.sh --tree PATH`. It reports exactly what's missing, and [`10-SETUP-NEW-COMPUTER.md`](10-SETUP-NEW-COMPUTER.md) explains each fix.

**Start the LineageOS download early.** It takes hours and needs no device:
```bash
tools/05-sync-lineage.sh /path/to/lineage-21.0
```
Then the first compile takes about 5.5 hours on 12 threads, and can run overnight. See [`01-FAST-PATH.md`](01-FAST-PATH.md#how-long-it-takes).

**Prepare the device:**
1. Keep it on the stock ROM. Don't change anything yet.
2. Enable Developer options (tap Build number 7 times) and USB debugging.
3. Connect it, accept the prompt on screen, and check with `adb devices`.

## What to tell the agent

### The intake form

```bash
tools/01-new-device.sh mybox
```

Use the device's codename (`adb shell getprop ro.product.device`). Fill in `devices/mybox/INTAKE.md`. Four answers save the most time:

| Question | Why it matters |
|---|---|
| **Stock features you rely on** | On the first project, keystone, HDMI input and the factory menu came up only after the ROM worked. Each one took more builds |
| **Can the data be wiped?** | Otherwise the agent has to ask every time |
| **Is this unit a spare, or do you need it working?** | It decides how much risk is acceptable |
| **Exact app names and license sources** | "Browser1" and "symphonium" cost time to identify. The package name settles it at once. Find it in the Play Store URL, after `id=` |

### The first prompt

```
Use this toolkit to build a custom Android TV ROM for my device, codename mybox.
Read CLAUDE.md, README.md and docs/00-SAFETY.md, then devices/mybox/INTAKE.md.

Start with read-only steps only: check the computer, run preflight, and take a verified full backup.
Then show me what you found, your recovery plan, and any questions.
Don't flash anything until I've approved the plan.
Keep devices/mybox/PROGRESS.md up to date.
```

If you want it to work with less supervision, once the plan is approved, say so plainly, for example:
```
The plan is approved. Flash and iterate without asking each time, and wipe userdata whenever it helps.
You may reboot the device freely. Keep going until sys.boot_completed, then tell me what to test.
If it would need any of the "stop and ask" items in docs/00-SAFETY.md, stop and ask.
```

**Be explicit about permission for risky steps.** Agents shouldn't assume it. On the first project, wiping, flashing and root each needed a clear yes from the user.

### Files and logs

Put them in `devices/mybox/logs/`, or give the agent the path, rather than pasting long text. A full file keeps the lines that matter.

| What | How |
|---|---|
| UART, continuously (best) | `picocom -b 115200 --logfile ~/uart.log /dev/ttyUSB0`. Tell the agent the path. It can read the log while you run it |
| A short log | Paste it into the chat. Include the lines from before the failure, not only the end |
| What's on screen | Say what you see. Screenshots from the device can differ from what the projector shows |
| Firmware or APKs | Put them in their own folder and give the path. If a site blocks the agent's download, you may have to download it yourself |
| Earlier attempts and links | The last section of the intake form |

**Check logs before sharing them outside this computer.** They can hold serial numbers, MAC addresses and email addresses.

## What only you can do

| Job | Notes |
|---|---|
| Approve the recovery plan, and any risky step | The agent should show what can go wrong |
| `sudo` commands | Type `! command` in Claude Code to run a command in the session yourself. This also works for logins |
| Buttons, cables, USB sticks, soldering | The agent will tell you what to press and when |
| Open the serial port | Often only your user can |
| Confirm what's on screen | The agent can't see the projected image |
| Test features | Is the picture right? Does sound play? Did the remote respond? |
| Passwords and sign-ins | Never give them to the agent |
| Approve running downloaded programs on the device | A safety system may block this until you decide. On the first project, that was the Magisk patcher |

## How to give useful feedback

| Instead of | Say |
|---|---|
| "It doesn't work" | "On the corner screen, the arrow keys do nothing. The picture doesn't move." |
| "It's broken" | "Logo for 30 seconds, then black. The fan's on. It's been 5 minutes." |
| "Same error" | The exact text, or the new log's path |

**Report what you see, even if it seems wrong.** The agent can be mistaken. On the first project, the user corrected wrong theories several times, including removing a setup wizard that was needed. Challenge claims that don't fit what you see.

**Ask "what did you actually verify?"** at any time. A good answer separates what was tested from what's inferred.

## Long sessions and limits

Agents run out of context or usage limits. The toolkit copes with this if progress is written down.

- **Ask for it:** "Save your progress to devices/mybox/PROGRESS.md now."
- **After an interruption, in a new session:**
  ```
  Continue the ROM for device mybox. Read CLAUDE.md, then devices/mybox/PROGRESS.md and NOTES.md, and carry on from there.
  ```
- **What survives:** files. Anything only in the chat is lost to a new session. That includes your decisions, so ask the agent to write important ones into the intake or notes.

A session ending doesn't harm the device. Long builds in the background may stop, and the agent can start them again.

## Common requests

| Goal | Tell the agent |
|---|---|
| Is this device worth trying? | "Run preflight and tell me the risks and the likely effort. Change nothing." |
| Back up only | "Take a verified backup to /path. Don't change anything else." |
| Read-only study of a stock feature | "Find what implements keystone in stock. See docs/06." |
| Add an app | "Add package x from F-Droid using tools/80-apps.py. Rebuild, and run the gate." |
| Back to stock | "Plan a restore to stock, from devices/mybox's backup. Show me the plan before you write anything." |
| Second unit of the same model | "Reuse devices/mybox. Back up this unit first, and keep its per-device data." |
| Improve the toolkit | "Add what we learned to docs/05, docs/08 and tools/75-triage.py." |

## Choosing how much to supervise

| Stage | Suggested supervision |
|---|---|
| Read-only study and backup | Low. These only read |
| **First flash** | **High. Check the recovery plan yourself** |
| Build and iterate, with a working way back | Low. Allow flashing and wiping |
| Patching bootloader-adjacent images, like root | High |
| Anything on the never-flash list | Your decision each time, and normally no |

## Using a different agent or model

`AGENTS.md` and `CLAUDE.md` have the same content, for tools that look for either. If yours loads neither, tell it to read `README.md` first. **Less capable agents need the structure more:** tell them to follow the order, use the tools instead of improvising, and stop at each gate. Keep tasks small: "do phase 1, then stop and report."

## Keeping the toolkit current

Each device teaches something. At the end of a project, ask the agent to add failures to the catalogs, turn repeated work into tools, test new gate checks against the real broken file, and update the tested column in `README.md`. Device-specific details stay in `devices/<codename>/`.

## Git and personal data

This toolkit is a git repository with no remote, so nothing leaves this computer unless you add one. **It must not contain personal data**, including commit author names.

**In each new clone, run this once:**
```bash
git config core.hooksPath .githooks
git config user.name custom-tv-rom-tool
git config user.email noreply@example.invalid
```
The hook runs `tools/02-check-pii.py` before each commit, and blocks it if it finds a problem.

`devices/*/` isn't committed: the intake form, notes and logs describe a real unit, and your answers can identify you. Back that folder up privately. `.gitignore` also keeps out images, APKs, device backups, logs and keys.

**The scanner can't catch everything.** It finds patterns, like addresses and home paths, plus this computer's username and git identity, but not, say, a name written in a note. Read what you add, and check `git log -p` before you publish. Anything committed stays in the history.

**Before you make it public:** `reference/hermes/` still holds a real device's stock SELinux policy, device tree and notes. They don't identify a person, but consider whether you can share them.

## Backing it up

Keep these safe, ideally in more than one place:
- This repository.
- `devices/*/`, which holds decisions and notes, and isn't in git.
- Device backups, stored separately, since git ignores them. **They're private.**
