# Google Play and F-Droid

`tooling/gapps/setup-gapps.py` unpacks both into `vendor/hermes-gapps/` in the build tree, and `device.mk` inherits it if present. The APKs aren't committed.

## Sources
| Package | File | Check |
|---|---|---|
| Google apps | [MindTheGapps 14.0.0-arm-ATV](https://github.com/MindTheGapps/14.0.0-arm-ATV/releases), `minimal-20240523_192108` | SHA-256 `e36bc0db...fb62a652`, recorded at download; the release publishes no checksum |
| F-Droid | [f-droid.org/F-Droid.apk](https://f-droid.org/F-Droid.apk), 2.0.2 | Signing certificate `43238d51...a9c9ccab`, checked by the script |

This is the 32-bit Android TV build, which matches this device and LineageOS 21.

## What's installed
From MindTheGapps: `PrebuiltGmsCorePano` (Play services), `Tubesky` (Play Store, `com.android.vending`), `GoogleServicesFramework`, `GoogleExtShared`, `GoogleOneTimeInitializer`, `AtvRemoteService`, `ATVOverlay`, and its permission and sysconfig files.

Left out: `SetupWraithPrebuilt` (Google TV setup), because it hit repeated ANRs with about 15 MB of RAM free while its intro video played. With it installed, the projector showed a black screen with sound. `LineageSetupWizard` handles first run instead: Wi-Fi, remote pairing, language and date. It has no Google login, so signing in is optional, through Settings. That path is untested without the setup app.

**Why this works:** `SetupWizardActivity` exits immediately when Play services and Google's TV setup app are both installed. Without Google's app, the Lineage wizard runs normally.

**Attempt that was wrong, kept for the record:** removing `LineageSetupWizard` as well and marking the device as set up with an overlay. That would have removed first-run Wi-Fi and remote setup. The user caught it, and reading the source confirmed it.

Also left out, to save storage and memory: TalkBack, Google TTS, Chromecast (`AndroidMediaShell`), voice search (`Katniss`), `Backdrop`, `GoogleFeedback`, calendar sync, `DfuService`.

F-Droid is a normal system app, so it installs apps through the usual confirmation prompt. The privileged extension, which would allow silent installs, isn't included.

## Known limit
This build reports its own fingerprint, not stock's spoofed ADT-3 one (`docs/02`). Google may treat the device as uncertified, which can block sign-in until its GSF ID is registered at [google.com/android/uncertified](https://www.google.com/android/uncertified).
