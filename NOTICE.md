# Licensing

Copyright (C) 2026 custom-tv-rom-tool contributors.

This program is free software: you can redistribute it and/or modify it under the terms of the **GNU General Public License, version 3** ([`LICENSE`](LICENSE)), as published by the Free Software Foundation. It's distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the license for details.

Everything in this repository is under GPL-3.0, except the files below, which keep their own licenses. All of them can be used alongside GPL-3.0 code.

| Files | License | Origin |
|---|---|---|
| `tools/bin/lpunpack.py` | LGPL-3.0 ([text](LICENSES/LGPL-3.0.txt), which builds on the GPL-3.0 in [`LICENSE`](LICENSE)) | Unmodified copy of <https://github.com/unix3dgforce/lpunpack> |
| `tools/bin/unpack_bootimg.py` | Apache-2.0 ([text](LICENSES/Apache-2.0.txt)) | The Android Open Source Project. Keeps its own header |
| `templates/patches/*.patch` | Apache-2.0, like the files they change | Changes to Android Open Source Project and LineageOS code |
| `reference/hermes/device-tree/` files that follow AOSP or LineageOS templates, such as `extract-files.sh` and `setup-makefiles.sh`, where they carry their own notice | That notice's terms | LineageOS's device-tree conventions |

## What isn't here, and isn't covered

**No manufacturer firmware, stock binaries or stock configuration files are included.** These stay with their owners, and you get them from your own device:
- Stock kernel, kernel modules, HALs, libraries, apps, SELinux policy, fstab, recovery init files and VINTF manifests.
- Google's apps, Magisk, F-Droid and other third-party apps. The tools download or install these separately, under their own terms.

The tools and notes refer to these files and describe how they behave. **The license on this toolkit gives you no rights to them.**

## What GPL-3.0 means here

- **You can use, change and share this toolkit freely.** If you distribute it, or a changed version, you must do so under GPL-3.0, with its source.
- **Just running the tools puts no license on your output.** A ROM isn't GPL because these tools helped build it. The GPL doesn't normally extend to a program's output.
- **Code you copy into your own project is different.** Copying from `templates/` (the companion app, shim, boot scripts) or `reference/` into a device tree makes that copy GPL-3.0 if you distribute it. Patches in `templates/patches/` stay Apache-2.0.
- This isn't legal advice.

## This toolkit being free doesn't make a ROM free

A ROM built with this toolkit normally includes closed-source binaries. Those keep their own terms, whatever this toolkit's license says, and a finished image may not be legal to share. See [`docs/12-KERNEL-AND-CLOSED-SOURCE.md`](docs/12-KERNEL-AND-CLOSED-SOURCE.md) and [`DISCLAIMER.md`](DISCLAIMER.md).

The notes under `reference/hermes/` describe reverse engineering of one device's bootloader for the purpose of repair and interoperability. Laws on this vary by country: check yours.

Trademarks belong to their owners. This project isn't affiliated with any of them.
