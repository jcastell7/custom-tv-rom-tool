#!/usr/bin/env python3
"""Checks this repository for personal data. It also runs as a pre-commit hook. Exit status 1 means something was found.

Usage: 02-check-pii.py [--staged]     Default: all files on disk, except ignored ones. --staged: what's about to be committed, and the author.

Finds email addresses, MAC addresses, private IP addresses, home and removable-media paths, serial-number assignments, tokens and
private keys, in text and binary files. It also looks for THIS computer's username, hostname and git identity, read at run time and
never stored. It prints the file and kind of match, never the value, so its output can be shared.

To allow a false positive, add "path:kind" to .pii-allow, with a comment saying why. Never allow a real value: replace it with a placeholder.
A pattern scan can't find everything, such as a person's name in a note: read what you commit.
"""
import getpass, os, re, socket, subprocess, sys

ALLOWED_EMAIL = re.compile(rb"@(?:example\.(?:com|org|net|invalid)|[a-z.]*\.invalid)$", re.I)
PATTERNS = {
    "email": re.compile(rb"[A-Za-z0-9._%+-]+@[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}"),   # A letter after @ skips HIDL names like x@1.0.so
    "mac-address": re.compile(rb"\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b"),
    "private-ip": re.compile(rb"\b(?:192\.168|10\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b"),
    "home-path": re.compile(rb"/(?:home|Users|media|run/media)/[a-z][a-z0-9_-]{1,}(?=[/\s\"'`:)]|$)"),
    "serial-value": re.compile(rb"(?i)(?:\bsnum=|ro\.serialno[\]:= ]+\[?|serialno=|androidboot\.serialno=)[0-9a-z]{6,}"),
    "fs-id": re.compile(rb"/(?:media|mnt)/[^/\s]+/[0-9A-F]{4}-[0-9A-F]{4}\b"),
    "token": re.compile(rb"gh[pousr]_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{30,}|\bsk-[A-Za-z0-9]{20,}|xox[bpa]-[0-9A-Za-z-]{20,}"),
    "private-key": re.compile(rb"BEGIN [A-Z ]*PRIVATE KEY"),
    "scratch-path": re.compile(rb"/tmp/claude-\d+|claude\.ai/code/session_"),
}
# Paths that are examples, not people.
PLACEHOLDER = re.compile(rb"/(?:home|Users|media)/(?:user|username|me|you|example|name|your)\b")
SKIP_SELF = {"tools/02-check-pii.py", ".git"}

def identity():
    out = {getpass.getuser(), socket.gethostname()}
    for key in ("user.name", "user.email"):
        for scope in ("--global", "--system"):
            v = subprocess.run(["git", "config", scope, key], capture_output=True, text=True).stdout.strip()
            out |= set(re.split(r"[\s@.]+", v))
    generic = {"root", "user", "admin", "ubuntu", "android", "linux", "localhost", "gmail", "com", "org", "net", "noreply", "example", "custom", "tool", "invalid"}
    out = {x for x in out if len(x) >= 4 and x.lower() not in generic}
    return re.compile(rb"(?<![A-Za-z0-9])(?:" + b"|".join(re.escape(x.encode()) for x in sorted(out)) + rb")(?![A-Za-z0-9])", re.I) if out else None

def load_allow():
    allowed = set()
    if os.path.exists(".pii-allow"):
        for line in open(".pii-allow"):
            line = line.split("#")[0].strip()
            if line:
                allowed.add(line)
    return allowed

def scan(name, data, ident, allowed, found):
    if name in SKIP_SELF:
        return
    checks = dict(PATTERNS)
    if ident:
        checks["this-computers-identity"] = ident
    for kind, pat in checks.items():
        if f"{name}:{kind}" in allowed:
            continue
        for m in pat.finditer(data):
            v = m.group(0)
            if kind == "email" and ALLOWED_EMAIL.search(v):
                continue
            if kind == "home-path" and PLACEHOLDER.match(v):
                continue
            line = data.count(b"\n", 0, m.start()) + 1
            found.append(f"{name}:{line}: {kind}")
            break

def main():
    os.chdir(subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or ".")
    ident, allowed, found = identity(), load_allow(), []
    if "--staged" in sys.argv:
        names = subprocess.run(["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"], capture_output=True).stdout.decode().split("\0")
        for n in filter(None, names):
            data = subprocess.run(["git", "show", ":" + n], capture_output=True).stdout
            scan(n, data, ident, allowed, found)
        who = subprocess.run(["git", "var", "GIT_AUTHOR_IDENT"], capture_output=True).stdout + b" " + subprocess.run(["git", "var", "GIT_COMMITTER_IDENT"], capture_output=True).stdout
        if ident and ident.search(who):
            found.append("commit author or committer: this-computers-identity. Run: git config user.name custom-tv-rom-tool; git config user.email noreply@example.invalid")
        msg = os.path.join(subprocess.run(["git", "rev-parse", "--git-dir"], capture_output=True, text=True).stdout.strip(), "COMMIT_EDITMSG")
    else:
        names = subprocess.run(["git", "ls-files", "-co", "--exclude-standard", "-z"], capture_output=True).stdout.decode().split("\0")
        for n in filter(None, names):
            try:
                with open(n, "rb") as f:
                    scan(n, f.read(), ident, allowed, found)
            except OSError:
                pass
    for f in found:
        print("PII?", f)
    print(f"{len(found)} possible personal-data findings." if found else "No personal data found. A pattern scan can't catch everything: read what you commit.")
    return 1 if found else 0

sys.exit(main())
