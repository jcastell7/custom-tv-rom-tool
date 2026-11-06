# HDMI input, factory menu, preinstalled apps and root

## Right click as Back
`CursorButtonAccumulator` in `frameworks/native` reports the right mouse button as `BUTTON_BACK`, which the cursor mapper turns into `KEYCODE_BACK`. This applies to every mouse and trackpad, so apps no longer see a secondary click. Patch: `lineageos/patches/inputflinger-right-button-back.patch`.

## HDMI input and factory menu
The TV input HAL was already running and reporting 7 inputs. These stock pieces are added, unpacked from the stock `system` image into `vendor/hermes-gapps/` by `tooling/gapps/setup-gapps.py`:

| File | Role |
|---|---|
| `VideoInputService` | `TvInputService` for the physical inputs |
| `AwSource` | Input picker |
| `AwLiveTv` | Viewer |
| `AwTvFactoryMenu` | Factory test and configuration tool |
| `com.softwinner.tv.jar` and its XML | Library the apps use |
| `libawimage_jni`, `libdvbcore_jni`, `libdvb_core_client`, `vendor.aw.tvserver@1.0` | Native libraries, stock copies |

All four native libraries resolve against this build with no missing symbols.

**First flash failed:** `system_server` aborted with `Signature|privileged permissions not in privapp-permissions allowlist`, even with stock's `ro.control_privapp_permissions=permissive` property set. The script now generates `privapp-permissions-hermes.xml` from the apps' manifests.

The apps use platform-only permissions, and `AwTvFactoryMenu` runs as `android.uid.system`, so the build re-signs them with our platform key (`LOCAL_CERTIFICATE := platform`). Stock's signature can't be kept, because it would have to match our framework.

## Keystone correction
Stock's `ProjectionSettings.apk` (`com.telanda.keystone`) has manual four-corner adjustment and tilt-based auto correction. The warp is done by the vendor HAL, `vendor.display.config@1.0::IDisplayConfig.keystoneSetCoordinates`, which is in `vendor.display.config@1.0-impl.so` and already runs on this build. The app has its own copy of the HAL client and uses the accelerometer through `SensorManager`.

Stock's modified framework did two more things, and `HermesKeystone` does them here, rather than patching the framework:
- `WindowManagerService.initTCorrection` restored the corners at boot from `persist.display.keystone_*`.
- `PhoneWindowManager.GlsStartGsensor` started `GensorService`. Here it only starts when `persist.sys.Auto.Correction` is true, because it stays in memory.

`HermesKeystone` also adds a launcher icon, since the stock app has none. `persist.keystone.*` and `persist.sys.keystone.*` tuning values come from the capture of this unit.

**Name collision found while testing:** the first build failed with `HwBinder Error: (-74)`, which is `UNKNOWN_TRANSACTION`. `vendor/lib/vendor.display.config@1.0.so` was built from `vendor/qcom/opensource/interfaces/display/config/1.0`, Qualcomm's unrelated HAL with the same name, which has no keystone methods. Allwinner's library had been dropped from the blob list as a collision, and FIX 10 then installed the Qualcomm module. The build rejects two rules for that path, even with the Qualcomm module not installed. So `tooling/vendor-fixups/rename-display-config.sh` renames the stock file to `vendor.display.config.aw@1.0.so` and updates what links to it. **Rerun it if the blobs are extracted again.** The HIDL interface name is unchanged. `AwTvDisplayManager` catches this error and only prints a stack trace, so `HermesKeystone`'s "Restored" log line doesn't prove the call worked; check for `HwBinder Error`.

**Autofocus isn't included.** `GensorService` can start `com.hysd.hyscreen.VAF2S`, which isn't in the stock image inventory.

## Preinstalled apps
| App | Source | Check |
|---|---|---|
| Jellyfin (Android TV) 0.19.10 | F-Droid | SHA-256 matches `index-v2.json` |
| VLC 3.7.2 (armeabi-v7a) | F-Droid | SHA-256 matches `index-v2.json` |
| AdAway 6.1.4 | F-Droid | SHA-256 matches `index-v2.json` |
| Symfonium 15.1.0 TV | [Developer's Android TV repository](https://repo.symfonium.app/androidtv/repo/) | SHA-256 matches the repository index; closed source, activated with your own license |
| SmartTube 32.71 (armeabi-v7a) | [GitHub release](https://github.com/yuliskov/SmartTube/releases); not on F-Droid | Recorded SHA-256 `288e8caa...`, no published hash to compare |

They keep their publishers' signatures, so they can update normally. They use compressed native libraries, which Android doesn't extract for system apps. **First attempt:** `LOCAL_PREBUILT_JNI_LIBS`. The build then rewrote the APKs, Android rejected them with `No APK Signature Scheme v2 signature`, and they weren't installed. **Fix:** `LOCAL_REPLACE_PREBUILT_APK_INSTALLED` installs each APK untouched, and the libraries are copied to `lib/arm` beside it.

## Browser
`com.internet.tvbrowser` isn't bundled. It's closed source, and APKMirror refuses automated downloads (`403`). Install it from the Play Store, or give `adb install` an APK you downloaded.

## Root for AdAway
Magisk 31.1, from its [GitHub release](https://github.com/topjohnwu/Magisk/releases) (recorded SHA-256 `89cefac0...`, no published hash to compare), isn't in the ROM. It warned about being a system app and it updates itself, so it's installed as a user app with `adb install`. A userdata wipe removes it.

LineageOS's `su` only works for the shell and root users. A setuid `su` can't work for apps, because zygote clears their capability bounding set, so app root needs a daemon. Magisk provides that, and asks for approval per app on screen.

`tooling/root/patch-init-boot.sh` runs Magisk's patcher on the booted device and produces a patched `init_boot`. A plain full flash removes root, so pass `INIT_BOOT_IMG=<patched image>` to `flash-lineage-fastbootd.sh`. Repatch if `init_boot` itself changes.

**Risk:** first-stage init comes from `init_boot`, and recovery uses it too. If a patched image fails very early, fastbootd won't come up either, and recovery needs `tooling/rescue-stick/make-stick.py ramboot`.

Root is a real security trade-off. Any app you approve gets full control of the device.
