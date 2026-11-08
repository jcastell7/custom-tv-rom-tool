# Resource overlays

Copy `packages/` into `<device tree>/overlay/`, and add `PRODUCT_PACKAGE_OVERLAYS += $(DEVICE_PATH)/overlay` to `device.mk`. These are static overlays: the build compiles them into the app.

| Overlay | Why |
|---|---|
| `TvSettings show_bluetooth_toggle=true` | With Bluetooth off, "Remotes and accessories" shows only its title: TvSettings hides the toggle by default, and the pair button needs Bluetooth on. Only safe with another input, such as an IR remote |

Check it reached the build: `aapt2 dump resources <out>/system_ext/priv-app/TvSettingsTwoPanel/TvSettingsTwoPanel.apk | grep -A1 show_bluetooth_toggle`.
