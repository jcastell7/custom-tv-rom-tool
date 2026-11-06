# Files removed from this example

To keep this repository free software, stock files that belonged in this tree aren't included. So **this example doesn't build as it stands**. Use it to read how things were done.

| Missing | What it is | Where to get it, on your own device |
|---|---|---|
| `prebuilt/` | Kernel, DTB, DTBO, kernel modules | Your backup: `boot`, `dtbo`, `vendor_boot`, `vendor_dlkm` |
| `manifest.xml`, `compatibility_matrix.xml`, `vintf/` | VINTF | Stock `/vendor/etc/vintf/` |
| `rootdir/etc/fstab.<hardware>` | Partition table for init | Stock `vendor_boot` ramdisk, or `/vendor/etc/` |
| `recovery/root/` | Recovery init file and modules | Stock `vendor_boot` ramdisk. `templates/fallback/recovery-auto-fastbootd.rc.snippet` holds the addition made to it |
| `sepolicy/reference/` | Stock SELinux policy, for reference | Stock `/vendor/etc/selinux/` |
| `hermes_defconfig` | Kernel configuration | `adb shell zcat /proc/config.gz` |
| `keylayout/` | Remote key layout | Stock `/vendor/usr/keylayout/`. Replace any key names LineageOS doesn't define: see `docs/05-DEBUG-CATALOG.md` |
| `vendor/<vendor>/<codename>/` | All vendor blobs | Stock `/vendor`, with `tools/30-extract-stock.sh` |
