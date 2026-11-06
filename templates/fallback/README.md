# Automatic return to fastboot after a failed boot

Add these from the very first build. They were verified on hardware: after a hang or a boot loop, the first device came back to fastbootd with nothing inserted.

| File | Goes to | Does |
|---|---|---|
| `boot-watchdog.sh` | `/vendor/bin/hermes-boot-watchdog.sh` | Counts boots in `/metadata`. Third failed boot, or 15 minutes without `sys.boot_completed`: reboots to recovery |
| `bringup.rc` | `/vendor/etc/init/` | Starts the watchdog at post-fs-data, clears the counter at boot complete, and quiets the console |
| `recovery-auto-fastbootd.rc.snippet` | Your `recovery/root/init.recovery.<hardware>.rc` | Switches recovery to fastbootd 4 s after it starts, and clears the counter |
| `wl-retry.sh` | `/vendor/bin/` | Reruns a stock chip-driver loader once. Change the device path and service name for your chip |
| `device.mk.snippet` | Your `device.mk` | Lists what to add |

**Adapt these before use:**
- `bringup.rc` also starts swap and the chip-driver retry. Remove the services you aren't installing, or `init` logs errors. The script names must match where you install them.
- `/dev/BTBOOT` and `wl_info` in `wl-retry.sh` belong to the Seekwave chip on the first device.

**What this can't catch:** kernel panics and hangs before init. For those you need `androidboot.init_fatal_reboot_target=recovery` (for init failures only), and the routes in `docs/03-RECOVERY-ROUTES.md`.

**Remove all of it before calling a build final.**
