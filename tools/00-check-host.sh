#!/usr/bin/env bash
# READ-ONLY host check. Run it first on any computer. Works on any Linux distribution. It changes nothing except a small
# temporary test directory in the location being checked, which it removes.
#
# Usage: 00-check-host.sh [--tree DIR] [--purpose device|build|all]
#   --tree DIR   where the LineageOS tree is or will go. Default: $LINEAGE_TREE. Checks the drive and, if it exists, the tree.
#   --purpose    device: only what's needed to back up and flash. build: also needs a tree. all: default.
# Exit status: 0 no problems, 1 a FAIL item needs fixing. See docs/10-SETUP-NEW-COMPUTER.md for how to fix each item.
set -uo pipefail
TREE=${LINEAGE_TREE:-}; PURPOSE=all
while [ $# -gt 0 ]; do case $1 in
  --tree) TREE=$2; shift ;; --purpose) PURPOSE=$2; shift ;;
  -h|--help) sed -n 2,8p "$0"; exit 0 ;;
  *) echo "unknown option $1"; exit 2 ;; esac; shift; done

fails=0; warns=0
ok()   { printf '  \033[32mOK  \033[0m %s\n' "$*"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$*"; warns=$((warns+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fails=$((fails+1)); }
has()  { command -v "$1" >/dev/null 2>&1; }

# Measured on the first project: source 90 GB + git data 68 GB + output 74 GB = 232 GB, before ccache and any second device.
NEED_NEW_GB=350      # free space to sync and build from nothing
NEED_BUILD_GB=120    # free space in an existing synced tree with no output yet
NEED_INCREMENT_GB=30 # free space in a tree that has already been built
NEED_BACKUP_GB=32    # free space for a device backup, without userdata; check the device's own size too

echo "== Computer"
os=$(uname -s); arch=$(uname -m)
[ "$os" = Linux ] && ok "Linux: $( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}" ), kernel $(uname -r)" || bad "$os: Android builds need Linux. WSL2 and VMs may work but weren't tested."
[ "$arch" = x86_64 ] && ok "x86_64" || bad "$arch: Android's prebuilt toolchains need x86_64."
if [ "$PURPOSE" != device ]; then
  cpus=$(nproc)
  [ "$cpus" -ge 8 ] && ok "$cpus CPU threads" || warn "$cpus CPU threads: this works, but a first build can take a day. 8 or more is much better."
  ram=$(awk '/MemTotal/{print int($2/1048576+0.5)}' /proc/meminfo); swp=$(awk '/SwapTotal/{print int($2/1048576+0.5)}' /proc/meminfo)
  t=$((ram+swp))
  if [ "$t" -lt 16 ]; then bad "RAM ${ram} GB + swap ${swp} GB: under 16 GB in total will likely run out of memory. Add swap (docs/10)."
  elif [ "$t" -lt 30 ]; then warn "RAM ${ram} GB + swap ${swp} GB: works, but limit parallel jobs if builds get killed. 32 GB is better."
  else ok "RAM ${ram} GB + swap ${swp} GB"; fi
  [ "$(ulimit -n)" -ge 4096 ] 2>/dev/null || [ "$(ulimit -n)" = unlimited ] && ok "open file limit $(ulimit -n)" || warn "open file limit $(ulimit -n): run 'ulimit -n 4096' or more before building."
fi

