# Memory and swap

The unit has 1 GiB of RAM. The kernel reports 791 MiB available at boot; the rest is kernel code and carve-outs, including a 150 MiB region at `0x76a00000`.

## What was wrong
Measured with GApps installed, during first boot, with Google's setup app running:

| Measure | Value |
|---|---|
| `MemAvailable` | 0 |
| Free | about 15 MB |
| Swap | 0, zram never started |
| File cache | 68 MB |
| Load average | 17–30 |

- **zram:** stock's `init.ram.rc` waits for `vold.post_zram_writeback=1`, which our vold never sets.
- **Heap limit:** `dalvik.vm.heapgrowthlimit` was unset, so apps could grow to the 256 MiB `heapsize` instead of stock's 128 MiB.
- **Largest processes by RSS:** `system_server` 98 MB, three or more Play services processes at 45–70 MB each, TV launcher 63 MB, SystemUI 60 MB, then about 15 more at 43–50 MB. RSS counts shared pages repeatedly, so these don't add up to real usage.

## Changes
- `hermes-swap.sh`: 512 MiB lz4 zram at priority 100, then a file of one byte under 2 GiB at `/data/vendor/hermes_swapfile` at priority 10, because toybox `fallocate` rejects larger sizes. There's no spare partition, and the GPT stays untouched. The file takes 2 GiB of the 4.36 GiB `userdata`, and it wears the eMMC when in use. A userdata wipe removes it, and it's recreated on the next boot.
- Stock's heap and dexopt properties.
- `hermes-removed-apps` in `Android.mk` overrides `Settings` and the phone stack: `TeleService`, `Dialer`, `Contacts`, `messaging`, `MmsService`, `WAPPushManager`, `Stk`, `ONS`, `EmergencyInfo`, `CallLogBackup`, `ImsServiceEntitlement`, `CarrierConfig`, `CarrierDefaultApp`, `CellBroadcastLegacyApp`, `com.android.cellbroadcast` and `rild`. On the build before this, `com.android.phone`, `imsserviceentitlement`, `cellbroadcastreceiver.module` and `smspush` each used 42–46 MB RSS, with no modem to talk to. `ContactsProvider` stays for Play services, and `Telecom` stays because it wasn't running and the framework expects it. A first attempt, swapping `aosp_base_telephony` for `aosp_base`, had no effect because `atv_base.mk` inherits telephony itself. `TVLauncherNoGMS` is the only launcher. `TvSettings` remains for its fallback home.
- Google's setup app removed ([`16`](16-google-play-and-fdroid.md)).

## lmkd: a mistake, corrected
FIX 11 and the first version of this work copied stock's lmkd tuning: `use_new_strategy=false`, `critical=1`, `critical_upgrade=true`, `upgrade_pressure=30`, `downgrade_pressure=95`, `kill_heaviest_task=true`.

**Result:** Google sign-in closed by itself, and the Play Store reported "account not found". With 2.4 GB of swap free, lmkd killed the on-screen `tv.settings`, `gms.ui`, `gms.persistent` and the keyboard within seconds. The `killinfo` events showed `min_oom=1` and kill reason `-1`, which is the old strategy: it reacts to pressure levels, ignores swap, and with `critical=1` can kill nearly anything.

**Fix:** remove that tuning and set `use_new_strategy=true`, the default for low-RAM devices, which kills based on real low-memory and thrashing conditions. `thrashing_limit=100` raises the low-RAM default of 30, because swapping to eMMC refaults a lot without the device being out of memory.

## Not changed
- The 150 MiB carve-out at `0x76a00000` comes from the stock device tree and may be needed by display or video. Shrinking it could gain the most, but it needs testing.
- Bluetooth still crash-loops, which costs CPU on every restart.

## Result on hardware
With Play services running, at first boot on the wizard: `MemAvailable` about 334 MB, swap total 2621428 kB (zram plus file), about 1.7 GB free on `/data`.
