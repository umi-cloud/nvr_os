# nvr-os — RK3566 Linux SDK

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

- rootfs 内置 gst 1.22(tools/base/good)+ `gstreamer1.0-rockchip1` 插件:`mppvideodec` / `mpph264enc` /
  `mpph265enc` / `mppjpegdec|enc`,以及 kmssrc/rkximagesink;NVR 解码链示例:
  `rtspsrc ! rtph264depay ! h264parse ! mppvideodec ! kmssink`
- **版本陷阱**:mpp/gst 插件的 deb 必须用 bookworm 构建(packages/arm64 已换)。
  bullseye 旧构建版本号同为 1.5.0-1,但配 6.1 内核会在 MPP 层直接段错误
  (mpi_enc_test 都崩);版本号相同不代表构建相同,以实测为准
- **勿装 gstreamer1.0-plugins-bad 元包**(依赖链拖入 LLVM/GTK/flite 约 300M):
  h264/h265parse 与 kmssink 由构建脚本从 bad 的 deb 中定向抽取
- apt 包本地镜像:`packages/apt-mirror-bookworm/`(361 deb,157M)。镜像非空时构建只用
  file:// 本地源(严格钉版、离线可建);要升级基础包版本,清空该目录联网重建一轮即自动重捕获
- 基准(实测):H264 硬编 720p 285fps/硬解 445fps;H265 硬编 113fps/硬解 712fps(720p),gst 1080p 闭环通过;快速自检
  `mpi_enc_test -w 640 -h 480 -t 7 -n 10 -o /tmp/s.h264` 应输出非零码流

## 硬件说明

**本板无 WiFi/BT/vfd 硬件**(dts 已禁用相关节点,内核裁剪 WLAN/BT 协议栈,rootfs 无相关组件)。
dragon 板(5.10)保留全部原配置。

电源方案(无 SATA 板):无 I2C PMIC(i2c0 禁用是刻意的)——vdd_cpu/vdd_logic 为 PWM 调压 DC-DC
(800-1200mV,DVFS 有效),其余固定 LDO;SATA 板改用 RK809-5(vdd_cpu 仍 PWM 调压)。
RTC:无 SATA 板无 RTC,靠 systemd-timesyncd clock file(每分钟落盘)恢复时间;
SATA 板有 HYM8563(i2c1@0x51,CR1220 备电,alias 固定 rtc0,内核 hctosys 开机恢复)。
fake-hwclock 已从 rootfs 裁掉。
TF 卡槽存在,sdmmc0 保持启用(dwmmc "No normal pinctrl" 告警无害)。
看门狗 /dev/watchdog0 可用,**nvr-edge 需实现喂狗**。

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

- **NVR 板(nvr-ddr3)**:Debian 12 bookworm **headless**(glibc 2.36),`debian/mk-rootfs-bookworm.sh` debootstrap 直建,含 mpp/rga/rknpu2(rknn_server 默认启用,连板调试即插即用)、libmali-g24p0-x11-wayland-gbm、gst 1.22+rkmpp 插件
- **ssh 仅密钥登录**:公钥来自 `debian/authorized_keys`(入库,追加一行即多一把),
  装到 `/root/.ssh/` 后由 `sshd_config.d/10-nvr.conf` 关掉密码认证。用 drop-in 是因为
  主文件第 12 行的 `Include` 在设置之前,sshd 取先出现的值。构建时若无该文件则自动
  保持密码登录(没公钥还禁密码 = 造出登不上的机器)。root 密码仍是 root/root,
  但**只对串口 console 有效**,是密钥丢失时的唯一后路
- **量产前必改**:ssh host key 是构建时打进镜像的,全部设备共用同一把,
  量产前需加首启重新生成(开发期共用反而方便,故未做)
- dragon 板仍为 Debian 11 桌面版(linaro 基底流程,未动)
- **命名陷阱(勿按名字误删)**:`debian/linaro-rootfs.img` 沿用 linaro 时代命名,内容实为 **bookworm**,
  是 `rockdev/rootfs.img` 的真正来源(`mk-image.sh` 硬编码此输出名);`debian/binary/` 是
  bookworm 脚本的 `TARGET_ROOTFS_DIR`,非 bullseye 残留。`overlay/`、`overlay-firmware/`、
  `overlay-debug/` 两套 rootfs 共用。真正只属 bullseye 的是 `linaro-bullseye-alip-*.tar.gz`、
  `mk-rootfs-bullseye.sh`、`mk-base-debian.sh`、`mk-iso-debian.sh`、`ubuntu-build-service/`;
  `overlay_LM/` 全项目零引用,`packages/armhf/` 仅 32 位板用
