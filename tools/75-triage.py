#!/usr/bin/env python3
"""Maps log lines to known causes and fixes. Input: any logcat, crash buffer, dmesg, UART or events log.

Usage: 75-triage.py LOG [LOG...]

Each signature here came from a real failure (see docs/05 for the full write-ups). No match means something new: read the first error,
not the last, and add it here once you've solved it. Emails are masked on output, because sign-in logs can contain them.
"""
import collections, re, sys

R = [
 # (regex, title, what it means and what to do)
 (r"Failed to parse bootconfig|Value is redefined", "bootconfig rejected",
  "A key is defined twice, usually by the build and by the bootloader. The kernel drops ALL of bootconfig. Make vendor cmdline and bootconfig match stock exactly."),
 (r"ramdisk use init boot", "Stopped at init_boot (only if nothing follows it)",
  "If there's no 'Starting kernel' after this, check init_boot's header version against stock. Fix: BOARD_MKBOOTIMG_INIT_ARGS += --header_version N."),
 (r"SwitchRoot|Failed to mount required partitions|first_stage_mount|Unable to mount", "First-stage mount problem",
  "Check that the fstab is in the vendor ramdisk, and that every mount point exists in the system root: BOARD_USES_METADATA_PARTITION, BOARD_ROOT_EXTRA_FOLDERS, plus SELinux labels."),
 (r"NetBpfLoad.*(non-optional|CRITICAL)|BPF_PROG_LOAD|bpfloader.*fail|ENOTSUPP", "BPF programs failed to load",
  "On a 32-bit kernel with BPF_JIT_ALWAYS_ON, the JIT rejects atomics and 64-bit div/mod. Remove them from bpf_progs, as stock's vendor/etc/bpf-override does. 50-gate.py --arch32 finds them."),
 (r"Failed to get program from /sys/fs/bpf|libnetd_updatable_init: Failed", "netd aborting: BPF program missing",
  "netd can't run without its BPF programs, and zygote restarts with it. Don't just skip programs at load: rewrite netd.c. See templates/patches/connectivity-bpf-32bit.patch."),
 (r"VINTF parse error|has a conflict: Conflicting FqInstance|NULL VINTF MANIFEST", "VINTF manifest invalid",
  "A HAL is declared twice (a device fragment and an APEX count). servicemanager then treats the whole manifest as null and every HAL lookup fails. 50-gate.py finds these."),
 (r"update_verifier.*(Error getting bootctrl|Failed)|Error getting bootctrl", "No boot control HAL",
  "update_verifier reboots the system without one. Add android.hardware.boot@1.2-impl, -impl.recovery and -service, or the version stock uses."),
 (r"CANNOT LINK EXECUTABLE.*not found", "Missing library",
  "On a build without a VNDK APEX, stock blobs look in /vendor/lib only. Add the .vendor module or a stock copy. If a prebuilt replaced a module, its dependencies aren't installed automatically."),
 (r"cannot locate symbol", "Missing symbol",
  "A stock blob expects a symbol your newer library dropped. Write a small shim library and add it with patchelf --add-needed. See templates/shim."),
 (r"not accessible for the namespace", "Linker namespace",
  "A vendor library tried to load a system library by path. Often harmless if the feature isn't needed. Otherwise provide a vendor copy."),
 (r"TEEC_ERROR_ITEM_NOT_FOUND|TA not found|failed to open the ta", "Trusted app missing",
  "OP-TEE TAs (*.ta) weren't installed. keymint then fails, keystore2 aborts, and the boot stalls. Copy vendor/lib/optee_armtz/*.ta."),
 (r"stoi: no conversion|set_boot_patchlevel", "keymint: empty patch level",
  "Stock keymint parses security-patch properties. Set VENDOR_SECURITY_PATCH, BOOT_SECURITY_PATCH and ro.vendor.boot_security_patch to stock's values."),
 (r"Failed to create service android.system.keystore2|Cannot connect to Keymint|Trying to connect to genuine KeyMint", "keystore2 can't reach KeyMint",
  "This is a result, not the cause. Find why the KeyMint HAL isn't running: TAs, libraries or patch levels."),
 (r"Could not find 'android\.hardware\.graphics\.composer", "Composer HAL missing",
  "No display. The module or its .rc isn't installed. A 'collision' fix may have dropped the stock copy without adding the AOSP module."),
 (r"HwBinder Error: \(-74\)|UNKNOWN_TRANSACTION", "HAL call: UNKNOWN_TRANSACTION",
  "The service doesn't know this method. Check that the interface library is stock's and not an unrelated module with the same name (hermes installed Qualcomm's vendor.display.config@1.0). Rename stock's with patchelf."),
 (r"assertion 'was_validated_' failed|Received UNEXPECTED command status:UNKNOWN_HCI_COMMAND", "Bluetooth: vendor command rejected",
  "The controller rejected a vendor HCI command, and the shim reads an empty response. Remove persist.bluetooth.bqr.* and apply templates/patches/bluetooth-shim-invalid-command-complete.patch."),
 (r"skwbt_boot_open|bt_vendor.*unable to open|hci_hal_android_hidl.*Check failed", "Bluetooth HAL can't open the chip",
  "The char device is missing, so the chip driver isn't loaded. Check dmesg for the SDIO/UART driver. Then look at the scan-timeout entry."),
 (r"wait scan card time out|scan card fail|sdio.*timeout", "Wi-Fi/Bluetooth chip scan timed out",
  "Often caused by console output on a slow UART blocking the kernel, or by load. Lower the console level before drivers load (write /proc/sys/kernel/printk 4), and retry the loader once after boot."),
 (r"Can not initialize the vendor function pointer table|failed to open /vendor/etc/wifi/vendor_hals", "Wi-Fi HAL has no vendor library",
  "AOSP's libwifi-hal fell back to the stub. Use stock's libwifi-hal if it selects the chip's driver itself."),
 (r"skw_wifi_get_chip_feature_set|wifi-service.*SIGSEGV|Fatal signal.*wifi-service", "Wi-Fi HAL crash in vendor library",
  "The AOSP service and stock's vendor HAL disagree on the function table. Use stock's service binary with stock's library, as a matched pair."),
 (r"Signature\|privileged permissions not in privapp-permissions allowlist", "Boot loop: priv-app allowlist",
  "A privileged app's permissions aren't allowlisted, so system_server aborts. Generate a privapp-permissions XML from aapt2 dump permissions. tools/80-apps.py does this."),
 (r"No APK Signature Scheme v2 signature|Failed to scan .*\.apk", "APK rejected: signature broken",
  "The build rewrote a presigned APK, most often because of LOCAL_PREBUILT_JNI_LIBS. Use LOCAL_REPLACE_PREBUILT_APK_INSTALLED and copy the libraries beside it. tools/80-apps.py does this."),
 (r"UnsatisfiedLinkError", "App can't load a native library",
  "Compressed JNI libraries aren't extracted for system apps. Check the app's lib/arm directory, or install it as a user app. GMS logs some harmless misses, such as libbrotli_native."),
 (r"lowmemorykiller: Kill '[^']+' \(\d+\), uid \d+, oom_score_adj (?:[0-9]|[0-9][0-9]|1[0-9][0-9]|200) ", "lmkd killing foreground, visible or keyboard processes",
  "If swap is free, this is wrong. It's usually the old strategy: remove stock's ro.lmk.critical=1 and use ro.lmk.use_new_strategy=true. Symptoms: menus closing by themselves and sign-in failing."),
 (r"low watermark is breached and swap is low", "lmkd says swap is low (check it really is)",
  "Compare with SwapFree. lmkd uses min(free swap, free RAM + inactive file) against 10% of total swap, so a large swap on low RAM causes kills with swap free. Set ro.lmk.swap_free_low_percentage=3."),
 (r"System UI isn't responding|ANR in ", "Apps not responding",
  "Often memory pressure plus a slow disk. Check MemAvailable and SwapTotal. If swap is 0, zram never started: its init trigger may depend on a stock-only property."),
 (r"can't allocate .*swap|fallocate: -l", "Swap file not created",
  "toybox fallocate rejects sizes above 2147483647 on 32-bit. Use 2147483647."),
 (r"audit: rate limit exceeded|has incorrect label or no domain transition|libprocessgroup: Failed to", "Harmless noise while permissive",
  "SELinux logs on a permissive build, or init cleaning up after exited processes. Not a cause on its own."),
 (r"init: .*(fatal|Fatal)|InitFatalReboot", "init aborted",
  "Read the lines just before this. androidboot.init_fatal_reboot_target=recovery sends such failures to recovery."),
 (r"mmc 0 cmd timeout|card0 init failed|mmc_init: -95|reserving fdt memory region failed|secure storage read|Load advert_file fail|fail to get clk|failed to request regulator|KSC_ERR|FDT_ERR_INTERNAL|Bad device usb 0|EHCI fail timeout", "Bootloader noise, normal on hermes",
  "Appears on good boots too: absent SD slot, optional properties, missing keys. See 'Looks scary, but is normal' in docs/05. On another device, compare with its stock log."),
 (r"Command 'restart .*failed: service|Could not create socket 'pdx/|cutils-trace: Error opening|using dummy regulator|failed to load regulatory\.db|Volume was not properly unmounted", "Android or kernel noise, usually harmless",
  "AOSP .rc files name service variants this device doesn't have, and vendor kernels print optional-hardware messages. Only look closer if a feature is actually broken."),
 (r"Tried to start aidl service .* as a lazy service", "Lazy service couldn't start",
  "Often a side effect of a service restarting. Check that the named HAL is declared and running with lshal and getprop init.svc.*."),
 (r"Unknown command '0x40007000'|Unable to read file", "Rescue stick script running",
  "Expected only when a rescue stick's auto_update.txt runs. If no stick is inserted, look closer."),
 (r"Out of space\? Out of inodes\?", "Image build: 'Out of space' (may be misleading)",
  "Compare the tree size and max image size in the message. If there's room, it's something else: on hermes, new root folders with no SELinux labels. See docs/08."),
 (r"overriding commands for target|already defined|VINTF metadata found in PRODUCT_COPY_FILES|includes non-existent modules|found ELF prebuilt|dumpvars failed|soong bootstrap failed", "Build error",
  "See docs/08-BUILD-ERRORS.md, sorted by stage. Fix the first error, and batch collision fixes."),
 (r"Kernel panic|Unable to handle kernel|Internal error: Oops", "Kernel crash",
  "The Android-side watchdog can't help here. You need UART, and possibly the rescue route. Check the stock kernel is being used unchanged."),
 (r"prefetch abort|data abort", "Bootloader crash",
  "A u-boot command overran memory or ran with bad parameters. Read docs/03 before retrying anything."),
 (r"WaitForDisplay took to complete: \d{4,}ms|DisplayManagerService took \d{4,} ms in onBootPhase", "Boot waits seconds for the display",
  "Often not the display. Capture stacks during the wait with tools/78-boot-stacks.sh. On hermes, SurfaceFlinger's RenderEngine was compiling shaders in the Mali driver: service.sf.prime_shader_cache=0 saved 9 s (docs/13, 3b)."),
 (r"cmpbe_v2_compile_multiple_shaders", "GPU driver compiling shaders",
  "Seen in a SurfaceFlinger stack during boot. Shader cache priming blocks composition on a slow CPU: try service.sf.prime_shader_cache=0 (docs/13, 3b)."),
 (r"su: request rejected \(\d+\)", "Magisk denied root without asking",
  "Magisk 31.1 has no prompt: an app with no stored policy is rejected. Grant it in Magisk's Superuser tab, or add a row to the policies table (docs/05, Root)."),
 (r"ADB Root access is disabled by system setting", "adb root disabled",
  "LineageOS's Rooted debugging toggle, in Developer options. Ask the user."),
 (r"Service 'blank_screen' .*exited with status 255|cannot find blank_screen", "blank_screen failed at shutdown",
  "No lights HAL. Harmless: removing it didn't speed up shutdown on hermes (docs/13, 4c)."),
 (r"So far shutdown sequence took \d+ms|Waiting for \d+ pids to be reaped took", "Shutdown timing from init",
  "Not an error: init's own timing of the shutdown. Compare it between builds (docs/13, section 4)."),
]

EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+")

def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    pats = [(re.compile(p), t, h) for p, t, h in R]
    hits = collections.OrderedDict()
    lines = 0
    for path in sys.argv[1:]:
        try:
            f = open(path, errors="replace")
        except OSError as e:
            print(f"skipping {path}: {e}")
            continue
        with f:
            for line in f:
                lines += 1
                for p, t, h in pats:
                    if p.search(line):
                        e = hits.setdefault(t, {"n": 0, "first": EMAIL.sub("<email>", line.strip())[:170], "help": h})
                        e["n"] += 1
                        break
    print(f"Read {lines} lines. {len(hits)} known signatures, in order of first appearance:\n")
    for t, e in hits.items():
        print(f"* {t}  ({e['n']}x)\n    first: {e['first']}\n    what to do: {e['help']}\n")
    if not hits:
        print("Nothing recognised. Read the FIRST error before the failure, then see docs/05-DEBUG-CATALOG.md.")
    print("Fix the earliest cause first: later errors are often results of it.")

main()
