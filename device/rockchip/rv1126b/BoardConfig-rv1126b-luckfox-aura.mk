#!/bin/bash
# Luckfox Aura (RV1126B) 开发板:验证 RV1126B 软件栈用,不是出货版型
# 系统盘为板载 eMMC 64GB,整包经 USB-C(Loader/MaskRom 模式)烧录;MicroSD 为扩展;无 SATA、无 USB3
# dts 依据 Luckfox 公开原理图(外设页)与官网规格自写,点亮级:串口/eMMC/SD/网口/USB

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
export RK_KERNEL_DIR=kernel
export RK_KERNEL_DEFCONFIG=rv1126b_defconfig
# 板级片段:开 RGMII delay 标定工具(rv1126b_defconfig 的 MINI_KERNEL 把它关了)
export RK_KERNEL_DEFCONFIG_FRAGMENT="rv1126b-luckfox-aura.config"
export RK_KERNEL_DTS=rv1126b-luckfox-aura
export RK_KERNEL_IMG=kernel/arch/arm64/boot/Image
export RK_BOOT_IMG=boot.img
# boot 打包为 FIT
export RK_KERNEL_FIT_ITS=boot.its

# ---- rootfs ----
export RK_ROOTFS_TYPE=ext4
export RK_DEBIAN_VERSION=bookworm
export RK_ROOTFS_IMG=rockdev/rootfs.${RK_ROOTFS_TYPE}
# 同 EVB:buildroot 树里没有 rv1126b 配置,故不设 RK_CFG_BUILDROOT/RK_CFG_RECOVERY

# ---- 分区与打包 ----
# 与 rk3566 共用 rootfs,分区表也共用(软链到 rk356x/parameter-nvr.txt,uboot/misc 偏移两颗芯片一致)
export RK_PARAMETER=parameter-nvr.txt
export RK_PACKAGE_FILE=rv1126b-package-file
