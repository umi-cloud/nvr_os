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

- 组件版本(2026-09):**mpp 1.1.0**(`1:1.1.0-1`)、**librga 1.10.6**(`1:1.10.6-1`,上游只发预编译库,
  自写 debian/ 打包)、gst-rockchip 插件**保持 1.14-4 旧二进制**——同一份源码对 mpp 1.1.0 头文件重编后
  1080p I420 走 RGA 转换必失败(内核报 job_commit failed),旧二进制配新库反而正常,四种组合交叉验证过。
  重打 deb 的配方与这个坑见 `debian/pkgbuild/README.md`。
  验证基准(SATA 板,mpp 1.1.0):`mpi_enc_test` 720p H264/H265 报 87/84 fps(**旧 mpp 1.5.0 同一命令也是 87**,
  下面那条 285fps 是早期不同测法的数字,不要拿来对比),`mpi_dec_test` 720p H264 800+fps、H265 1270fps,
  gst 1080p I420 编→解闭环通过、RGA 0 报错。
  NPU:rknpu 驱动 0.9.8 + librknnrt 2.3.2 已是上游最新;Mali kbase g25p0 不能单独升(g29p1 无配套 libmali)
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
NTP 源钉阿里云(`/etc/systemd/timesyncd.conf.d/10-nvr.conf`:`ntp.aliyun.com ntp1.aliyun.com`,
cn.pool 兜底)——Debian 默认池会先连试境外 IPv6 地址超时数轮,无 RTC 的板子这段时间只能用旧时间。
注意 ntp2~ntp7.aliyun.com 与 ntp.aliyun.com 是同一个 anycast 地址,列多个不增加冗余。
RTC:无 SATA 板无 RTC,靠 systemd-timesyncd clock file(每分钟落盘)恢复时间;
SATA 板**用 RK809 内置 RTC**(rk808-rtc = rtc0,内核 hctosys/systohc 直接读写)。板上的 HYM8563
(i2c1@0x51)节点保留但 disabled:两颗同时注册时 RK809 作为 MFD 子设备先抢 rtc0,
`aliases { rtc0 = &hym8563 }` 无效(内核报 `/aliases ID 0 not available`)。要换回 HYM8563 须同时关
`CONFIG_RTC_DRV_RK808`。fake-hwclock 已从 rootfs 裁掉。
**DDR 调频(dmc)按板区分**:无 SATA 板开 auto-freq(324↔1056);**SATA 板 dmc 关闭、定频 1056**——
该板开调频后随机 Oops(非法指令/PID 1 段错误),panic 时 cur_freq 均为 324MHz,loader 降 780 无改善,
关 dmc 后 4 核+硬编压力与 memtester 1GB 全过。两板差异:无 SATA 板 dmc 的 center-supply 是 950mV 固定
`vdd_fixed`(调频不动电压),SATA 板是 RK809 `vdd_logic` 900mV(真调压)。恢复调频的路径写在 SATA dts 注释里。
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
- **串口控制台**:`serial-getty@ttyFIQ0` 已启用,root/root 密码登录(Rockchip overlay 原来写死
  `--autologin root` 免密进 shell,构建脚本已 sed 掉)。`systemctl reboot loader` 可远程进烧写模式,
  不用按 recovery 键
- **设备身份(vendor storage,eMMC 末尾厂商区)**:`nvr-provision <SN> <MAC1> <MAC2>` 写入,`show` 回读。
  SN 16 位、`UMNVR3566` 开头;u-boot 下次启动把 SN 注入 `/serial-number`(nvr-edge/vsync 的设备 SN),
  MAC1 注入 gmac1(dts 别名 `ethernet0`,因此网口名是 **end0**),MAC2 由 udev 打标签拉起
  `nvr-usb-eth-mac@eth1.service` 套到 USB 网口(r8152 无 EEPROM、开机随机)。工具是官方
  `external/rktoolkit/vendor_storage.c`,构建期交叉编译进 `/usr/local/sbin`。**upgrade_tool 只能写 SN 不能写 MAC**
- **主机名** `UMI-<SN 后 6 位>`(`nvr-hostname.service` 每次开机幂等):两块板同名时路由器按主机名派同一 IP
- **两个网口都走 DHCP**(`10-lan.network` 匹配 `en* eth*`);只写 `en*` 会把 USB 口漏掉,线插那边就没网
- **网口灯**:RTL8211F LCR 由 PHY 节点 `realtek,led-lcr` 指定(stmmac 的 led_fixup 原来写死 0xc160),
  NVR 板取 0xc20b(LED0 常亮 link,LED1/LED2 收发闪烁),两颗灯都闪、没有常亮则改回 0xc160