check_drive() { # dir, gb needed
  local d=$1 need=$2 p=$1
  while [ ! -e "$p" ]; do p=$(dirname "$p"); done
  [ -w "$p" ] || { bad "$p isn't writable by $(id -un). Fix ownership before you put a tree there."; return; }
  local fs mnt opts src free_gb
  fs=$(findmnt -no FSTYPE -T "$p" 2>/dev/null | head -1); mnt=$(findmnt -no TARGET -T "$p" 2>/dev/null | head -1)
  opts=$(findmnt -no OPTIONS -T "$p" 2>/dev/null | head -1); src=$(findmnt -no SOURCE -T "$p" 2>/dev/null | head -1)
  free_gb=$(df -BG --output=avail "$p" | tail -1 | tr -dc 0-9)
  echo "   location $d, on $src ($fs), mounted at $mnt"
  case "$fs" in
    ext4|xfs) ok "filesystem $fs" ;;
    btrfs|f2fs|bcachefs) ok "filesystem $fs. Works, but wasn't tested here. Disable btrfs compression and snapshots on the tree, for speed." ;;
    zfs) warn "filesystem zfs: not tested here. Make sure it's case-sensitive and has POSIX ACLs." ;;
    ntfs|ntfs3|fuseblk|fuse*|vfat|exfat|msdos|9p|nfs*|cifs|smb*|overlay|tmpfs|ramfs)
      bad "filesystem $fs can't hold an Android tree: it lacks case sensitivity or Unix permissions and symlinks, is too slow, or doesn't survive a reboot. Use ext4 on a local drive." ;;
    *) warn "filesystem '$fs' isn't known here. Check it's local, case-sensitive and supports symlinks." ;;
  esac
  case ",$opts," in *,noexec,*) bad "mounted noexec: the build can't run its own tools here. Remount with exec (docs/10). Removable drives often mount this way." ;; esac
  case ",$opts," in *,ro,*) bad "mounted read-only." ;; esac
  case ",$opts," in *,nosuid,*) ok "nosuid is set, which is fine for building" ;; esac
  # Prove the behaviour, because the filesystem name doesn't tell everything.
  local t; t=$(mktemp -d "$p/.hostcheck.XXXXXX" 2>/dev/null) || { bad "can't create files in $p"; return; }
  : > "$t/CaseTest"; [ -e "$t/casetest" ] && bad "not case-sensitive: Android has files differing only by case." || ok "case-sensitive"
  ln -s CaseTest "$t/link" 2>/dev/null && [ -L "$t/link" ] && ok "symlinks work" || bad "symlinks don't work"
  printf '#!/bin/sh\nexit 0\n' > "$t/x"; chmod +x "$t/x"; "$t/x" 2>/dev/null && ok "files can run here" || bad "files can't run here (noexec)"
  rm -rf "$t"
  local dev rota
  dev=$(lsblk -no PKNAME "$src" 2>/dev/null | head -1); [ -n "$dev" ] || dev=$(basename "$src")
  rota=$(cat "/sys/block/$dev/queue/rotational" 2>/dev/null)
  case "$rota" in 0) ok "solid-state drive ($dev)" ;; 1) warn "spinning disk ($dev): this works, but builds are many times slower. Use an SSD if you can." ;; *) warn "couldn't tell the drive type for $src" ;; esac
  local bus; bus=$(lsblk -dno TRAN "/dev/$dev" 2>/dev/null); [ "$bus" = usb ] && warn "$dev is on USB: use a fast SSD, and don't unplug it during a build."
  [ "$free_gb" -ge "$need" ] && ok "${free_gb} GB free, need ${need} GB" || bad "${free_gb} GB free, need ${need} GB"
}

