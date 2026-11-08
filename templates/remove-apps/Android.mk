# Removes apps inherited from AOSP, ATV or Lineage products. It must be a real module: phony modules can't use overrides.
# Add "custom-removed-apps" to PRODUCT_PACKAGES, and put any short text file next to this one as custom-removed-apps.txt.
# Keep: TvSettings (fallback home), ContactsProvider (Play services uses it), Telecom (framework expects it),
#       LineageSetupWizard (first-run Wi-Fi, remote and language; it has no Google login).
include $(CLEAR_VARS)
LOCAL_MODULE := custom-removed-apps
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_SUFFIX := .txt
LOCAL_SRC_FILES := custom-removed-apps.txt
# Phone Settings, plus the phone stack for a device with no modem:
LOCAL_OVERRIDES_MODULES := Settings \
    TeleService Dialer Contacts messaging MmsService WAPPushManager Stk ONS EmergencyInfo CallLogBackup \
    ImsServiceEntitlement CarrierConfig CarrierDefaultApp CellBroadcastLegacyApp com.android.cellbroadcast rild
# Optional: add blank_screen if the device has no lights HAL. It runs at shutdown, waits about 2 s and fails.
# Removing it didn't speed up shutdown on the first device (docs/13, 4c), so it's only tidying.
include $(BUILD_PREBUILT)
