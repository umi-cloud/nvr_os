# nvr_os — RK3566 Linux SDK

Rockchip RK3566 Linux SDK,双内核并存:
- `kernel/`:5.10.110(基线 `linux-5.10-gen-rkr3.3`,官方 Gerrit 同步,本机无账号)
- `kernel-6.1/`:6.1(armbian 官方镜像 `rk-6.1-rkr6.1` = `linux-6.1-stan-rkr6.1`,无需账号)——**NVR 板当前使用**

内核目录由 BoardConfig 的 `RK_KERNEL_DIR` 选择(默认 `kernel`,dragon 板仍用 5.10)。

## GPU(Mali-G52 Bifrost)

- 内核配置**必须叠加官方芯片片段** `rk3566.config`(6.1 把 GPU 配置从 defconfig 拆了出来):
  `RK_KERNEL_DEFCONFIG_FRAGMENT="rk3566.config nvr.config"`。漏了会只编 mali400(Utgard),
  与 G52 不匹配 → 无 `/dev/mali0`、GLES/OpenCL 全废
- 用户态 libmali-bifrost-g52-**g24p0**-x11-wayland-gbm(同时支持 GBM/X11/Wayland),
  与内核 kbase **g25p0** 相邻代配对。实测 EGL 1.5、GLES 3.2、OpenCL 3.0 全通过,
  X11 路径为 DRI3(依赖 libxcb-dri3/present/xfixes,构建脚本已带)
- 备注:官方 6.1 SDK 脚本默认给 rk356x 选 g13p0(EGL 1.4、2020 年库),包目录里留有其 deb 作回退
- 不要用 gbm-only 变体:它只导出 `EGL_KHR_platform_gbm`,Chromium(X11)和 cog/cage(Wayland)全废
- 库在 `/usr/lib/aarch64-linux-gnu/mali/`(libEGL/libGLESv2/libgbm/libMaliOpenCL),
  该路径已在 ld.so.conf.d 中,应用直接 `-lEGL -lGLESv2` 即可
- **应用集成注意**(多平台变体下必须这么写,否则**段错误**):原生 DRM/KMS 程序要用
  `eglGetPlatformDisplayEXT(EGL_PLATFORM_GBM_KHR, gbm_create_device(open("/dev/dri/renderD128")), NULL)`。
  旧写法 `eglGetDisplay(gbm_dev)` 在 gbm-only 变体上能用,换成多平台变体后会被误判为 X11 Display* 而崩溃;
  传 `EGL_DEFAULT_DISPLAY` 则 eglInitialize 失败
- 实测:GL_RENDERER=Mali-G52、OpenGL ES 3.2;OpenCL 3.0 设备 Mali-G52 r1p0
- GPU DVFS:rk356x.dtsi 的 gpu_opp_table 漏了每条 OPP 的 `opp-supported-hw`(表级
  `rockchip,supported-hw` 却在),会导致全部 OPP 被否 → 无 devfreq;板级 dts 已补齐,
  现为 200/300/400/600/700MHz simple_ondemand(800MHz 档被 rk3566-box.dtsi 删除)

## 视频编解码(MPP + GStreamer)

- rootfs 内置 gst 1.22 + `gstreamer1.0-rockchip1` 插件:`mppvideodec` / `mpph264enc` /
  `mpph265enc` / `mppjpegdec|enc`,以及 kmssrc/rkximagesink;NVR 解码链示例:
  `rtspsrc ! rtph264depay ! h264parse ! mppvideodec ! kmssink`
- **版本陷阱**:mpp/gst 插件的 deb 必须用 bookworm 构建(packages/arm64 已换)。
  bullseye 旧构建版本号同为 1.5.0-1,但配 6.1 内核会在 MPP 层直接段错误
  (mpi_enc_test 都崩);版本号相同不代表构建相同,以实测为准
- 基准(实测):H264 硬编 720p 285fps/硬解 445fps;H265 硬编 113fps/硬解 712fps(720p),gst 1080p 闭环通过;快速自检
  `mpi_enc_test -w 640 -h 480 -t 7 -n 10 -o /tmp/s.h264` 应输出非零码流

## 硬件说明

**本板无 WiFi/BT/vfd 硬件**(dts 已禁用相关节点,内核裁剪 WLAN/BT 协议栈,rootfs 无相关组件)。
dragon 板(5.10)保留全部原配置。

已完成:librknnrt 2.3.2(配 rknpu 0.9.8);首块板整机点亮验证(eMMC/网口/加速全家/分区自适应);
开机 logo 全程无缝(u-boot drm-logo 预留页对齐补丁 + 360px um 标志);
DDR 动态调频(opp 适配 DDR3 频点 + 使能 dfi + auto-freq-en=1,空闲 324MHz↔负载 1056MHz 实测闭环;
建议量产前跑通宵压力浸泡);WiFi/BT/vfd 全量裁剪。
待观察:sdmmc supports-* 旧式属性未移植(6.1 官方属性优先,异常再查)。

## 编译:一律使用 docker 环境

宿主机缺内核构建依赖(flex 等),不要在宿主机直接编译。

