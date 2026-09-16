#!/bin/bash
# RV1126B EVB1 V10:官方 SDK 标准配置,用于打通芯片与构建链
# 自研 SATA 版型(RV1126B 无原生 SATA,走 USB3-SATA 桥)定型后另建 BoardConfig,不在本文件上改

# Target arch
export RK_ARCH=arm64
# target chip
export RK_TARGET_PRODUCT=rv1126b
# Build jobs
export RK_JOBS=12

# ---- U-Boot ----
export RK_UBOOT_DEFCONFIG=rv1126b
# Uboot image format type: fit(flattened image tree)
export RK_UBOOT_FORMAT_TYPE=fit

# ---- Kernel ----
# 与 rk3566 板共用 6.1 内核树;rv1126b 的 defconfig 与 EVB dts 官方树已带
export RK_KERNEL_DIR=kernel
export RK_KERNEL_DEFCONFIG=rv1126b_defconfig
export RK_KERNEL_DTS=rv1126b-evb1-v10
export RK_KERNEL_IMG=kernel/arch/arm64/boot/Image
export RK_BOOT_IMG=boot.img
# boot 打包为 FIT
export RK_KERNEL_FIT_ITS=boot.its

# ---- rootfs ----
export RK_ROOTFS_TYPE=ext4
export RK_DEBIAN_VERSION=bookworm
export RK_ROOTFS_IMG=rockdev/rootfs.${RK_ROOTFS_TYPE}
# buildroot 侧无 rv1126b 配置,故不设 RK_CFG_BUILDROOT/RK_CFG_RECOVERY;
# 二者只在 mkfirmware 取打包工具与编 recovery 时用到,uboot/kernel 构建不需要

# ---- 分区与打包 ----
# 官方标准分区表
export RK_PARAMETER=parameter.txt
# 打包清单暂不含 oem/userdata(未生成这两个镜像,列入会导致 updateimg 失败)
export RK_PACKAGE_FILE=rv1126b-package-file