- 基底缓存 `debian/bookworm-base-arm64.tar.gz`,删掉会重新 debootstrap;**不入库**(~130M),
  新机器首次构建需联网跑一次 debootstrap,之后装包全走本地 apt 镜像
- recovery:`./docker/run.sh ./build.sh recovery` 已在容器内打通(容器重编 output,含 6.1 内核);
  前人旧产物已清理,注意新 recovery 尚未上板验证

### 应用层组件(overlay-nvr)

两个组件随镜像出厂,unit 与启动脚本都在 `debian/overlay-nvr/`:

| 组件 | 基线(rootfs) | 运行体 | 数据/部署 |
|---|---|---|---|
| nvr-edge | `/usr/local/lib/nvr/nvr-edge` | 自更新双槽 `data/selfupdate/nvr-edge/current` | work-dir `/userdata/nvr` |
| vsync | `/usr/local/lib/vsync/vsync` | `/userdata/vsync/vsync`(首启从基线复制) | work-dir `/userdata/vsync`,部署目录 `/vcache` |

- 两者的运行体都不在 rootfs:**nvr-edge** 靠引导器 `/usr/local/bin/nvr` 选双槽、基线兜底;
  **vsync** 的自更新是就地覆盖自己(同目录写 `.new`/`.backup`),没有槽,故运行体必须
  复制到可写的 userdata —— 跑 rootfs 里那份会被 `ProtectSystem=full` 的只读 `/usr` 挡死
- **启动参数一律由启动脚本组装,不写进 unit**:systemd 对不带引号的 `${VAR}` 做 word
  splitting,空值会让整个参数消失,后一个开关被当成前一个的值(Go flag 不报错,静默取错)
- 设备 SN 两者都从 `/proc/device-tree/serial-number` 动态取(vsync 自带的
  getprop/unifykeys/getsn 在 RK3566+Debian 全不匹配);渠道/agent id 均为 102
- unit 的 `RequiresMountsFor` 必须列全用到的分区,且 `WorkingDirectory` 要加 `-` 前缀:
  首启 userdata 刚格式化,目录不存在会在 exec 前 chdir 失败(`200/CHDIR`)导致崩溃循环,
  `ExecStartPre` 同样受其约束救不了;目录由启动脚本 mkdir(那时分区已挂载,不会落在
  被盖住的 rootfs 上)
- MQTT 的 CA 证书随镜像出厂在 `/etc/nvr/certs/ca-cert.pem`。nvr-edge 内嵌了同一份并会
  尝试自写,但 `ProtectSystem=full` 下 `/etc` 只读必然失败,故必须预置
  (当前是 `CN=MyTestCA` 测试证书,量产前替换;要 mTLS 再加 `client.crt`/`client.key`)
- **vsync 是 32 位 ARM 二进制**,依赖内核 `CONFIG_COMPAT=y`(已开)——裁剪内核时勿关

## 板级配置

- 选板:`./build.sh lunch`,配置文件在 `device/rockchip/rk356x/BoardConfig-*.mk`,选中后软链到 `device/rockchip/.BoardConfig.mk`
- 区分逻辑:芯片级(`RK_UBOOT_DEFCONFIG`、rkbin loader)/ 板级(`RK_KERNEL_DIR` 选内核树 + `RK_KERNEL_DTS`,核心)/ 系统级(rootfs、分区表 parameter)
- 现有板子:
  - `BoardConfig-rk3566-evb2-lp4x-v10.mk`:前人定制的机顶盒板("dragon"),5.10 内核,DTS `rk3566-box-demo-v10_rtl8211f`(另有 `_ip1001` PHY 变体)
  - `BoardConfig-rk3566-nvr-ddr3-v1.0.mk`:NVR 无 SATA 板(硬件同为 V1.0,旧命名 v10 已统一为 v1.0),8颗 8bit DDR3,**kernel-6.1** + DTS `rk3566-nvr-ddr3-v1.0`(override 风格,基于官方 box-demo dtsi,含电源域 1.8V/RGMII 时延等实板参数)+ defconfig 片段 `nvr.config`
  - `BoardConfig-rk3566-nvr-ddr3-sata-v1.0.mk`:NVR SATA 板(原理图 UMI-NVR-RK3566-V1.0),DTS `rk3566-nvr-ddr3-sata-v1.0` include 无 SATA 板 dts 只维护差异:SATA 硬盘位(sata2/combphy2,combphy1 保留 USB3 host)、RK809-5 PMIC(box.dtsi 占位 regulator 删除后按原 label 重建,vdd_cpu 仍 PWM 调压)、HYM8563 RTC、RK809 codec 声卡;内核配置与无 SATA 板完全一致
