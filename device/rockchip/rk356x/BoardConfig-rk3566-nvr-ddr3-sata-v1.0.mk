#!/bin/bash
# NVR 板 SATA 版 (UMI-NVR-RK3566-V1.0, 8bit DDR3, RTL8211F PHY)
# 与无 SATA 板(v1.0)差异:SATA 硬盘位(sata2/combphy2)、RK809-5 PMIC、HYM8563 RTC
# 内核 6.1 + Debian 12 headless;无 WiFi/BT/vfd 硬件

# Target arch
export RK_ARCH=arm64
# target chip
export RK_TARGET_PRODUCT=rk356x
# Build jobs
export RK_JOBS=12

# ---- U-Boot ----
export RK_UBOOT_DEFCONFIG=rk3566
# Uboot image format type: fit(flattened image tree)
export RK_UBOOT_FORMAT_TYPE=fit

# ---- Kernel ----
# 内核源码目录(6.1,armbian 官方镜像 rk-6.1-rkr6.1);默认 kernel 为 5.10
export RK_KERNEL_DIR=kernel
export RK_KERNEL_DEFCONFIG=rockchip_linux_defconfig
# rk3566.config 是官方芯片片段(含 Mali-G52 Bifrost kbase),6.1 从 defconfig 拆出,必须叠加
# SATA/AHCI、RK809(MFD/regulator/codec)、HYM8563 驱动 defconfig 均已带,无需额外片段
export RK_KERNEL_DEFCONFIG_FRAGMENT="rk3566.config nvr.config"
export RK_KERNEL_DTS=rk3566-nvr-ddr3-sata-v1.0
export RK_KERNEL_IMG=kernel/arch/arm64/boot/Image
export RK_BOOT_IMG=boot.img
# boot 打包为 FIT
export RK_KERNEL_FIT_ITS=boot.its

# ---- Recovery ----
export RK_CFG_RECOVERY=rockchip_rk356x_recovery
export RK_RECOVERY_FIT_ITS=boot4recovery.its

# ---- rootfs ----
export RK_ROOTFS_TYPE=ext4
export RK_DEBIAN_VERSION=bookworm
export RK_ROOTFS_IMG=rockdev/rootfs.${RK_ROOTFS_TYPE}
# 仅用于 mkfirmware 取 buildroot host 打包工具,rootfs 本身走 debian
export RK_CFG_BUILDROOT=rockchip_rk3566

# ---- 分区与打包 ----
# boot 128M / recovery 64M / rootfs 5G / userdata 10G / vcache:grow(按 parameter-nvr.txt 核算)
export RK_PARAMETER=parameter-nvr.txt
# update.img 打包清单(无 oem/userdata)
export RK_PACKAGE_FILE=rk356x-nvr-package-file
# 空白 misc:首次开机不进 recovery,userdata/vcache 由 rootfs 的
# format-data-parts.service 静默格式化(故不设 RK_OEM_*/RK_USERDATA_*,不生成这两个镜像)
export RK_MISC=blank-misc.img
