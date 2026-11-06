# Product definition for lineage_hermes (Allwinner H723 projector, Android TV)

# Inherit the Android TV base (Leanback launcher, TvSettings, 10-foot UI).
$(call inherit-product, device/allwinner/hermes/device.mk)

# Android TV flavour of the AOSP/LineageOS base.
# atv_base.mk below still inherits telephony; Android.mk removes the phone app itself (docs/17).
$(call inherit-product, $(SRC_TARGET_DIR)/product/aosp_base.mk)
$(call inherit-product, device/google/atv/products/atv_base.mk)

# LineageOS common TV bits. REQUIRED when building with `mka bacon`: this pulls in
# vendor/lineage/config/{common,version}.mk, which set LINEAGE_VERSION / LINEAGE_BUILD. Without it the
# bacon package is named `lineage-.zip` (empty version) and the `ln -f` step fails. Also adds the
# LineageOS TV app suite. Inherited after the AOSP/ATV base (most-specific-first convention).
$(call inherit-product, vendor/lineage/config/common_full_tv.mk)

PRODUCT_NAME := lineage_hermes
PRODUCT_DEVICE := hermes
PRODUCT_BRAND := Allwinner
PRODUCT_MODEL := H723 Projector
PRODUCT_MANUFACTURER := Allwinner

PRODUCT_CHARACTERISTICS := tv
PRODUCT_AAPT_PREF_CONFIG := xhdpi

# Match the stock build identity enough for apps; set a TRUTHFUL fingerprint (not the
# spoofed ADT-3 one from stock — see docs/02 finding #7).
PRODUCT_SYSTEM_DEFAULT_PROPERTIES += \
    ro.product.cpu.abilist=armeabi-v7a,armeabi \
    ro.product.cpu.abilist32=armeabi-v7a,armeabi \
    ro.product.cpu.abilist64=