- **ssh host key 首启生成**:镜像不带 host key,`nvr-ssh-hostkeys.service` 首启 `ssh-keygen -A`,每台设备
  各不相同。代价是每刷一次固件 known_hosts 都会报 key 变化,开发期用 `-o StrictHostKeyChecking=no` 即可
- **系统自愈与收敛**(overlay-nvr/etc/systemd):PID 1 喂硬件看门狗(`RuntimeWatchdogSec=30s`,内核或
  PID 1 卡死 30 秒自动复位;nvr-edge 自己的喂狗仍待做);journald 封顶 64M;apt-daily/e2scrub/dpkg-db-backup
  定时器已 mask,adbd 已关(USB 是 host 模式);根分区 noatime。板上常驻服务 13 个,启动 8 秒
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
| nvr-edge | `/usr/local/lib/nvr/nvr-edge` | `/userdata/nvr/bin/nvr-edge`(首启从基线复制,之后由自更新从活动槽同步) | work-dir `/userdata/nvr`,双槽 `data/selfupdate/nvr-edge/` |
| vsync | `/usr/local/lib/vsync/vsync` | `/userdata/vsync/vsync`(首启从基线复制) | work-dir `/userdata/vsync`,部署目录 `/vcache` |

- **两者的运行体都必须在可写的 userdata,跑 rootfs 里那份会被 `ProtectSystem=full` 的只读 `/usr` 挡死**,
  但失败方式不同:
  - **vsync** 的自更新是就地覆盖自己(同目录写 `.new`/`.backup`),没有槽,写不进去就更新不了
  - **nvr-edge** 更隐蔽:它把自己的可执行文件路径当作"固定启动路径"
    (`app.go` 的 `AgentInstallPath` 默认取 `os.Executable()`),切槽后要把活动槽二进制
    复制回该路径(`updater.go` 的 `activate`)。这一步失败时 `Install()` **整体回滚** ——
    切回旧 current、擦掉刚下好的新槽。下载、sha256、健康自检全过,只在最后一步倒回,
    日志看着像更新完了。若从 `/usr` 里的基线启动,**裸机首次 OTA 必然失败且永远卡在出厂版本**
- 故引导器 `/usr/local/bin/nvr` 不做"槽优先"选择,只保证 `/userdata/nvr/bin/nvr-edge` 上
  有个能跑的二进制(缺失/0 字节才从基线补),哪个槽活动由 `state.json` 说了算:
  启动时 `RecoverBoot` 会 `activate` 一次把活动槽同步过来并请求重启,自愈。
  `ConfirmBootFrom` 按**内容 sha256** 而非路径比对,故固定路径与槽是副本关系不影响 trial 确认
  (真机实测:换成固定路径启动后,首次启动日志出现一次
  `固定启动程序与活动槽不一致,已修复并请求重启` + 一次 ConfirmBoot WARN,重启后即收敛)
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
  rootfs 两块板共用,不必重建。快速自检:反编译 dtb 看 `rk809` 节点数,无 SATA 板应为 0。
  两块板的 dts 与 BoardConfig 直到 2026-09 才补入库(此前只有旧名 v10 在库里),改完记得 `git status`
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

⚠ **SDK 里有两个 upgrade_tool,别用错**:
- `rkbin/tools/upgrade_tool` 是 **v1.54(2018 年)**,连当前 build.sh 产出的 update.img 都
  **解析不了**,只报一句无信息量的 `Loading firmware failed!` ——
  与"文件不存在"的报错一模一样,极易误判成路径或镜像损坏(实际镜像 RKFW/RKAF 魔数、
  chip=3568、尾部 MD5 全部正确)
- `tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool` 是 **v2.17(2022)**,
  能正常加载并打印 `Support Type / FW Ver / FW Time / Loader ver`。`rkflash.sh` 指的就是这个路径
- 结论:命令行烧写一律用 v2.17 那个;v1.54 只留着给 ddrbin_tool 等其他子工具作伴
串口调试波特率 1500000,开机最早的 DDR training 打印可确认内存识别(类型/容量/rank)。

## 文档结构约定

