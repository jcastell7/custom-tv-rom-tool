# UART serial console — debug the boot hang & force fastboot/recovery (Allwinner H723 "hermes")

The device boots slot `_a` (LineageOS) and hangs at the manufacturer logo with **no adb and no
fastboot**. u-boot runs, so the escape is to watch the serial console and, if we can break into u-boot,
drop straight into **fastboot** — no SoC-specific FEL tooling and no firmware `.img` needed.

> **Current state of this unit.** Both directions work electrically: streaming `x` during power-on produced
> `[102]key press : x` (`firmware/device-state/uart-rx-test-x-stream.log`). **u-boot still shows no prompt or echo**,
> and its visible output stops at `Hit any key to stop autoboot:  0` unless `d` is streamed. **To reach fastboot, use
> the rescue USB stick** ([`13`](13-fastboot-trigger-no-fel.md)), not the console. The u-boot commands in §6 and §7
> assume a prompt, which hasn't been reached on this unit.

Companion to [`10-flashing-the-build.md`](10-flashing-the-build.md) (re-flash once in fastboot) and
[`07-stock-backup-and-restore.md`](07-stock-backup-and-restore.md) (roll back to stock).

Device-specific facts pulled from the dumped u-boot env (`firmware/partitions/env_a.img`):

| Setting | Value | Why it matters |
|---|---|---|
| Debug UART | **UART0** @ `0x02600000` (`serial0`), pins **PH0 (TX) / PH1 (RX)** per the DTS | wire the adapter to UART0, nothing else |
| Console / baud | **`ttyAS0,115200`** 8N1 | host opens the port at **115200** (the `AS` is Allwinner's device-side name) |
| `earlyprintk` | `sunxi-uart,0x02600000` | a running kernel should print early on UART; none has been captured |
| `loglevel` | `8` | verbose kernel log |
| `bootdelay` | `0` | **no pause** — breaking into u-boot needs a continuous stream of characters (see §5) |
| `boot_fastboot` | `fastboot` | at the u-boot prompt, `fastboot` drops into fastboot-over-USB |
| `force_normal_boot` | `1` | `0` selects recovery on **stock** images; **our build has no recovery** ([`12`](12-rom-boot-fixes.md)) |
| `slot_suffix` | `_a` | set to `_b` to boot the **stock** slot |

Facts confirmed from a captured boot0→u-boot log (`firmware/device-state/`):

- **u-boot 2018.07** (Allwinner), boots through OP-TEE/BL31 cleanly to the `Hit any key` prompt.
- **eMMC = controller `mmc2`** (HS400, 8-bit, **7456 MB**). A later `mmc 0 … init fail -95 / card0 init
  failed` is just u-boot probing the **absent SD slot** — harmless, not a storage fault.
- **Two OEM USB upgrade paths run on every boot** (useful when UART TX is unavailable):
  - `usb burn from boot … do_burn_from_boot usb : have no handshake` — an Allwinner **"efex" USB burn
    handshake**; this is what **PhoenixSuit** connects to (needs a firmware `.img`).
  - `scanning usb for storage devices … List file under ULI/factory` — u-boot scans a **USB stick for an
    `ULI/factory` update folder** (seen failing only because no FAT filesystem was present).

---

## 1. Wiring sanity check (do this before powering anything)

A USB-TTL adapter (FT232/CP2102/CH340) exposes 3 pins you need. Allwinner UART is **3.3 V logic**.

- **GND** (adapter) ↔ **GND** (board) — connect first.
- **RX** (adapter) ↔ **TX** (board).
- **TX** (adapter) ↔ **RX** (board).  *(RX/TX cross over.)*
- **Do NOT connect the adapter's VCC / 3V3 / 5V** to the board. The projector powers itself; a VCC jumper
  risks back-powering/frying the pad. If the adapter has a 3.3V/5V jumper, set it to **3.3V** (this only
  sets its logic level; still leave VCC unwired).

If you see nothing in §4, the usual cause is TX/RX not crossed — swap the two signal wires.

---

## 2. Find the serial device on the host

Plug the adapter into the PC (not the projector yet) and check which node it created:

```bash
dmesg | tail -n 15          # look for "... FTDI USB Serial" / "cp210x" / "ch341" -> ttyUSB0
ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
```

Typical node is `/dev/ttyUSB0` (FT232/CP2102/CH340) or `/dev/ttyACM0` (some CDC adapters). Permissions:

```bash
groups | grep -q dialout && echo "ok: in dialout" || echo "not in dialout — use sudo, or: sudo usermod -aG dialout $USER (re-login)"
```

---

## 3. Open the console (115200 8N1, no flow control)

Pick one terminal program. **picocom** is simplest and logs cleanly:

```bash
# picocom (recommended) — Ctrl-A Ctrl-X to quit
sudo apt install picocom
picocom -b 115200 /dev/ttyUSB0 --imap lfcrlf --logfile /tmp/<scratch>

# alternatives:
#   screen /dev/ttyUSB0 115200        (quit: Ctrl-A then \ )   add -L to log
#   minicom -b 115200 -D /dev/ttyUSB0 (configure: Ctrl-A Z)
```

8 data bits, no parity, 1 stop bit, **no hardware/software flow control** are the defaults for all three
at `115200`; no extra flags needed. Keep the `--logfile` — the boot log is the whole point (see §6).

---

## 4. Validate communication (power on and watch)

With the console open, apply power to the projector. On a healthy link you'll see, in order:

1. **boot0 / SPL**: a banner like `HELLO! BOOT0` followed by DRAM init lines (`DRAM: ... MB`).
2. **u-boot**: a `U-Boot 20xx.xx ...` banner, board/env lines.
3. **kernel**: a flood of `[    0.000000] ...` lines (earlyprintk + loglevel 8).

Seeing **any** of that = communication is good. Troubleshooting:

- **Total silence** → TX/RX not crossed, GND not connected, wrong `/dev/ttyUSB*`, or you're not on UART0.
- **Logs appear only when the board is USB-powered from the PC, nothing on wall power** → **bad GND**.
  The USB cable is substituting as the ground path; your dedicated GND wire isn't on real ground. Run a
  solid GND from the adapter to a known-good ground (USB shell / confirmed GND pad; verify ~0 Ω with a
  meter). This can also fix ignored keystrokes. **On this unit it did not:** fixing ground restored the logs
  on wall power, but input still doesn't work.
- **Garbage / mojibake** → wrong baud. This device is **115200**; re-open at exactly that. (If a line of
  `boot0` is readable but the rest is garbage, it's a flaky ground, not baud.)

---

## 5. Getting input to the board and breaking into u-boot

u-boot prints a break-in prompt, but with `bootdelay=0` it may check for a key only once, so hand typing can
miss it. Work through these in order.

**Step 1 — test the adapter alone.** Disconnect it from the projector, join its TX and RX pins, and type in
picocom. Your typing must appear. Also measure TX: it should idle at about 3.3 V.

**Step 2 — stream characters during power-on.** Reconnect with the projector unplugged. In one terminal:

```bash
picocom -b 115200 --noreset --logfile ~/hermes-rx-test.log /dev/ttyUSB0
```

In a second terminal:

```bash
while :; do printf 'x'; sleep 0.005; done > /dev/ttyUSB0
```

Now apply power. Use `x`. Avoid `2` and `d`: from memory of public Allwinner boot0 source, boot0 reads one UART
character at the `key press :` line and treats those two specially (`2` enters FEL, `d` enables debug). `d` is now
confirmed to work; `2` is not.

**Two stream mistakes that caused real problems:**
- Writing with `>` while the adapter is absent, as root, turned `/dev/ttyUSB0` into an ordinary file. Fix: stop the
  stream, `sudo rm /dev/ttyUSB0`, replug the adapter.
- Putting the redirect inside the loop (`printf 'd' > /dev/ttyUSB0`) reopens the port about 200 times a second. Shortly
  after that was suggested, the kernel log filled with `clear tt ... error -71` and the PC's USB hub, carrying the
  adapter, dropped off the bus. The timing points to this loop, though it isn't proven.

Safe form, which opens the port once, won't create a file, and stops if the adapter goes away. Plug the adapter directly
into the PC, not through a hub:

```bash
[ -c /dev/ttyUSB0 ] && while printf 'd'; do sleep 0.005; done > /dev/ttyUSB0
```

| Result | Meaning |
|---|---|
| `sunxi#` or `=>` prompt | Input works. Stop the stream and continue below |
| `[102]key press : x` but no prompt | The board receives input. The problem is at the u-boot stage |
| Neither | The signal is not reaching PH1, go to step 3 |

**Result on this unit: `key press : x`, at both boot0 read points, with no prompt.** Earlier captures had this field
empty. This confirms boot0 reads UART there and RX reaches the chip, so steps 3 and 4 are not needed.

**Step 2b — blind-command test.** u-boot may be listening with its output silenced, so test it without relying on
output. Stream `x` as in step 2. About 10 s after the log stops at `Hit any key`, stop the stream with Ctrl-C and run:

```bash
printf '\003\r' > /dev/ttyUSB0; sleep 1; printf 'reset\r' > /dev/ttyUSB0
```

| Result | Meaning |
|---|---|
| `HELLO! BOOT0` appears again | u-boot's prompt is alive but silent. Commands can be sent blind |
| Nothing | u-boot is not reading input at this point, or is hung |

If it resets, connect the OTG USB port to the PC, repeat the sequence with `fastboot\r` in place of `reset\r`, then run
`fastboot devices` on the PC. Never send `saveenv`.

**Result on this unit: nothing happened** after streaming `x` and sending `reset` blind.

**Step 2c — try other keys.** Same procedure, streaming one key per boot with its own log file. Order: carriage
return, Ctrl-C, space, then `d`. From memory of public Allwinner source, `d` asks boot0 for debug mode, which may add
logging. Results: `x` gave no prompt and no reset. **`d` works:** boot0 prints `detected user input d`, and u-boot
logs far more, including past `Hit any key`, ending at `ramdisk use init boot` ([`12`](12-rom-boot-fixes.md)).

**Use `d` for every future capture.** It does not stop autoboot, so u-boot still doesn't appear to read this input.

**Step 3 — measure the pads.** Always disconnect the adapter's signal wires first and use board ground.

Readings on this unit:

| Adapter wires | Projector state | TX pad | RX pad |
|---|---|---|---|
| Disconnected | Powered | 3.3 V | 3.3 V |
| Connected, adapter **not plugged into the PC** (explains the low values) | Powered | 2.3 V | 1.7 V |

The adapter passes the TX-to-RX loopback test, so it can send and receive.

What this shows:
- **3.3 V suits a 3.3 V adapter**, assuming it reflects the pins' real I/O level. A resistor in series is optional.
- **RX is not floating at 0 V, but that does not prove it reaches PH1.** A board pull-up resistor gives the same
  reading.
- **Keep the adapter plugged into the PC while it is wired to the board.** An unpowered adapter loads the lines, as
  the low readings show.

If step 2 fails, first confirm the wire reaches the pad. With the adapter on the PC and the board on, run
`cat /dev/zero > /dev/ttyUSB0` and measure the RX pad. It should drop well below 3.3 V, then recover on Ctrl-C. If it
stays at 3.3 V, the fault is in your wire or joint, not on the board.

To estimate what is holding RX high, put a **10 kΩ resistor** from the RX pad to ground and read voltage V. The
pull-up is about `10 kΩ × (3.3 − V) / V`. A value near 10 kΩ points to a board resistor, while roughly 100 kΩ could be
the SoC's internal pull-up (typical value, from memory).

Only the streaming test in step 2 proves that input reaches PH1.

**Step 4 — look for the break.**
- **Empty resistor footprint** on the RX trace: bridge it. A common way to disable input on production boards.
- **Mislabelled or different pad:** PH0 and PH1 are neighbours, so follow the TX trace and look nearby for another
  pad that idles high. Test candidates with a **1 kΩ resistor in series** with the adapter's TX, then repeat step 2.
- **Do not use the PF2/PF4 alternate UART** (the DTS `uart_jtag` state on the SD pins): that state belongs to the
  kernel's SD driver, so nothing suggests u-boot listens there.

Once at the prompt, confirm with:

```text
sunxi# printenv          # dumps the env; verify bootdelay/slot_suffix/force_normal_boot/fastboot vars
```

**If input can't be made to work:** see the other routes in [`13`](13-fastboot-trigger-no-fel.md). The earlier
advice here to use a "hardware fastboot key combo" was wrong: no such buttons are known to exist on this unit.
UART output is still valuable for diagnosis (§6).

> **Rule: never `saveenv`.** Everything below sets variables for *one* boot only. Persisting a changed
> env is exactly the "don't touch `bootloader`/`env`" brick risk from `07`/`10`.

---

## 6. Diagnose the hang (why `_a` dies at the logo)

Let it boot normally (don't break in, or type `boot` at the prompt) and **capture the full log**
(`--logfile` from §3). Save a copy for analysis:

```bash
cp /tmp/<scratch> firmware/device-state/uart-boot-hang.log
```

Read it top-to-bottom; **where it stops is the diagnosis.** Look for these milestones in order:

| Last thing you see | Likely cause | Next move |
|---|---|---|
| `Starting kernel ...` then silence | DTB/dtbo mismatch, or kernel can't bring up console device | compare our `dtbo.img` vs stock; check cmdline reached kernel |
| kernel logs, then `Kernel panic - not syncing: ... init` | first-stage init died (bad ramdisk / missing module) | check `init_boot`/`vendor_boot`, first-stage module list |
| `init: First stage` / `dm-verity` / `avb` errors | AVB/verity rejecting an image | we build `--flags 2` + unlocked, so this should be non-fatal — but confirm |
| `Failed to mount /vendor` / `fs_mgr` errors | fstab / dynamic-partition (`super`) problem | verify `super` flashed, fstab partitions |
| `avc: denied` flood then reboot/hang | SELinux enforcing against our near-empty vendor policy | test permissive (below) |
| insmod/modprobe failure on a `.ko` | a first-stage `BOARD_VENDOR_RAMDISK_KERNEL_MODULES` module | identify the module, drop/fix it |

### If it *stalls at* `Hit any key to stop autoboot:` and never continues

**This is what happens on this unit, and it is not a real stall at this line.** u-boot's messages are hidden at the
default debug level. With `d` streamed, it continues past this line, reads `boot_a` and the vbmeta images, and stops
at `ramdisk use init boot`, with no `Starting kernel`. See [`12`](12-rom-boot-fixes.md). A capture of **stock**
booting would show what normally follows.

### No working input? Recover without the u-boot console

Some consumer boards expose console output only. See [`13`](13-fastboot-trigger-no-fel.md) for the routes that
don't need it. UART stays useful as a monitor while trying them.

**The earlier method here was wrong.** It told you to hold a button and read an ADC value from `key press :`.
This unit has no such buttons, and that line reports a UART character (confirmed), not a button. The `keyadc0` table
below is kept only as a record of what the DTS describes; nothing shows those keys exist on this board.

| key | key*_vol | Linux keycode | button |
|---|---|---|---|
| key0 | 0x000 (0 mV)    | 0x8B (139) | **MENU** |
| key1 | 0x190 (400 mV)  | 0x69 (105) | LEFT |
| key2 | 0x258 (600 mV)  | 0x1C (28)  | ENTER |
| key3 | 0x320 (800 mV)  | 0x67 (103) | UP |
| key4 | 0x3E8 (1000 mV) | 0x179 (377)| TV |
| key5 | 0x49C (1180 mV) | 0x6A (106) | RIGHT |
| key6 | 0x546 (1350 mV) | 0x9E (158) | BACK |
| key7 | 0x60E (1550 mV) | 0x6C (108) | DOWN |

The env also has `fastboot_key_value_min/max` (`0x2–0x8`) and `recovery_key_value_min/max` (`0x10–0x13`). What
reads them, and on what scale, is unknown.

### Quick isolation tests (one-boot, from the `sunxi#` prompt)

These rebuild `bootargs` with `setargs_nand`, append a flag, then boot — without persisting anything:

```text
# Test whether SELinux is the blocker (boots permissive):
sunxi# run setargs_nand
sunxi# setenv bootargs "${bootargs} androidboot.selinux=permissive"
sunxi# run boot_normal

# Even louder kernel + stall detection, if the log cut off too early:
sunxi# run setargs_nand
sunxi# setenv bootargs "${bootargs} ignore_loglevel printk.devkmsg=on"
sunxi# run boot_normal
```

If **permissive boots** and enforcing doesn't, the fix is sepolicy (our `sepolicy/vendor` is a
placeholder) — report that back and I'll address it in the device tree. If it still hangs permissive,
SELinux is not the cause; use the milestone table.

---

## 7. Get into fastboot / recovery from u-boot

Once at `sunxi#`:

```text
# --- FASTBOOT (the rescue: then re-flash per docs 10/07 over USB) ---
sunxi# fastboot
#   ...then on the host:   fastboot devices   (must list the serial)   ->   flash per doc 10/07

# --- Boot RECOVERY (stock images only: recovery lives in vendor_boot; OUR BUILD HAS NONE, see docs/12) ---
sunxi# setenv force_normal_boot 0
sunxi# boot

# --- Boot the STOCK slot _b (instant return to a known-good OS; _b was never touched) ---
sunxi# setenv slot_suffix _b
sunxi# boot

# --- Resume a normal slot _a boot ---
sunxi# boot
```

Notes:
- `fastboot` here is the env's `boot_fastboot` command — it brings up **fastboot over the OTG USB port**
  (`usbc0`, the same port as adb/FEL). Connect that port to the host and `fastboot devices` should list it.
  This is the clean way back to the [doc 10](10-flashing-the-build.md) flashing flow.
- **`setenv slot_suffix _b; boot` is the first thing to try** — `_b` was not flashed, so it may boot stock.
  Untested: `boot_normal` reads the partition `boot` by a name with no visible slot, `super` is shared, and
  `update bootcmd` may change the command.
- `boot` runs the env's `bootcmd`, which the log suggests u-boot updates at boot, so check it with `printenv` at
  the prompt. The `setenv` lines above change one variable for this boot only; power-cycling restores the
  stored values (we never `saveenv`).
- The stock `boot_recovery` var (`sunxi_flash read 40007000 recovery; bootm`) reads a `recovery` partition, and
  none is listed in `ab_partition_list`. Stock's recovery is in `vendor_boot`, selected by `force_normal_boot=0`.

---

## Quick reference

```bash
# host: open console + log
picocom -b 115200 /dev/ttyUSB0 --imap lfcrlf --logfile /tmp/<scratch>
# second terminal, then power on:  while :; do printf 'x'; sleep 0.005; done > /dev/ttyUSB0   ->  prompt: sunxi#
```
```text
sunxi# printenv                               # inspect env
sunxi# fastboot                               # -> fastboot over USB (reflash per doc 10/07)
sunxi# setenv slot_suffix _b ; boot           # boot stock slot _b (known good)
sunxi# setenv force_normal_boot 0 ; boot      # boot recovery (stock images only; our build has none)
sunxi# run setargs_nand ; setenv bootargs "${bootargs} androidboot.selinux=permissive" ; run boot_normal
#        ^ one-boot permissive test to isolate the hang
```
> Never `saveenv`. Wire UART0 only, 3.3V logic, VCC unwired, 115200 8N1.
