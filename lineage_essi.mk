#
# Copyright (C) 2025 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit some common Lineage stuff.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Inherit from essi device
$(call inherit-product, device/samsung/essi/device.mk)

PRODUCT_DEVICE := essi
PRODUCT_NAME := lineage_essi
PRODUCT_BRAND := samsung
PRODUCT_MODEL := SM-X520
PRODUCT_MANUFACTURER := samsung

PRODUCT_GMS_CLIENTID_BASE := android-samsung-ss

PRODUCT_BUILD_PROP_OVERRIDES += \
    PRIVATE_BUILD_DESC="gts10fewifixx-user 15 AP3A.240905.015.A2 X520XXS2AYD3 release-keys"

BUILD_FINGERPRINT := samsung/gts10fewifixx/essi:15/AP3A.240905.015.A2/X520XXS2AYD3:user/release-keys
