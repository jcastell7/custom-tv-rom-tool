#!/usr/bin/env python3
"""
DO NOT USE. Kept as a record of an approach that turned out to be unfounded:
"key press :" probably reports a character read from UART, not an ADC button,
and this unit has no known ADC buttons. See docs/13.

find-fastboot-key.py — read a boot0/u-boot UART capture and report the ADC
"key press :" value boot0 printed, and whether it lands in the fastboot or
recovery window the env defines.

boot0 prints a line like:   [102]key press : <value>
when a button is held at power-on. The stock env windows are:
    fastboot : fastboot_key_value_min .. _max   (stock 0x2 .. 0x8)
    recovery : recovery_key_value_min .. _max   (stock 0x10 .. 0x13)

Workflow to find which physical button triggers fastboot (no FEL, no flash):
  1. Wire UART (docs/11), start your capture (picocom/screen logging to file).
  2. Power on while HOLDING one button. Note the button.
  3. Run:  find-fastboot-key.py <capture.log>
  4. Repeat per button until the printed value is inside the fastboot window;
     that button, held at power-on, is your fastboot trigger.

Usage:
    find-fastboot-key.py <capture.log>         # or '-' for stdin
    find-fastboot-key.py --window MIN MAX <log> # override windows (hex)
"""
import argparse
import re
import sys

# default windows (stock env_a.img)
FB_MIN, FB_MAX = 0x2, 0x8
RC_MIN, RC_MAX = 0x10, 0x13

KEY_RE = re.compile(r"key press\s*:\s*([0-9a-fA-FxX]*)")


def parse_val(tok):
    tok = tok.strip()
    try:
        return int(tok, 0) if tok.lower().startswith("0x") else int(tok, 16)
    except ValueError:
        try:
            return int(tok)
        except ValueError:
            return None


def main():
    print("WARNING: unreliable, see docs/13. 'key press :' is probably UART "
          "input, not a button value.\n", file=sys.stderr)
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--fb-window", nargs=2, type=lambda x: int(x, 0))
    ap.add_argument("--rc-window", nargs=2, type=lambda x: int(x, 0))
    args = ap.parse_args()

    fb = tuple(args.fb_window) if args.fb_window else (FB_MIN, FB_MAX)
    rc = tuple(args.rc_window) if args.rc_window else (RC_MIN, RC_MAX)

    text = sys.stdin.read() if args.log == "-" else open(
        args.log, "r", errors="replace").read()

    hits = []
    for line in text.splitlines():
        m = KEY_RE.search(line)
        if m:
            tok = m.group(1).strip()
            hits.append((line.strip(), parse_val(tok) if tok else None))

    if not hits:
        print("No 'key press :' line found at all — is this a boot0/u-boot "
              "capture? boot0 prints it every boot.")
        sys.exit(2)
    if all(v is None for _, v in hits):
        print("'key press :' line present but EMPTY (no button held during "
              "this capture). Re-capture while HOLDING a button from before "
              "power-on through boot0 (~0.1 s in), then re-run.")
        sys.exit(2)

    print(f"fastboot window: 0x{fb[0]:x}..0x{fb[1]:x}   "
          f"recovery window: 0x{rc[0]:x}..0x{rc[1]:x}\n")
    triggered = False
    for raw, val in hits:
        if val is None:
            print(f"  {raw!r}  -> no numeric value (no button held)")
            continue
        where = "FASTBOOT" if fb[0] <= val <= fb[1] else (
            "RECOVERY" if rc[0] <= val <= rc[1] else "none")
        print(f"  {raw!r}  -> value=0x{val:x} ({val})  window={where}")
        if where == "FASTBOOT":
            triggered = True
    print("\n" + ("MATCH: this button lands in the FASTBOOT window — hold it "
                  "at power-on to enter fastboot without FEL."
                  if triggered else
                  "No value hit the fastboot window. Try another button, or "
                  "widen the window via env-widen-key.img (needs one fastboot "
                  "session first)."))


if __name__ == "__main__":
    main()
