# Contributing

Contributions are welcome, under the [GNU GPL version 3](LICENSE). By contributing, you agree your work is licensed that way.

## Setup
```bash
git config core.hooksPath .githooks
git config user.name custom-tv-rom-tool
git config user.email noreply@example.invalid
```

## Rules
- **No personal data**, in files or commit metadata. `tools/02-check-pii.py` checks this, but read what you commit too.
- **No manufacturer firmware or stock files.** No kernels, modules, HALs, libraries, stock apps, stock SELinux policy or stock configuration. Tools should get these from the user's own device.
- **Third-party code** keeps its license: add it to `NOTICE.md`, and put the license text in `LICENSES/`.
- **Keep the safety rules.** Don't weaken a check in `tools/60-flash.sh` or `tools/50-gate.py` without explaining why.
- **Say what you tested,** and update the table in `README.md`. A new gate check should be tested against the real broken file.
- **New failures** go in `docs/05-DEBUG-CATALOG.md` or `docs/08-BUILD-ERRORS.md`, and in `tools/75-triage.py`.
- **Keep device-specific details marked as such.** Addresses and module names from one device shouldn't read as general facts.
