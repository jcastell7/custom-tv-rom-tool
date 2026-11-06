# Keeping the stock device's features

> **⚠️ WARNING: this process could very well fully and permanently brick your device.** Only use it on a device you own and can afford to lose. It's provided as is, with no warranty, and **we accept no responsibility** for how it's used or what happens. Not affiliated with LineageOS in any way: we just use and recommend their work, so [please donate to them](https://lineageos.org/about/) when you can. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

TV boxes and projectors have features that AOSP knows nothing about. **Do this inventory while stock still runs.** On the first project, these were found late: keystone correction, HDMI input, the factory menu, and right-click as Back. Each needed another round of work.

## Step 1: Make a list with the user, on stock

Go through this with them, and record what they use:

| Area | What to ask or check |
|---|---|
| Display | Keystone, zoom, four-corner, overscan, picture modes, HDR, resolution switching |
| Inputs | HDMI in, AV/CVBS, USB video, tuner. Which app shows them? |
| Remote | IR and Bluetooth. Every key, including power, volume, Back, Home, voice, and mouse or trackpad modes |
| Sensors | Tilt, distance, autofocus, motor |
| Audio | Speaker, HDMI out, S/PDIF, Bluetooth speaker mode, Bluetooth sink |
| Network | Wi-Fi, Ethernet, hotspot |
| Casting | AirPlay, Miracast, Chromecast |
| Tools | Factory or test menu, file manager, updater, boot logo |
| Power | Standby behaviour, what the power button does, auto power on |
| Storage | USB drives, SD |

Save stock's state, which you can't get back afterwards:
```bash
adb shell getprop > stock-getprop.txt
adb shell dumpsys input > stock-input.txt       # which key layout each device uses
adb shell getevent -pl > stock-events.txt
adb shell dumpsys tv_input > stock-tv-input.txt
adb shell dumpsys display > stock-display.txt
adb shell dumpsys audio > stock-audio.txt
adb shell pm list packages -f > stock-apps.txt
```
If the user changes a setting, note the property or setting that changed: `settings list global`, `system` and `secure`, before and after.

## Step 2: Find what implements each feature

```bash
tools/31-find-feature.py stock/fs 'keystone|trapezoid' 'hdmi.?in|tvinput' 'focus' 'factory'
```

Also look at the app list for names like `Aw*`, `Tv*`, `*Settings`, `*Source`, `*Input`, `*Factory`. Compare against what AOSP normally ships. Anything unfamiliar is probably a device feature.

## Step 3: Work out which layer it needs

There are four possible answers, and they differ a lot in effort:

| What you find | What it means | Effort |
|---|---|---|
| A vendor HAL or library has it | It's already in your image | Low: just needs an app to call it |
| A stock app calls the HAL with its own code | Add the app, re-signed | Low |
| A stock jar in `/system/framework` has it | Add the jar, its XML and its native libraries | Medium |
| `services.jar` or `framework.jar` has it | Stock changed the framework. **Read what it does**: often it only forwards to a HAL or restores a setting at boot | Medium to high |

**Don't assume the worst from the first hit.** On the first device, keystone appeared in `services.jar`, which looked like a framework port. Reading it showed that the framework only restored saved values at boot and started a service. A 60-line companion app did the same job.

To read framework code:
```bash
unzip services.jar 'classes*.dex'
TREE/out/host/linux-x86/bin/dexdump -d classes.dex > dump.txt
```
Then search `dump.txt` for your keyword and read the `invoke-*` lines nearby.

## Step 4: Add it

### Stock apps

Stock apps are usually signed with the manufacturer's platform key, and they often declare `android:sharedUserId="android.uid.system"`. That only installs when the signature matches your framework, so they must be re-signed with your platform key. In `tools/80-apps.py`, use `"certificate": "platform"`, and `"privileged": true` if it was in `priv-app` on stock.

**Check before you add one:**
```bash
aapt2 dump badging App.apk                 # uses-library, launchable activity
aapt2 dump xmltree --file AndroidManifest.xml App.apk | grep -E 'sharedUserId|uses-library'
aapt2 dump permissions App.apk
```

| Finding | Action |
|---|---|
| `uses-library: com.vendor.x` | Add that jar and its XML from `/system/framework` and `/system/etc/permissions` |
| `System.loadLibrary("x")` | Add `libx.so` from `/system/lib`. Check it with `50-gate.py` |
| No launcher activity | Add a companion app with an icon: `templates/companion-app-example/` |
| TV launcher doesn't show it | It needs a `LEANBACK_LAUNCHER` activity and a banner |

**Native library check:** the first device's HDMI libraries all resolved against LineageOS, so they could be used unchanged. Check this for yours, as a library that links against private framework APIs can fail.

### Framework behaviour

Before you patch the framework, see if a small system app can do it. For anything done at boot, a `BOOT_COMPLETED` receiver works. Reach stock's code through `createPackageContext` with `CONTEXT_INCLUDE_CODE`, when it shares your user ID. See `templates/companion-app-example/src/`.

Patch the framework only for things an app can't do, like input mapping. Keep patches small, and save them.

### Key layouts

Stock's `.kl` files can name keycodes that only its own framework defines. **A single unknown name rejects the entire file**, with `Generic.kl` used instead. To check:
```bash
awk '/^key/{print $3}' file.kl | sort -u | while read k; do
  grep -q "AKEYCODE_$k\b" frameworks/native/include/android/keycodes.h || echo "UNKNOWN $k"
done
```

### Saved settings and tuning

Stock's sensors and tuning properties are often device-specific calibration, like `persist.keystone.*`. Copy them from `getprop`. Note that a `persist.*` value set in `build.prop` is only a default.

## Step 5: Test with the user

**You can't verify most of these from a shell.** A service accepting a call doesn't prove the picture moved, so ask the user. Tell them what you checked, and what only they can check. Keep this table up to date:

| Feature | Checked by me | Needs the user |
|---|---|---|
| Keystone | HAL call returns with no error | Does the picture change? Does it survive a reboot? |

When a user reports "X doesn't work", check the logs before concluding where the fault is. On the first device, "arrow keys don't work" meant the keys worked and the display library didn't.

## What the first device needed

| Feature | Implemented by | What we added |
|---|---|---|
| HDMI, CVBS input | `tv.input` HAL (running), `VideoInputService` | Stock's service, `AwSource`, `AwLiveTv`, `com.softwinner.tv.jar`, 4 native libraries |
| Keystone | `vendor.display.config` HAL, `ProjectionSettings` | App re-signed, correct library, companion app |
| Factory menu | `AwTvFactoryMenu` | App re-signed, library |
| IR remote | `sunxi-ir` kernel driver, `.kl` | Fixed `.kl` |
| Right click as Back | Stock framework change | One-line input patch |
| Bluetooth, Wi-Fi | Seekwave chip | See the debug catalog |

Status of these on the first device when this was written: installed and registered, but the user hadn't yet confirmed every one. See the case study.