> 本节是 `nvr-contracts/docs/doc-convention.md` 的副本(约定属多边,权威版在那里)。
> **要改约定先改权威版再同步回来**,只改这一份会让四个仓悄悄漂成四个版本。

### 放哪里

| 位置 | 内容 | 判据 |
|---|---|---|
| `README.md` | 仓库入口:这是什么、怎么跑起来 | 新人第一眼看的 |
| `CLAUDE.md` | 给 AI 的工作约定 | 本文件 |
| `docs/README.md` | 文档地图(见下) | 读者靠它决定翻哪份 |
| `docs/architecture.md` | 结构、原理,以及**什么不属于本仓** | 边界不写清楚,功能会长到错误的仓里 |
| `docs/<topic>.md` | 查阅类:接口、配置、schema | 干活时随时翻的 |
| `docs/modules/<pkg>.md` | 模块深度说明 | **仅当代码注释放不下时**才单开 |

### 文档地图不是文件清单

`docs/README.md` 是**导航**,不是 `ls` 的结果。每份文档至少标注三项:

| 列 | 说明 |
|---|---|
| 受众 | 谁会读它——本仓开发者 / 调用方 / 模型训练侧 / 运维 |
| 内容 | 一句话说清讲什么,让人能判断"是不是我要找的" |
| 权威性 | 是权威定义,还是引用他处;已知陈旧的必须直说 |

并且给出**按意图的阅读路径**,而不是让读者自己拼:

```
新人上手  README → architecture(先读边界一节)→ 跑一遍构建
改代码前  architecture 对应章节 → 该模块的代码注释(注释才是第一现场)
接接口    <topic>.md 的调用约定 → 头文件/契约文件
排障      运维类文档 → 对应模块注释
```

### 每份文档开头三行说清楚

1. **是什么**——一句话定位
2. **给谁看**——受众明确了,详略才有依据
3. **核验基线**——对照哪些代码、什么日期;没有基线的文档,读者无从判断它是否已在骗人

目标态设计稿必须在这里显式声明"不是当前实现",否则会被当成现状。

### 超过 200 行给阅读导航

长文档开头放一张「关注什么 → 看第几节」的表。读者带着具体问题来,
不该被迫从头读到尾。

### 正文怎么组织

**先边界后细节**。读者先得知道"这份文档/这个仓**不管**什么",才不会误用。
边界放在开头,不要藏在末尾。

**每节回答一个问题,标题就是那个问题**。「为什么网关校验放行链路本地」比
「网关校验」有用——前者让人一眼知道该不该读下去。

**表格优先于长段落**。并列关系(几种模式、几个字段、几条路径)一律用表,
可扫描;连续三段以上的散文说明,基本都能压成一张表。

**引用代码给到行**:`internal/network/configure.go:186`,不要只说"在 configure 里"。
读者要能一跳就到。

**决策要写代价**。只写"我们选了 A"没用,要写"为什么不是 B"和"A 的代价是什么"——
否则后人不知道这个选择还能不能改,只好原样供着。

### 契约放哪:先判断边数

只约束本仓的契约(接口 schema、配置格式、内部约定)放**本仓** `docs/`;
约束两个及以上仓、任一方单独改都会伤到另一方的,放 **nvr-contracts**——
它是多边契约的中立仓,改动要过双方都看得见的评审。

判据很简单:**这份东西改了,别的仓会不会挂?** 会,就是多边的。

### 命名

全小写 kebab-case + `.md`,`README.md` 是唯一例外。不用下划线、驼峰、中文。

### 就近原则

能写进代码注释的不要单开文档——注释紧挨定义,改代码时不会漏改;单独的文档会腐烂。
反过来说,内容塞得进头文件/包注释的,它就不该是一份文档。

### 过程性文档有生命周期

评审记录、迁移说明、排障记录、待办清单,完成后就删——它们会冒充现状文档误导后来人。
确需留作历史的,在文首标注「已归档,仅供追溯,不要据此开工」。

### 单一事实来源

同一事实只在一处权威定义,别处引用而不复制。已知非权威的文档必须在文首自我标注
(如「API 契约以 nvr-contracts/contracts/local-api/openapi.yaml 为准」)。

> 例外:`docs/` 下的 `Common/`、`Linux/`、`Others/`、`RK356X/` 与 Rockchip 原厂 PDF/PNG
> 是**厂商原始资料**,保持上游文件名不动(改名会丢失与官方文档的对应关系),
> 上面的命名规范只约束本项目自己写的文档(如 `nvr-edge-integration.md`)。