if [ "$PURPOSE" != device ]; then
  echo "== LineageOS location"
  if [ -z "$TREE" ]; then
    bad "no location given. Pass --tree DIR or set LINEAGE_TREE."
  else
    case "$TREE" in /*) ;; *) TREE=$(pwd)/$TREE ;; esac
    if [ -d "$TREE/.repo" ] && [ -f "$TREE/build/envsetup.sh" ]; then
      [ -d "$TREE/out/host" ] && need=$NEED_INCREMENT_GB || need=$NEED_BUILD_GB
      check_drive "$TREE" "$need"
      echo "== LineageOS tree at $TREE"
      branch=$(git -C "$TREE/.repo/manifests" for-each-ref --format='%(upstream:short)' 2>/dev/null | grep -m1 -o 'lineage-[0-9.]*')
      [ -n "$branch" ] || branch=$(sed -n 's/.*merge = refs\/heads\///p' "$TREE/.repo/manifests.git/config" 2>/dev/null | head -1)
      case "$branch" in lineage-*) ok "branch $branch. Check it matches the device's Android version (21.0 = Android 14)" ;; *) warn "couldn't read the branch ('$branch')" ;; esac
      missing=0; for d in build/make frameworks/base system/core external/boringssl vendor/lineage packages/modules/Connectivity; do [ -d "$TREE/$d" ] || { bad "missing $d: the sync looks incomplete. Re-run tools/05-sync-lineage.sh."; missing=1; }; done
      [ "$missing" = 0 ] && ok "main source directories present"
      [ -d "$TREE/device/google/atv" ] && ok "device/google/atv present (Android TV base)" || bad "device/google/atv missing: needed for TV builds. See docs/10."
      if [ -e "$TREE/out/host/linux-x86/bin/aapt2" ]; then ok "host tools built (aapt2, checkvintf and others)"; else warn "no built host tools yet. 50-gate.py and 80-apps.py need them after the first build."; fi
      n=$(find "$TREE/device" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | grep -vE '/(google|generic|linaro|lineage|sample|amlogic)/' | sed "s#$TREE/device/##" | tr '\n' ' ')
      [ -n "$n" ] && echo "   device trees: $n"
    elif [ -e "$TREE" ] && [ -n "$(ls -A "$TREE" 2>/dev/null)" ]; then
      bad "$TREE exists and isn't a LineageOS tree. Choose an empty directory, or the real tree."
      check_drive "$TREE" "$NEED_NEW_GB"
    else
      echo "   no tree here yet, checking it as a place to sync one"
      check_drive "$TREE" "$NEED_NEW_GB"
      echo "   Then run: tools/05-sync-lineage.sh $TREE"
    fi
  fi
  if [ -n "${CCACHE_DIR:-}" ]; then ok "CCACHE_DIR=$CCACHE_DIR"; fi
fi

echo "== Space for device backups (current directory)"
g=$(df -BG --output=avail . | tail -1 | tr -dc 0-9); [ "$g" -ge "$NEED_BACKUP_GB" ] && ok "${g} GB free in $(pwd)" || warn "${g} GB free in $(pwd). A backup needs about the size of the device's storage, minus userdata."

echo "== Tools for the device"
for t in adb fastboot python3 unzip zipinfo readelf sha256sum debugfs; do has "$t" && ok "$t" || bad "$t missing"; done
if has fastboot; then
  v=$(fastboot --version 2>/dev/null | sed -n 's/^fastboot version \([0-9]*\).*/\1/p'); [ -n "$v" ] && [ "$v" -lt 33 ] && warn "fastboot version $v is old: get platform-tools from Google. Old versions mishandle fastbootd and dynamic partitions."
fi
if has python3; then python3 -c 'import sys; sys.exit(0 if sys.version_info>=(3,8) else 1)' && ok "Python $(python3 -c 'import platform;print(platform.python_version())')" || bad "Python 3.8 or newer needed"; fi

echo "== Permissions"
id -nG | grep -qwE 'plugdev|uucp|dialout' && ok "groups: $(id -nG | tr ' ' ',' | cut -c1-70)" || warn "not in plugdev, dialout or uucp. USB and serial access may need these."
id -nG | grep -qwE 'dialout|uucp' && ok "serial port group present" || warn "not in dialout or uucp: you can't open a UART adapter without sudo. (The first project had the user run picocom themselves.)"
ls /etc/udev/rules.d/*android* /lib/udev/rules.d/*android* /usr/lib/udev/rules.d/*android* >/dev/null 2>&1 && ok "Android udev rules present" || warn "no Android udev rules found. adb may show 'no permissions' (docs/10)."

if [ "$PURPOSE" != device ]; then
  echo "== Tools for building"
  for t in git git-lfs repo make gcc g++ bison flex rsync curl zip lzop gperf xmllint bc ccache; do has "$t" && ok "$t" || { case $t in ccache) warn "ccache missing: optional, but rebuilds after a clean are much faster" ;; repo) bad "repo missing. Also check ~/.local/bin is on PATH." ;; *) bad "$t missing" ;; esac; }; done
  git config --global user.name >/dev/null && git config --global user.email >/dev/null && ok "git identity set" || bad "git identity not set: repo needs it. git config --global user.name and user.email."
  [ -e /usr/lib/x86_64-linux-gnu/libncurses.so.5 ] || [ -e /usr/lib64/libncurses.so.5 ] || [ -e /usr/lib/libncurses.so.5 ] || [ -e /lib/x86_64-linux-gnu/libncurses.so.5 ] || warn "libncurses.so.5 not found: only some prebuilts need it. Install it if a build complains."
fi

echo "== Optional, only for certain jobs (docs/10 says when)"
for t in picocom simg2img fsck.erofs lz4 dtc mkfs.vfat parted gh sunxi-fel jadx; do has "$t" && echo "   have    $t" || echo "   missing $t"; done

echo
printf '%d FAIL, %d WARN\n' "$fails" "$warns"
[ "$fails" = 0 ] && echo "This computer is ready for: $PURPOSE." || echo "Fix each FAIL. docs/10-SETUP-NEW-COMPUTER.md explains how."
[ "$fails" = 0 ]
