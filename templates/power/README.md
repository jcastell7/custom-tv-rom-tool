# Power button and shutdown

Read [`docs/13-TUNING.md`](../../docs/13-TUNING.md), section 5, first.

| File | Goes to | Does |
|---|---|---|
| `power.rc.snippet` | your vendor `.rc` file | Blocks kernel suspend, turns the lamp off when shutdown starts, turns the swap file off |
| `../patches/framework-power-button-menu.patch` | `frameworks/base` | A short press of power opens the power menu, and a press while it's open powers off without asking |

**Before using them:**
- **Find your device's lamp and fan switches.** On the first device they were `/sys/class/backlightandfan/{backlight,fan,led}/value`, from a kernel driver with `compatible = "allwinner,backlightandfan"`. Search stock's `services.jar` with `dexdump` for `/sys/class/`, and the device tree for `fan` and `backlight`. See `docs/06-FEATURE-PARITY.md`.
- **Ask the user what they want.** This suits a device that is unplugged after use. If they want standby instead, it needs a different design and a long temperature test (docs/13, 5d).
- **Check how stock behaved.** On the first device, stock opened a power menu on a short press, and never slept.
- Change `/data/vendor/swapfile` to your swap file's path, or remove that line if you have none.

**To test without powering off:** `adb shell input keyevent 26` should open the menu, with `ActionsDialog` focused (`dumpsys window | grep mCurrentFocus`). `input keyevent 4` closes it. A second press powers off, so only test that when the user can switch the device back on.

**Results on the first device:** about 10 s from confirming to the fan stopping, measured by the user with `tools/measure/shutdown-timer.sh`.