- ⚠ **两块板的固件不通用,烧前先确认 `.BoardConfig.mk` 软链指向哪块**。SATA 板 dts 会
  `/delete-node/` 掉 `vcc_1v8`/`vcc_3v3` 等固定 regulator,改由 i2c0 上的 RK809 提供;
  这份固件烧到无 SATA 板上,PMIC 不存在 → regulator 全缺 → `pmu_io_domains` 配不起来 →
  **网口不通、拿不到 IP**(实际踩过)。反向(无 SATA 固件烧 SATA 板)则丢 SATA 盘与 RTC。
  换板后必须重编内核:`./docker/run.sh ./build.sh kernel` 再 mkfirmware/updateimg;
  rootfs 两块板共用,不必重建。快速自检:反编译 dtb 看 `rk809` 节点数,无 SATA 板应为 0
- DDR 类型由 rkbin 闭源 blob 自动识别(DDR3/DDR4/LP4X 同一 blob),换内存不改源码;调参用 `rkbin/tools/ddrbin_tool`

## git 仓库结构(重要)

- 本目录是 repo 工具管理的多仓库结构(`.repo/` + 各子仓库自带 `.git`)
- **外层 `git add .` 不会收编子仓库内容**(只记 gitlink),勿直接全量提交
- 所有定制改动已提交在各子仓库的 `nvr-custom` 分支(kernel、u-boot、buildroot、debian、device/rockchip、docs、tools、external/rkwifibt 等 10 个仓库);新改动继续提交到对应子仓库的 `nvr-custom`
- `kernel-6.1/` 不归 repo 工具管,是独立 git 克隆(remote 为 armbian/linux-rockchip,可拉取更新),定制同样在 `nvr-custom` 分支
- 与官方基线对比:`git -C kernel diff linux-5.10-gen-rkr3.3 nvr-custom`;6.1 用 `git -C kernel-6.1 diff origin/rk-6.1-rkr6.1 nvr-custom`
- 不入库:`buildroot/output/`(50G 构建产物)、`buildroot/dl/`、`rockdev/`、`.repo/`
- 子仓库远程指向 Rockchip Gerrit,不可推送
- **`kernel/`(5.10)只有 dragon 板在用**(该板 BoardConfig 未设 `RK_KERNEL_DIR`,吃默认值),
  其 `nvr-custom` 相对基线仅 2 个提交且**本地是唯一副本**。删 `.repo/project-objects/rk/kernel.git`
  (2.2G)后无账号拉不回来 → 不可逆。若要清理,先 `git -C kernel bundle create` 备份;
  只想省空间则 `make mrproper`(约 2G,可逆)

## 分区(NVR 两块板共用 parameter-nvr.txt)

uboot 4M / misc 4M / **boot 128M** / recovery 64M / **rootfs 5G** / **userdata 10G** / **vcache:grow**。
无 SATA 板与 SATA 板共用同一张表,改一处两块板同时生效(vcache:grow 自适应不同 eMMC 容量)。
实测样机 eMMC 为 **32G**(29.12 GiB 可用),vcache 实得 13.9G;换 64G/128G eMMC 只有 vcache 变大。
容量依据(实测):rootfs 出厂占用约 1.1G(/usr 1.1G 是大头,含 libmali/WPE/ffmpeg/思源黑体),
5G 余量充足;userdata 现用不到 1G,10G 为应用数据(模型、录像索引等)预留。
rootfs.img 本身只有 867M,按分区大小首启 `resize2fs` 扩展,改分区不必重建 rootfs。
userdata、vcache 不烧镜像,首次开机由 `format-data-parts.service` 自动 mkfs 并按 PARTLABEL 挂载到 `/userdata`、`/vcache`。
dragon 板仍用旧表 parameter-buildroot-fit.txt。改分区表必须整机重烧。

注意:若 mkfirmware 在 envsetup 阶段报错退出(buildroot output 配置路径不一致),
先执行 `cd buildroot && source build/envsetup.sh rockchip_rk3566` 刷新一次即可。

## 烧写

`rockdev/` 下产物用 RKDevTool(Windows,`RKDevTool_Release_v3.19/`)或 `rkflash.sh` / upgrade_tool 烧写。
整机包:`./build.sh updateimg`(宿主机跑)→ `rockdev/update.img`,RKDevTool 升级固件页或 upgrade_tool uf 一键烧。
串口调试波特率 1500000,开机最早的 DDR training 打印可确认内存识别(类型/容量/rank)。
