#!/bin/bash
# NVR 板 RV1126B SATA 版(原理图 UMI-NVR-RV1126B-V1.0):LPDDR3、eMMC 系统盘、RK801 PMIC、
# 双网口(千兆 RGMII + 板载 USB 百兆 RTL8152B)、SATA 硬盘位走 JMS578 USB3-SATA 桥(RV1126B 无原生 SATA)。
# 烧录走 MaskRom(板上无 USB-C 下载口)。dts 依原理图自写,未上真机。

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
# 板级片段:SATA(USB 存储/UAS)、RTL8152、PHY 驱动、LED、MPP、容器等,见文件头注释
export RK_KERNEL_DEFCONFIG_FRAGMENT="rv1126b-nvr.config"
export RK_KERNEL_DTS=rv1126b-nvr-sata-v1.0
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
