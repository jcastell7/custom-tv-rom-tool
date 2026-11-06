# Setting up a new computer

> **⚠️ WARNING: this process could very well fully and permanently brick your device.** Only use it on a device you own and can afford to lose. It's provided as is, with no warranty, and **we accept no responsibility** for how it's used or what happens. Not affiliated with LineageOS in any way: we just use and recommend their work, so [please donate to them](https://lineageos.org/about/) when you can. Read [`../DISCLAIMER.md`](../DISCLAIMER.md).

For any Linux distribution. **Start with the host check.** It tells you what's missing, and it changes nothing:

```bash
tools/00-check-host.sh --tree /path/to/lineage-21.0       # everything
tools/00-check-host.sh --purpose device                   # only back up and flash; no tree needed
```

`tools/40-build.sh` and `tools/05-sync-lineage.sh` run it themselves, and stop on any FAIL.

**What was tested:** everything here ran on Ubuntu 22.04. Package names for other distributions are general knowledge, and untested: if one is wrong, search your distribution's packages for the tool name, and correct this page.

## Which computer you need

Some jobs need very little. You can back up and flash from a modest laptop, and build elsewhere.

| Job | Minimum | Good |
|---|---|---|
| Back up and flash a device | Any Linux PC, USB 2 port, free disk the size of the device's storage | USB port directly on the PC, not through a hub |
| Reverse engineering | The above, plus 8 GB RAM | 16 GB |
| Build LineageOS | See below | See below |

## Hardware for building

**Measured on the first project,** which had a 12-thread CPU, 31 GB RAM, no swap, and a Kingston NV1 NVMe SSD:

| Item | Measured |
|---|---|
| Source tree | 90 GB |
| Git data (`.repo`) | 68 GB |
| Build output (`out`) | 74 GB |
| **Total for one device** | **232 GB** |
| Incremental rebuild and new images | Typically 1.5 minutes, 4 minutes at worst |
| Download | Under about 1 hour on that connection. Often several hours elsewhere |
| First complete compile | About 5.5 hours, estimated. See [`01-FAST-PATH.md`](01-FAST-PATH.md#how-long-it-takes) |

| Part | Minimum | Recommended | Why |
|---|---|---|---|
| CPU | x86_64, 4 cores | 8+ cores, 12+ threads | Android's toolchains only ship for x86_64 Linux. ARM won't work directly |
| RAM + swap | 16 GB total | 32 GB RAM | Soong and linking use a lot. Builds die from memory shortage with little explanation. If you're short, add swap, and limit jobs with `m -j6` |
| Disk space | 350 GB free | 500 GB or more | 232 GB measured, plus room to grow, plus ccache, plus device backups, which can be several GB each |
| Disk type | SATA SSD | NVMe SSD | A spinning disk works, but many times slower |
| Internet | Stable broadband | Fast and unmetered | About 160 GB download. `repo sync` resumes |

**Hardware for the device work:**

| Item | Needed? | Notes |
|---|---|---|
| USB cable | Yes | For the device's OTG port. TV boxes sometimes need USB-A to USB-A. **Must carry data.** |
| USB 2 stick, FAT32 | Strongly recommended | For bootloader updaters and stick rescue. Some bootloaders won't see USB 3 sticks |
| USB-UART adapter, **3.3 V** | Strongly recommended | CP2102, FT232, or similar. It's the best debugging tool you have. **Never use a 5 V adapter or connect VCC.** Some boards use 1.8 V: measure first |
| Multimeter | Helpful | To find UART pads and check voltage |
| Soldering iron | If UART needs wires | Clips sometimes work |
| Second disk | Yes | For the second backup copy |

## The drive for LineageOS

**Prerequisite:** an empty directory on a suitable drive. The host check verifies each of these:

| Requirement | Why | If it fails |
|---|---|---|
| Local drive | Network storage is too slow, and it breaks permissions | Use a local or fast USB SSD |
| ext4 or xfs (btrfs and f2fs should work, untested) | Android needs case sensitivity, symlinks and Unix permissions | Format a partition as ext4 |
| **Not** NTFS, exFAT, FAT, or tmpfs | They lack those features, or don't survive a reboot | This is a common failure on dual-boot PCs and external drives |
| Mounted with `exec` | The build runs its own tools from the tree | See below |
| Writable by your user | Don't build as root | `sudo chown -R $USER: /path` |
| 350 GB free for a new tree | See measurements above. 120 GB for a synced tree that hasn't been built; 30 GB for one already built | Free space, or use a different drive |

### Preparing a drive

**This erases the partition. Check the device name with `lsblk` first, and confirm with the user. Don't guess.**

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,MODEL
sudo mkfs.ext4 -L lineageos-build /dev/<PARTITION>
sudo mkdir -p /mnt/lineageos-build
sudo mount /dev/<PARTITION> /mnt/lineageos-build
sudo chown -R "$USER": /mnt/lineageos-build
```

To mount it at every boot, add this to `/etc/fstab`, using the UUID from `blkid`:
```
UUID=<uuid>  /mnt/lineageos-build  ext4  defaults,noatime  0  2
```

**Desktop auto-mounts:** these commonly use `nosuid,nodev`, which is fine (the first project's drive did), but some use `noexec`, which isn't. To fix it now: `sudo mount -o remount,exec /path`, then use the `/etc/fstab` line above to make that permanent.

### Tell the tools where it is

```bash
export LINEAGE_TREE=/mnt/lineageos-build/lineage-21.0     # add to ~/.bashrc or ~/.zshrc
```

Paths like `/path/to/lineageos-build` in these documents are from the first computer. Replace them with yours.

### Moving an existing tree

Don't re-download if another computer has a tree. Copy it while preserving everything:

```bash
rsync -aHAX --info=progress2 old:/path/lineage-21.0/ /mnt/lineageos-build/lineage-21.0/
```
Leave out `out/` to save time and space: `--exclude=/out`. Then run the host check. `git-repo` keeps absolute paths in a few places, so if something complains, run `repo sync -l` inside the new location.

## Installing the base tools

### Debian, Ubuntu, Mint (tested on Ubuntu 22.04)
```bash
sudo apt-get update
sudo apt-get install -y bc bison build-essential ccache curl flex g++-multilib gcc-multilib git git-lfs gnupg gperf \
  lib32ncurses-dev lib32z1-dev libelf-dev liblz4-tool libncurses-dev libsdl2-dev libssl-dev libxml2 libxml2-utils lzop \
  pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev python3 unzip e2fsprogs binutils dosfstools parted \
  adb fastboot picocom device-tree-compiler lz4 erofs-utils android-sdk-libsparse-utils
```
On Ubuntu 22.04 the first project used `lib32ncurses5-dev`, and `python-is-python3`. If a package isn't found on your release, try the name without its version number.

### Fedora, RHEL-style (untested)
```bash
sudo dnf install -y @development-tools gcc-c++ glibc-devel.i686 libstdc++.i686 ncurses-devel ncurses-compat-libs zlib-devel.i686 \
  bc bison ccache curl flex git git-lfs gnupg gperf libxml2 libxslt lz4 lzop openssl-devel python3 rsync squashfs-tools zip unzip \
  e2fsprogs binutils dosfstools parted picocom dtc erofs-utils android-tools
```

### Arch, Manjaro (untested)
```bash
sudo pacman -S --needed base-devel multilib-devel bc bison ccache curl flex git git-lfs gnupg gperf libxml2 libxslt lz4 lzop \
  ncurses openssl python rsync squashfs-tools zip unzip e2fsprogs binutils dosfstools parted picocom dtc erofs-utils android-tools
```
`multilib` must be enabled in `/etc/pacman.conf`. `ncurses5-compat-libs` is in the AUR, if a build asks for `libncurses.so.5`.

### openSUSE (untested)
```bash
sudo zypper install -t pattern devel_basis
sudo zypper install bc bison ccache curl flex gcc-c++ gcc-32bit git git-lfs gpg2 gperf libxml2-tools libxslt-tools lz4 lzop \
  ncurses-devel libopenssl-devel python3 rsync squashfs zip unzip e2fsprogs binutils dosfstools parted picocom dtc erofs-utils android-tools
```

### Any distribution: things to get separately

**`repo`:**
```bash
mkdir -p ~/.local/bin
curl -o ~/.local/bin/repo https://storage.googleapis.com/git-repo-downloads/repo
chmod +x ~/.local/bin/repo
export PATH="$HOME/.local/bin:$PATH"    # add to your shell's rc file
```

**Current `adb` and `fastboot`:** distribution packages are sometimes old. Old `fastboot` mishandles fastbootd and dynamic partitions. Google's are at <https://developer.android.com/tools/releases/platform-tools>. Unzip them, and put the folder first on `PATH`. The first project used fastboot 37.

**Git setup:**
```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git lfs install --skip-repo
```

**Python 3.8 or newer.** The toolkit's scripts use only the standard library, with nothing to install. Android's build uses its own prebuilt Python for most things, but needs `python3` on `PATH`.

**Java:** Android's build ships its own JDK. You only need a system one for `jadx` and Ghidra.

### USB and serial access

**udev rules, so `adb` and `fastboot` work without sudo.** Some distributions provide `android-sdk-platform-tools-common` or `android-udev`. Otherwise, make `/etc/udev/rules.d/51-android.rules` containing:
```
# Google (fastbootd, adb)
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0660", GROUP="plugdev", TAG+="uaccess"
# Allwinner FEL. Add your SoC vendor's ID: see lsusb
SUBSYSTEM=="usb", ATTR{idVendor}=="1f3a", MODE="0660", GROUP="plugdev", TAG+="uaccess"
```
Then:
```bash
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo groupadd -f plugdev; sudo usermod -aG plugdev "$USER"
```
**Serial port:** `sudo usermod -aG dialout "$USER"`, or `uucp` on Arch. **Group changes need a new login.**

**Agents:** you often can't run `sudo` or get a new login. On the first project, the user started `picocom` themselves with a log file, and I read the log:
```bash
picocom -b 115200 --logfile ~/uart.log /dev/ttyUSB0      # the user runs this; exit with Ctrl-A Ctrl-X
```
Only one program can hold the port, and `fuser /dev/ttyUSB0` shows which. **Read `docs/00-SAFETY.md` before you write to a serial port.**

**Brltty conflict:** on some distributions, `brltty` grabs CH340 and CP210x adapters, so `/dev/ttyUSB0` disappears at once. If `dmesg` shows that, remove `brltty`.

## LineageOS source

```bash
tools/05-sync-lineage.sh "$LINEAGE_TREE" lineage-21.0
```

It checks the location first, then runs `repo init` and `repo sync`. Re-run it to resume. By hand:

```bash
mkdir -p "$LINEAGE_TREE" && cd "$LINEAGE_TREE"
repo init -u https://github.com/LineageOS/android.git -b lineage-21.0 --git-lfs --no-clone-bundle
repo sync -c -j"$(nproc)" --no-clone-bundle --no-tags --optimized-fetch --prune
```

**Choosing a branch.** Match the device's stock Android version:

| Android | Branch |
|---|---|
| 13 | `lineage-20.0` |
| 14 | `lineage-21.0` (used here; the only one tested) |
| 15 | `lineage-22.x` (general knowledge: check the available branches) |

One tree serves many devices, so don't sync again for a new device. Different Android versions need separate trees.

**`device/google/atv`:** needed for TV builds. Check with the host check. If it's missing, add it through `.repo/local_manifests/`. Example: `reference/hermes/device-tree/` and `reference/hermes/docs/08-lineageos-build-setup.md`.

**ccache, optional:** speeds rebuilds after a clean. It doesn't help typical increments much: on the first project its directory stayed nearly empty.
```bash
export USE_CCACHE=1 CCACHE_EXEC=$(command -v ccache) CCACHE_DIR=/mnt/lineageos-build/ccache
ccache -M 50G
```

**Limited RAM:** add swap.
```bash
sudo fallocate -l 32G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
```

**Git LFS errors in the sync:** run `git lfs install --skip-repo`, then `repo sync` again. `repo forall -c 'git lfs pull'` fetches any that were skipped.

## Third-party tools

### Comes with the Android tree, after the first build

No installation. **They exist only after a first build**, so `50-gate.py` and `80-apps.py` need that build first. Add `export PATH="$LINEAGE_TREE/out/host/linux-x86/bin:$PATH"` to use them by hand.

| Tool | Path | Used for |
|---|---|---|
| `aapt2` | `out/host/linux-x86/bin/` | Reading APK manifests and permissions |
| `apksigner` | Same | Checking signing certificates |
| `dexdump` | Same | Disassembling framework and app code |
| `checkvintf`, `assemble_vintf` | Same | VINTF checks |
| `avbtool` | Same, or `external/avb/avbtool.py` | AVB footers and vbmeta info |
| `lpunpack`, `lpmake` | Same | `super`. The toolkit also has `tools/bin/lpunpack.py` |
| `unpack_bootimg` | Same | Boot images. Also `tools/bin/unpack_bootimg.py` |
| `simg2img` | Same | Sparse images, if your distribution lacks it |
| `llvm-objdump` | `prebuilts/clang/host/linux-x86/*/bin/` | BPF scanning |
| `patchelf` | `prebuilts/extract-tools/linux-x86/bin/patchelf-*` | Blob fix-ups. Not on `PATH` |

### Needed for the core process

| Tool | Package name | Used by | Check |
|---|---|---|---|
| `adb`, `fastboot` | Above | Everything | `fastboot --version` |
| `debugfs` | `e2fsprogs` | `30-extract-stock.sh` | `debugfs -V` |
| `fsck.erofs` | `erofs-utils` | EROFS partitions, like `vendor_dlkm` here | `fsck.erofs --help`. Must support `--extract` |
| `readelf` | `binutils` | Gate | `readelf --version` |
| `unzip`, `zipinfo` | `unzip` | Apps | |
| `picocom` | `picocom` | UART | |
| `mkfs.vfat`, `parted` | `dosfstools`, `parted` | Rescue sticks | |
| `simg2img` | `android-sdk-libsparse-utils` | Sparse `super` | |

**Making a rescue stick.** FAT32 on MBR. **This erases the stick. Confirm the device name with `lsblk` and with the user.**
```bash
sudo parted -s /dev/<STICK> mklabel msdos mkpart primary fat32 1MiB 100%
sudo mkfs.vfat -F 32 /dev/<STICK>1
```

### For specific jobs

| Tool | When | How to install | Notes |
|---|---|---|---|
| `gh` | Finding releases on GitHub | Package `gh`; `gh auth login` | `curl` works for public downloads |
| `dtc` | Reading device trees | `device-tree-compiler` or `dtc` | `dtc -I dtb -O dts file.dtb` |
| `lz4` | Ramdisks | `lz4` | |
| **capstone** | Disassembling a bootloader | `python3 -m venv ~/.cache/re && ~/.cache/re/bin/pip install capstone` | The first project used 5.0.9. Keep it in a venv. `reference/hermes/uboot-re/ua.py` shows the use |
| **sunxi-tools** | Allwinner FEL | Package `sunxi-tools`, or build from <https://github.com/linux-sunxi/sunxi-tools>, needing `libusb-1.0-0-dev`, `libfdt-dev`, `zlib1g-dev` | **Didn't support H723.** Check your chip with `sunxi-fel ver` |
| **jadx** | Reading APK code | Release from <https://github.com/skylot/jadx>. Needs Java 11+ | First project used 1.4.7 |
| **apktool** | APK manifests, resources | <https://apktool.org> | First project used 3.0.3 |
| **Ghidra** | Deep native analysis | <https://ghidra-sre.org>, with JDK 21 | First project used 12.1.4. Install it under `$HOME` |
| **REA** (`rea-agents`) | Firmware extraction, agent-driven analysis | `npx rea-agents@6.8.0`, needs Node 24. See the project's `tooling/README.md` | Optional. Requires Ghidra, jadx and apktool paths set through environment variables. Refuses output directories it doesn't own |
| **unblob** | Carving unknown firmware | `pipx install unblob` | Optional extractors need `lz4`, `simg2img`, `sasquatch`, `erofs`, `unar` |
| **PhoenixSuit** etc. | SoC vendor flashing | Windows, from the SoC vendor | Never used here |

### Apps, downloaded rather than installed on the PC

| Item | Source | How it's checked |
|---|---|---|
| Google apps | <https://github.com/MindTheGapps> releases: the repository matching Android version, ABI and `ATV` | Compare any published checksum. Record the hash |
| F-Droid and its apps | `tools/81-fdroid-fetch.py`, or <https://f-droid.org> | Hash from the F-Droid index, certificate with `apksigner` |
| Magisk | <https://github.com/topjohnwu/Magisk/releases> | Record the hash |

## Moving to another computer: what to copy

| What | Size here | Why |
|---|---|---|
| **Device backups** | Several GB each | **Can't be recreated if the device changes. Copy them first** |
| This toolkit | 4 MB | |
| Your device tree and vendor blobs | Under 2 GB | Also keep them in a private repository |
| Patches you applied to the Android tree | Small | Re-sync loses tree changes. Save them with `git diff`, in `templates/patches/` or `devices/<codename>/` |
| Downloaded apps and GApps | Under 1 GB | Saves re-downloading and re-checking |
| Android tree | 158 GB without `out` | Optional. You can sync again |
| `~/.android/adbkey` | Small | Optional. Without it, devices ask for authorization again |

**Device backups and blobs are private.** They hold MAC addresses and keys. Encrypt them on anything portable, and don't push them to a public repository.

## Then verify

```bash
tools/00-check-host.sh --tree "$LINEAGE_TREE"     # should report 0 FAIL
adb devices                                       # with a device connected
tools/40-build.sh "$LINEAGE_TREE" lineage_<codename>-ap2a-userdebug      # once a device tree is in place
```

## When something goes wrong on the host

| Symptom | Cause | Fix |
|---|---|---|
| `adb devices` shows `no permissions` | udev rules | Above, then replug |
| `adb` shows `unauthorized` | Prompt on the device not accepted | Accept it. Revoke authorizations in developer options if stuck |
| `adb` keeps disconnecting | Bad cable or hub | Use a short cable, directly on the PC |
| `fastboot` shows nothing, `lsusb` shows the device | Permissions | Try `sudo fastboot devices` to confirm, then fix udev |
| Nothing in `lsusb` | Cable, port or device mode | Data cable, OTG port. See `09-BRICK-RECOVERY.md` |
| `/dev/ttyUSB0` missing | Adapter or `brltty` | `dmesg -w`, replug |
| USB hub stops responding | A tight loop reopening the port | See `00-SAFETY.md`. Replug the hub, or reboot |
| `/dev/ttyUSB0` is a regular file | Written with `>` while the adapter was unplugged | `sudo rm /dev/ttyUSB0`, then replug |
| `Killed`, `ninja: build stopped`, nothing else | Out of memory | Check `dmesg` for OOM. Add swap, or use `m -j6` |
| `No space left on device` | Disk full | `df -h`. `m installclean` removes installed files, and a full `rm -rf out` frees the most |
| `Too many open files` | Limit | `ulimit -n 65536` |
| `repo: command not found` | `PATH` | `export PATH="$HOME/.local/bin:$PATH"` |
| `repo sync` fails partway | Network | Run it again, with fewer jobs: `-j4` |
| `Permission denied` running build tools | `noexec` mount | `sudo mount -o remount,exec` |
| Case or symlink errors in the sync | Wrong filesystem | Move to ext4 |
| `libncurses.so.5` not found | Older prebuilt | Install the compatibility package |
| `python: command not found` | No `python` alias | `python-is-python3` on Debian, or similar |
| `grep` errors in scripts, or strange flags | `grep` aliased to `ugrep`, as on the first computer | `command grep` in your own commands |
| zsh `no matches found` | Unmatched glob | Quote it, or run in `bash` |
