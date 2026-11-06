# Kernel choice, and what stays closed source

> **⚠️ WARNING: this process could very well fully and permanently brick your device.** Only use it on a device you own and can afford to lose. It's provided as is, with no warranty, and **we accept no responsibility** for how it's used or what happens. Not affiliated with LineageOS in any way: we just use and recommend their work, so [please donate to them](https://lineageos.org/about/) when you can. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

**Tell the user both of these at the start.** They affect what the finished ROM is, and whether it suits them.

## This ROM isn't fully open source

The toolkit's default approach keeps the device's stock kernel and vendor files, unless an open or manufacturer alternative fits, and builds open source LineageOS on top. **Parts of the result stay closed-source binaries that nobody can inspect or fix, supplied by the manufacturer and its suppliers.** "LineageOS" here doesn't mean an open device.

What the first device reused:

| Component | Closed? | What it does | Count there |
|---|---|---|---|
| Bootloader chain (boot0, u-boot, monitor, SCP) | Binary. Parts are based on open code, but the source wasn't available | Starts the device | Left untouched |
| TEE (OP-TEE build) and trusted apps | Binary | Keys, keymint, DRM | 3 `.ta` files, plus the TEE |
| Kernel | **Binary here.** Linux is GPL, but no matching source was available | Everything | 1 |
| Kernel modules | Binary. Some may be proprietary, and others GPL with no source to hand | Display, audio, Wi-Fi, input, and more | 81 |
| `/vendor` HALs and libraries | Mostly proprietary | Display composer, GPU (Mali), audio, Wi-Fi, Bluetooth, media codecs, keymint, TV input | 702 files, of which 279 are compiled binaries |
| Stock apps, if kept | Proprietary | HDMI input, keystone, factory menu | 5 here |
| Stock framework library | Proprietary | `com.softwinner.tv` | 1 jar, 4 native libraries |
| Google apps, if added | Proprietary | Play Store, Play services | Several |
| Paid or closed apps, if added | Proprietary | Whatever you chose | Your choice |

Other devices will differ. In total the first device's tree held 791 stock files, not counting the kernel, modules or apps.

### What this means for the user

| Topic | Effect |
|---|---|
| **Security** | Closed parts get no fixes unless the manufacturer ships them. New LineageOS builds don't patch them. The kernel here stays on whatever patch level it shipped with |
| **Trust** | You're trusting what you can't inspect. A device with this kind of firmware may include things the owner didn't ask for. Treat it as untrusted on your network, especially with root and open `adb`. Consider a separate network for it |
| **Longevity** | Blobs tie the device to the Android version they were built for. Moving to a newer Android gets harder with each step |
| **Fixing bugs** | Blobs can't be fixed, only worked around with shims, patched references, or leaving out a feature |
| **Licences** | Stock blobs and Google's apps have their own terms. **Sharing a finished image with others may not be allowed.** Building one for your own device is a different question from distributing it. Kernels and GPL modules also carry source obligations if you distribute them. This isn't legal advice: if you plan to publish images, check the terms, and consider publishing only the device tree, with blobs extracted by each user from their own device |
| **Support** | Official LineageOS has its own requirements, and this approach doesn't meet them. Call the result an unofficial build |

### Listing what you're reusing

Record it in `devices/<codename>/NOTES.md`, and show the user:

```bash
find vendor/<vendor>/<codename>/proprietary -type f | wc -l     # stock files in the build
ls device/<vendor>/<codename>/prebuilt/                         # kernel, DTB, DTBO
ls device/<vendor>/<codename>/prebuilt/modules | wc -l          # kernel modules
```

**Getting a kernel's source:** Linux is GPL. A manufacturer distributing a device must generally provide the kernel source if asked, though compliance varies. Asking is reasonable: email the manufacturer or chip vendor with the model and kernel version from `/proc/version`. Don't plan on it arriving.

## Alternatives for every closed part

Reusing a stock binary is one option, not the only one. **For each closed component, check all three, and choose per component, case by case:**

| Option | What it means | Usually best when |
|---|---|---|
| **Open source replacement** | AOSP's default, a LineageOS component, or a community project | It supports your hardware and the feature set you need |
| **Provided by the manufacturer** | A GPL source release, SDK or BSP, a newer firmware or driver package, a documented update tool, or the chip vendor's published driver | It's for your exact model or chip, and you can actually get it |
| **Reuse the stock binary** | Copy it from the device | Neither alternative exists, or the alternative loses a feature the user needs |

**One device can mix all three,** and most will. The first device did, for example:
- **Open source, from AOSP:** boot control HAL, composer service wrapper, audio HAL service, health HAL, `vndservicemanager`, Bluetooth stack, input and framework.
- **Stock, because the open option failed:** Wi-Fi service and library. AOSP's version only had a stub for this chip, then crashed with the vendor library.
- **Stock, as nothing open was found:** GPU libraries, display hardware layer, TV input, keymint, the kernel.

### Component by component

**This table is general knowledge and starting points, except where it mentions the first device.** Whether any entry works depends on the exact chip, and support changes. Check before you promise anything.

| Component | Open source options to check | Manufacturer options to check | Notes |
|---|---|---|---|
| Bootloader | Mainline U-Boot, and the community port for your chip | SDK or BSP source | **Very high risk: don't replace it without a hardware recovery route.** Needs board-specific DRAM setup |
| Secure firmware | Trusted Firmware-A, OP-TEE | BSP | Tied to the bootloader chain. On locked-down chips, only signed images run |
| Kernel | See "Choosing a kernel" below | GPL source release | |
| Wi-Fi and Bluetooth drivers | In-kernel drivers, community repositories for that chip | The chip vendor's published drivers, often on GitHub | Firmware files themselves usually stay closed. `linux-firmware` holds many |
| GPU | Mesa: Panfrost or Panthor for many Mali chips, Lima for older ones, Freedreno for Adreno. `drm_hwcomposer` and `minigbm` on the Android side | A newer vendor driver package | Open drivers need a matching kernel, normally DRM. Vendor display stacks can conflict |
| Display composer | `drm_hwcomposer` | BSP | Needs a DRM kernel driver. Features like keystone or HDMI-in overlays may be lost |
| Video decoding | Android's software codecs (`c2.android.*`), VLC or FFmpeg in apps, V4L2 codec2 with an open kernel driver | Vendor codecs | Software decoding may not manage 4K, or even 1080p, on weak chips |
| Audio | AOSP's default and `tinyalsa`-based HALs | BSP HAL | Usually needs device mixer paths |
| KeyMint, Gatekeeper | AOSP software implementations | Vendor TEE apps | Software ones give weaker security, and hardware attestation is lost, which can affect some apps |
| DRM (Widevine) | ClearKey only | Vendor | Generally has no open replacement. Streaming apps may fall back to lower quality or refuse to run |
| Sensors, IR, power | AOSP defaults, kernel input drivers, plain `.kl` files | BSP | Often simple to replace |
| Google apps | **microG**, F-Droid or Aurora Store for apps | None | Trades compatibility for openness. Android TV may have fewer options |
| Launcher, setup, settings | LineageOS and AOSP ones | | Usually the easy wins |
| Stock tools like keystone | Write a small open app that calls the HAL. Community tools | Manufacturer's app | The first device's keystone logic is a small HAL call, so an open replacement looks feasible, though the HAL remains closed |

### Where to look for manufacturer material

1. The product's support page: firmware, tools, source downloads.
2. **The GPL offer.** Look in the device's legal settings, or the manual. Then email the manufacturer with the model and `/proc/version`. Say which version you need.
3. The chip vendor's GitHub or developer site: SDKs, drivers.
4. Board makers using the same chip. They often publish BSPs. They may differ from your board, so treat these as a reference.
5. Community repositories and forums for the chip name, such as `linux-sunxi` for Allwinner.

**Before using anything:**
- It must be for your **exact model and revision** to flash. Anything else is reference only: wrong firmware can brick a device.
- Check its source, and whether you trust it: treat unofficial mirrors with suspicion.
- A newer vendor package may carry anti-rollback, or lock the bootloader. Read about it before flashing, and never let it update the bootloader without a plan.

### How to decide

For each component, ask:
1. Is a feature the user listed in the intake form dependent on it?
2. Is an open or manufacturer option available for this exact chip? Have you found evidence it works, not only that it exists?
3. What would be lost? Performance, DRM, features.
4. How much work and risk is it? Replacing an app is cheap, while replacing a GPU stack can take weeks.

**Sensible order:** get the device working first, using whatever's fastest. Then replace components one at a time, with a test each time, starting with the cheapest: apps, then simple HALs, then drivers, and only then the kernel, GPU stack or bootloader. Replacing several at once means that when something breaks, you can't tell which caused it.

**Record each decision** in `devices/<codename>/NOTES.md`:
```
Component | Choice (open / manufacturer / stock) | Why | What was checked | Works?
```
Tell the user what stayed closed, and what you tried. If you haven't checked for an alternative, say so.

## Choosing a kernel

**Use a LineageOS, other open, or manufacturer-provided kernel source when one suitably fits the device.** It gives you source, and the ability to fix problems. Reuse the stock kernel when none does.

### The options

| Option | When it fits | You gain | The catch |
|---|---|---|---|
| **A. LineageOS kernel for your SoC** | A repository exists for your chip or a close relative, at a compatible version | Source, maintained patches, a community that has solved similar problems | Vendor drivers may not match your board. Stock `.ko` files won't load unless they match |
| **B. Manufacturer or SoC vendor's source** | The GPL release matches your device | The right drivers | Often outdated, incomplete or hard to get |
| **C. Android common kernel (GKI)** | Stock is GKI-based, on Android 12 or later | Google's fixes, with stock vendor modules possibly staying compatible | Modules must match the KMI of the exact branch. Not every "GKI" vendor kernel keeps to it |
| **D. Mainline Linux** | A strong community port exists for the chip | Fully open | TV-box video, GPU and HDMI-in support is often missing. Android on mainline is a big project in itself |
| **E. Stock kernel, prebuilt** | None of the above fit (**what the first device used**) | Works at once, with all drivers, and is by far the fastest | Binary, no fixes, and the build warns it's deprecated |

### How to check for A

```bash
gh api 'search/repositories?q=org:LineageOS+android_kernel_<vendor>+in:name&per_page=50' --jq '.items[].name'
```
Also browse <https://github.com/LineageOS> for `android_kernel_<vendor>_<soc>` and `android_kernel_<vendor>_<version>`. LineageOS's device wiki shows which devices with your chip are supported: their device trees show the kernel they use.

**A search by name isn't a final answer.** Results when this was written, by name only: Amlogic 40, Qualcomm 28, MediaTek 3, Allwinner 0, Rockchip 0. Repositories named differently are missed, and these numbers change. Also look for community projects for your chip: for example, projects exist for chips related to the first device.

### Questions that decide it

1. **Does a kernel exist for this exact SoC family, at a version that suits the Android branch?** Check `/proc/version`. Android 14 stock with 5.15 needs a kernel its vendor blobs can work with.
2. **Are the closed vendor parts tied to the stock kernel?** They often are. The GPU's userspace driver must match its kernel driver (Mali's are versioned together), and the same goes for display, video decoding, and HDMI input.
3. **Does a module have to be loaded, and could it work?** A stock `.ko` won't load on a kernel with a different `vermagic` or incompatible symbols, without a matching rebuild. Without source for it, the feature is lost.
4. **Which device features depend on it?** Keystone, HDMI input and autofocus usually rely on vendor kernel drivers.
5. **Is the architecture right?** The first device runs a 32-bit kernel on a 64-bit chip, and its bootloader had a specific check for this.