```bash
# 构建镜像(一次性,必须加 --network=host,bridge 网络下 buildkit DNS 解析失败)
docker build --network=host -t nvr-os-builder:20.04 docker/

# 进入交互环境
docker/run.sh

# 直接执行构建
docker/run.sh ./build.sh uboot    # loader + uboot.img
docker/run.sh ./build.sh kernel   # 内核(NVR 板为 6.1)→ boot.img
docker/run.sh ./build.sh debian   # bookworm rootfs
./mkfirmware.sh                   # 在宿主机跑!汇总到 rockdev/
```

mkfirmware 必须在宿主机执行:buildroot 的 host 工具容器里跑不了(GLIBC),
且容器内执行会把 rockdev 软链写成 /sdk 绝对路径导致宿主机断链。
不要用 `build.sh all`(会触发 buildroot,容器内必失败)。

- 镜像:Ubuntu 20.04,含 Rockchip 官方依赖 + qemu-user-static/binfmt(debian rootfs 的 arm64 chroot 需要)
- run.sh 使用 `--privileged --network=host`:前者供 rootfs 构建 chroot/mount,后者保证容器内在线装包
- 容器内用户 `builder`(UID 1000,与宿主机一致),挂载 SDK 到 `/sdk`

## rootfs

- **NVR 板(nvr-ddr3)**:Debian 12 bookworm **headless**(glibc 2.36),`debian/mk-rootfs-bookworm.sh` debootstrap 直建,含 mpp/rga/rknpu2(rknn_server 默认不启用)/libmali-g13p0-gbm/WiFi·BT 固件;开发期账号 root/root(量产前必须改)
- dragon 板仍为 Debian 11 桌面版(linaro 基底流程,未动)
- 基底缓存 `debian/bookworm-base-arm64.tar.gz`,删掉会重新 debootstrap
- recovery:`./docker/run.sh ./build.sh recovery` 已在容器内打通(容器重编 output,含 6.1 内核);
  前人旧产物已清理,注意新 recovery 尚未上板验证

## 板级配置

- 选板:`./build.sh lunch`,配置文件在 `device/rockchip/rk356x/BoardConfig-*.mk`,选中后软链到 `device/rockchip/.BoardConfig.mk`
- 区分逻辑:芯片级(`RK_UBOOT_DEFCONFIG`、rkbin loader)/ 板级(`RK_KERNEL_DIR` 选内核树 + `RK_KERNEL_DTS`,核心)/ 系统级(rootfs、分区表 parameter)
- 现有板子:
  - `BoardConfig-rk3566-evb2-lp4x-v10.mk`:前人定制的机顶盒板("dragon"),5.10 内核,DTS `rk3566-box-demo-v10_rtl8211f`(另有 `_ip1001` PHY 变体)
  - `BoardConfig-rk3566-nvr-ddr3-v10.mk`:NVR 板,8颗 8bit DDR3,**kernel-6.1** + DTS `rk3566-nvr-ddr3-v10`(override 风格,基于官方 box-demo dtsi,含电源域 1.8V/RGMII 时延等实板参数)+ defconfig 片段 `nvr.config`
- DDR 类型由 rkbin 闭源 blob 自动识别(DDR3/DDR4/LP4X 同一 blob),换内存不改源码;调参用 `rkbin/tools/ddrbin_tool`

## git 仓库结构(重要)

- 本目录是 repo 工具管理的多仓库结构(`.repo/` + 各子仓库自带 `.git`)
- **外层 `git add .` 不会收编子仓库内容**(只记 gitlink),勿直接全量提交
- 所有定制改动已提交在各子仓库的 `nvr-custom` 分支(kernel、u-boot、buildroot、debian、device/rockchip、docs、tools、external/rkwifibt 等 10 个仓库);新改动继续提交到对应子仓库的 `nvr-custom`
- `kernel-6.1/` 不归 repo 工具管,是独立 git 克隆(remote 为 armbian/linux-rockchip,可拉取更新),定制同样在 `nvr-custom` 分支
- 与官方基线对比:`git -C kernel diff linux-5.10-gen-rkr3.3 nvr-custom`;6.1 用 `git -C kernel-6.1 diff origin/rk-6.1-rkr6.1 nvr-custom`
- 不入库:`buildroot/output/`(50G 构建产物)、`buildroot/dl/`、`rockdev/`、`.repo/`
- 子仓库远程指向 Rockchip Gerrit,不可推送

## 分区(NVR 板,parameter-nvr.txt)

uboot 4M / misc 4M / **boot 128M** / recovery 64M / **rootfs 4G** / **userdata 6G** / **vcache:grow**(64G/128G eMMC 通用)。
userdata、vcache 不烧镜像,首次开机由 `format-data-parts.service` 自动 mkfs 并按 PARTLABEL 挂载到 `/userdata`、`/vcache`。
dragon 板仍用旧表 parameter-buildroot-fit.txt。改分区表必须整机重烧。

注意:若 mkfirmware 在 envsetup 阶段报错退出(buildroot output 配置路径不一致),
先执行 `cd buildroot && source build/envsetup.sh rockchip_rk3566` 刷新一次即可。

## 烧写

`rockdev/` 下产物用 RKDevTool(Windows,`RKDevTool_Release_v3.19/`)或 `rkflash.sh` / upgrade_tool 烧写。
整机包:`./build.sh updateimg`(宿主机跑)→ `rockdev/update.img`,RKDevTool 升级固件页或 upgrade_tool uf 一键烧。
串口调试波特率 1500000,开机最早的 DDR training 打印可确认内存识别(类型/容量/rank)。
