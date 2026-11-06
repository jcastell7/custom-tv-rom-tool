# Flashing the LineageOS build (Allwinner H723 "hermes" projector)

How to flash a freshly built LineageOS 21 onto the device over the bootloader's fastboot, plus the
recovery ladder if it doesn't boot. Mirrors the stock restore flow in
[`07-stock-backup-and-restore.md`](07-stock-backup-and-restore.md) — same u-boot fastboot, same
slot `_a`, same "don't touch `bootloader`/`env`" rule.

> **First flash = raw images over fastboot, NOT the `lineage-*.zip`.** The bacon zip is a recovery/OTA
> package for *updating* an already-installed LineageOS; the stock recovery can't apply it (signature +
> format). For the initial install you flash the raw partition images below.

> **Read before flashing.** This has already left one unit stuck with no way to flash it
> ([`13`](13-fastboot-trigger-no-fel.md)). **Whether the build boots is unknown, and it contains no recovery**
> ([`12`](12-rom-boot-fixes.md)). If it fails, `adb` is gone and no key combo is known. Have a working way back
> into fastboot, tested **before** flashing, such as a confirmed UART prompt.

---

## 0. Prerequisites (one-time)

- **Build finished.** Images are in `out/target/product/hermes/` under the build root
  `/path/to/lineage-21.0`.
- **Bootloader unlocked** — confirmed `orange` (see `07`, "Verifying the bootloader is unlocked").
- **USB cable** to the projector's OTG port (`usbc0` — the same port used for adb/fastboot/FEL).
  Fastboot is **USB-only**; wireless adb won't work for flashing.
- **Stock backup present** for rollback (`firmware/partitions/` + `firmware/backup/`, see `07`).
- **FEL is not a safety net yet.** The recessed button enters FEL (see `07` Option C), but we lack the bootloader
  files and tooling to flash through it. A failed boot with no fastboot access can leave the unit stuck.
- `fastboot`/`adb` on PATH (the project's `tooling/` copies are fine).

---

## 1. Build the super image

`mka bacon` builds the logical partition images and `super_empty.img`, but **not** a populated
`super.img`. The device's u-boot sees `super` as a plain partition, so flashing one raw `super.img` is
the simplest path (no userspace fastbootd needed). Build it:

```bash
cd /path/to/lineage-21.0
source build/envsetup.sh && breakfast hermes
mka superimage            # -> out/target/product/hermes/super.img  (~2.5 GB, takes a while)
```

Confirm the images you'll flash all exist:

```bash
cd out/target/product/hermes
ls -lh boot.img init_boot.img vendor_boot.img dtbo.img \
       vbmeta.img vbmeta_system.img vbmeta_vendor.img super.img
```

---

## 2. Enter fastboot

```bash
adb reboot bootloader            # or: adb reboot fastboot
fastboot devices                 # MUST list the device before continuing
```

If adb isn't available, **no hardware trigger for fastboot is known on this unit**. The remote navigates the menu
once inside fastboot, but does not get you in as far as we know. See [`13`](13-fastboot-trigger-no-fel.md).
`fastboot devices` printing a serial is the go/no-go check.

---

## 3. Flash

Partition names are **slot-suffixed `_a`** (the active slot; the build output files are not suffixed, so
map file → `_a` partition). `super` is a single unslotted physical partition. This order matches stock
`flash-all.sh` (vbmeta/dtbo/boot chain first, then the big super):

```bash
cd /path/to/lineage-21.0/out/target/product/hermes

fastboot flash vbmeta_a        vbmeta.img
fastboot flash vbmeta_system_a vbmeta_system.img
fastboot flash vbmeta_vendor_a vbmeta_vendor.img
fastboot flash dtbo_a          dtbo.img
fastboot flash boot_a          boot.img
fastboot flash init_boot_a     init_boot.img
fastboot flash vendor_boot_a   vendor_boot.img
fastboot flash super           super.img        # ~2.5 GB, slow
fastboot reboot
```

### vbmeta / verity notes
- The build's vbmeta is made with `--flags 2` (dm-verity disabled), and the device is **unlocked
  (orange)** so AVB verification errors are **non-fatal** — it boots regardless. No extra flags needed.
- Belt-and-suspenders (optional): add host-side flags to also clear the verification flag while flashing
  vbmeta, e.g. `fastboot --disable-verity --disable-verification flash vbmeta_a vbmeta.img`. Harmless on
  an unlocked device; skip if your fastboot build rejects the options.

### What NOT to flash
- **Never flash `bootloader` or `env`** as part of a ROM install: brick risk, and we hold no bootloader image to
  restore. The only planned exception is the validated env change in [`14`](14-power-key-boot-trigger.md). We
  also don't flash `userdata`/`metadata`/`frp`/`misc` (a factory reset handles user data).

---

## 4. First boot

- Boot may be **slow** the first time (dexopt/first-run). Give it several minutes.
- A **black screen / no projector image early on is not necessarily failure** — give it time before
  concluding it's stuck.
- If it boots to LineageOS: done. Subsequent updates can use the `lineage-*.zip` via the Updater. LineageOS
  recovery isn't available until recovery is added to the build.

---

## 5. If it doesn't boot (recovery ladder)

**The earlier claim that nothing here can hard-brick the device was wrong in practice:** u-boot survives, but
without a way into fastboot the unit can't be reflashed. In order of use:

1. **Re-enter fastboot and re-flash** (Step 2–3). This needs a way in: u-boot being alive does not provide one
   by itself, because no hardware trigger is known and adb is gone.
2. **Roll back to stock** — `firmware/backup/fastboot/flash-all.sh --commit` (see `07` Option A). Also needs
   fastboot.
3. **FEL mode**: recessed FEL button → USB → host shows `1f3a:efe8`. Not usable for flashing yet, see `07` Option C.

> **Early hang with no adb *and* no fastboot?** That is the current state of this unit. Use the
> **UART serial console** — [`11-uart-serial-console.md`](11-uart-serial-console.md) — if input can be made to
> work, and see [`13`](13-fastboot-trigger-no-fel.md) for the other routes.

---

## 6. A/B / slot notes

- The device boots slot **`_a`**; we flash `_a`. `super` is one physical partition shared by both slots
  (Virtual A/B — the `_b` slot is a snapshot, not a second copy).
- This is a first install, not an OTA, so we flash `_a` directly rather than staging the inactive slot.
- For future seamless updates, the `lineage-*.zip` applied from the Updater handles the A/B slot switch itself
  (LineageOS recovery too, once the build includes one).

---

## Quick reference

```bash
# build
cd /path/to/lineage-21.0 && source build/envsetup.sh && breakfast hermes
mka bacon && mka superimage

# flash
adb reboot bootloader && fastboot devices
cd out/target/product/hermes
for p in vbmeta vbmeta_system vbmeta_vendor dtbo boot init_boot vendor_boot; do
  fastboot flash ${p}_a ${p}.img
done
fastboot flash super super.img
fastboot reboot
```
