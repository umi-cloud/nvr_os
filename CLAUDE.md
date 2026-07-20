# nvr_os — RK3566 Linux SDK

Rockchip RK3566 Linux5.10 SDK(基线 tag `linux-5.10-gen-rkr3.3`,kernel 5.10.110,Debian 11 / Buildroot rootfs)。
来源:官方 Gerrit(`ssh://git@www.rockchip.com.cn`,本机无账号,同步需授权机器)。

## 编译:一律使用 docker 环境

宿主机缺内核构建依赖(flex 等),不要在宿主机直接编译。

```bash
# 构建镜像(一次性,必须加 --network=host,bridge 网络下 buildkit DNS 解析失败)
docker build --network=host -t nvr-os-builder:20.04 docker/

# 进入交互环境
docker/run.sh

# 直接执行构建
docker/run.sh ./build.sh kernel
docker/run.sh ./build.sh all      # uboot + kernel + rootfs
docker/run.sh ./mkfirmware.sh     # 产物汇总到 rockdev/
```

- 镜像:Ubuntu 20.04,含 Rockchip 官方依赖 + qemu-user-static/binfmt(debian rootfs 的 arm64 chroot 需要)
- run.sh 使用 `--privileged --network=host`:前者供 rootfs 构建 chroot/mount,后者保证容器内在线装包
- 容器内用户 `builder`(UID 1000,与宿主机一致),挂载 SDK 到 `/sdk`

## 板级配置

- 选板:`./build.sh lunch`,配置文件在 `device/rockchip/rk356x/BoardConfig-*.mk`,选中后软链到 `device/rockchip/.BoardConfig.mk`
- 区分逻辑:芯片级(`RK_UBOOT_DEFCONFIG`、rkbin loader)/ 板级(`RK_KERNEL_DTS`,核心)/ 系统级(buildroot config、分区表 parameter)
- 现有板子:
  - `BoardConfig-rk3566-evb2-lp4x-v10.mk`:前人定制的机顶盒板("dragon"),DTS `rk3566-box-demo-v10_rtl8211f`(另有 `_ip1001` PHY 变体)
  - `BoardConfig-rk3566-nvr-ddr3-v10.mk`:NVR 板,8颗 8bit DDR3,DTS `rk3566-nvr-ddr3-v10`(薄封装 include rtl8211f dtsi)
- DDR 类型由 rkbin 闭源 blob 自动识别(DDR3/DDR4/LP4X 同一 blob),换内存不改源码;调参用 `rkbin/tools/ddrbin_tool`

## git 仓库结构(重要)

- 本目录是 repo 工具管理的多仓库结构(`.repo/` + 各子仓库自带 `.git`)
- **外层 `git add .` 不会收编子仓库内容**(只记 gitlink),勿直接全量提交
- 所有定制改动已提交在各子仓库的 `nvr-custom` 分支(kernel、u-boot、buildroot、debian、device/rockchip、docs、tools、external/rkwifibt 等 10 个仓库);新改动继续提交到对应子仓库的 `nvr-custom`
- 与官方基线对比:`git -C kernel diff linux-5.10-gen-rkr3.3 nvr-custom`
- 不入库:`buildroot/output/`(50G 构建产物)、`buildroot/dl/`、`rockdev/`、`.repo/`
- 子仓库远程指向 Rockchip Gerrit,不可推送

## 烧写

`rockdev/` 下产物用 RKDevTool(Windows,`RKDevTool_Release_v3.19/`)或 `rkflash.sh` / upgrade_tool 烧写。
串口调试波特率 1500000,开机最早的 DDR training 打印可确认内存识别(类型/容量/rank)。