### Trying a different kernel safely

**The kernel is the riskiest thing to change, after the bootloader.** On a `vendor_boot` device, **recovery and fastbootd use the same kernel as Android**. A bad kernel takes out your fallback along with the OS.

Before you try:
1. Get the ROM working on the stock kernel first. Then one change at a time tells you what caused a failure.
2. Keep the working `boot` image, and prove a route that doesn't depend on the kernel: `docs/03-RECOVERY-ROUTES.md`.
3. Test with `fastboot boot boot-new.img` if your device supports it: nothing is written.
4. Have UART ready. You won't have `adb`, and kernel failures happen early.
5. Compare the configuration with stock's: `adb shell zcat /proc/config.gz`, which also gives you a starting defconfig.
6. Compile against the same device tree, or check that stock's DTB works with it. Expect to build modules from source for what you can.

In `BoardConfig.mk`, replacing the prebuilt:
```make
# TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
TARGET_KERNEL_SOURCE := kernel/<vendor>/<codename>
TARGET_KERNEL_CONFIG := <codename>_defconfig
BOARD_KERNEL_IMAGE_NAME := zImage       # Image or Image.gz on 64-bit kernels. Match stock's
```
`reference/hermes/device-tree/BoardConfig.mk` has this block, commented out. **It was never built on the first device**, so treat this as a starting point.

**Time:** a kernel swap isn't in the toolkit's time estimates. Expect days to weeks, depending on how well the source matches, and it may not succeed.

### A sensible default

| Situation | Suggestion |
|---|---|
| User wants a working device soon, on an unsupported chip | E, stock kernel. State the trade-offs clearly |
| LineageOS has a kernel for this exact chip | A. Check the features still work |
| User cares most about open source or security | A, B or D. Warn that features may be lost, and that closed parts remain anyway unless the vendor stack is replaced too |
| Device will sit on a network long-term | Prefer A or B. If it's E, isolate it on the network |

**Changing the kernel doesn't make the device open source.** The vendor blobs, TEE and bootloader stay closed unless they're also replaced. See "Alternatives for every closed part". Say that plainly.
