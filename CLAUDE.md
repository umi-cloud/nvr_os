# nvr-os — RK3566 / RV1126B Linux SDK

主线是 RK3566。**RV1126B 工作已于 2026-10-21 停止**,文件保留备查:RV1126B 于 2026-09-16 接入,自研 SATA 版型 `rv1126b-nvr-sata-v1.0` 于 2026-10-21
按原理图建档,**真机未验**(此前验证软件栈用的 Luckfox Aura 开发板板型已同日删除,
实测结论保留在 git 历史与新板 dts 注释里)。单内核单 rootfs:
- `kernel/`:6.1.172(armbian 官方镜像 `rk-6.1-rkr7.2`,无需账号)。2026-10-21 由 `rk-6.1-rkr6.1`(6.1.118)升级,
  旧树原样备份在 `/data/backup/nvr-os-kernel-rkr61-20261021/`(含当时未提交改动的补丁与回退说明)
- rootfs:Debian 12 bookworm headless

由 BoardConfig 的 `RK_KERNEL_DIR=kernel` 指定(也是 build.sh 的默认值)。
目录原名 `kernel`,5.10 下线后于 2026-09-09 改回 `kernel`。**5.10 内核与 bullseye/linaro 用户环境已于
2026-09-08 下线**,同时删除的还有 dragon 板与四块 rk3568 EVB 板。归档见
`/data/backup/nvr-os-legacy-20260908/`(kernel 与 rkwifibt 的完整 git bundle + README)。

## GPU(Mali-G52 Bifrost)

- 内核配置**必须叠加官方芯片片段** `rk3566.config`(6.1 把 GPU 配置从 defconfig 拆了出来):
  `RK_KERNEL_DEFCONFIG_FRAGMENT="rk3566.config nvr.config"`。漏了会只编 mali400(Utgard),
  与 G52 不匹配 → 无 `/dev/mali0`、GLES/OpenCL 全废
- 用户态 libmali-bifrost-g52-**g24p0**-x11-wayland-gbm(同时支持 GBM/X11/Wayland),
  内核 kbase 为 **g29p1**(rkr7.2;rkr6.1 时为 g25p0),g52 没有 g29p1 配套用户态库,但 2026-10-21 实测
  g24p0 配 g29p1 可用(OpenCL 向量加法正确、EGL 1.5、GLES 3.2)。早先在 g25p0 上实测 EGL 1.5、GLES 3.2、OpenCL 3.0 全通过,
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
- GPU DVFS:200/300/400/600/700MHz simple_ondemand(800MHz 档被 rk3566-box.dtsi 删除)。rkr6.1 时
  rk356x.dtsi 留着表级 `rockchip,supported-hw` 却注释掉了每条 OPP 的 `opp-supported-hw`,板级 dts 曾补回掩码;
  rkr7.2 的 rk3566.dtsi 改为删掉表级属性,**板级 dts 不能再给 GPU OPP 带掩码**,否则 GPU 丢光 OPP、无 devfreq。
  dmc_opp_table 的掩码仍要留着(上游没动 dmc 表)

## 视频编解码(MPP + GStreamer)

- 组件版本(2026-09):**mpp 1.1.0**(`1:1.1.0-1`)、**librga 1.10.6**(`1:1.10.6-1`,上游只发预编译库,
  自写 debian/ 打包)、gst-rockchip 插件**保持 1.14-4 旧二进制**——同一份源码对 mpp 1.1.0 头文件重编后
  1080p I420 走 RGA 转换必失败(内核报 job_commit failed),旧二进制配新库反而正常,四种组合交叉验证过。
  重打 deb 的配方与这个坑见 `debian/pkgbuild/README.md`。
  验证基准(SATA 板,mpp 1.1.0):`mpi_enc_test` 720p H264/H265 报 87/84 fps(**旧 mpp 1.5.0 同一命令也是 87**,
  下面那条 285fps 是早期不同测法的数字,不要拿来对比),`mpi_dec_test` 720p H264 800+fps、H265 1270fps,
  gst 1080p I420 编→解闭环通过、RGA 0 报错。
  NPU:rknpu 驱动 0.9.8 + librknnrt 2.5.0(2026-10-21 由 2.3.2 升级,0.9.8 驱动下实测无版本警告);Mali kbase 已随 rkr7.2 到 g29p1,libmali 仍为 g24p0(实测可配)
- rootfs 内置 gst 1.22(tools/base/good)+ `gstreamer1.0-rockchip1` 插件:`mppvideodec` / `mpph264enc` /
  `mpph265enc` / `mppjpegdec|enc`,以及 kmssrc/rkximagesink;NVR 解码链示例:
  `rtspsrc ! rtph264depay ! h264parse ! mppvideodec ! kmssink`
- **版本陷阱**:mpp/gst 插件的 deb 必须用 bookworm 构建(packages/arm64 已换)。
  旧发行版构建版本号同为 1.5.0-1,但配 6.1 内核会在 MPP 层直接段错误
  (mpi_enc_test 都崩);版本号相同不代表构建相同,以实测为准
- **勿装 gstreamer1.0-plugins-bad 元包**(依赖链拖入 LLVM/GTK/flite 约 300M):
  h264/h265parse 与 kmssink 由构建脚本从 bad 的 deb 中定向抽取
- apt 包本地镜像:`packages/apt-mirror-bookworm/`(308 deb,141M,2026-10-21 联网重捕获,含 bookworm-security 截至当日的更新)。镜像非空时构建只用
  file:// 本地源(严格钉版、离线可建);要升级基础包版本,清空该目录联网重建一轮即自动重捕获
- 基准(实测):H264 硬编 720p 285fps/硬解 445fps;H265 硬编 113fps/硬解 712fps(720p),gst 1080p 闭环通过;快速自检
  `mpi_enc_test -w 640 -h 480 -t 7 -n 10 -o /tmp/s.h264` 应输出非零码流

## 硬件说明

**本板无 WiFi/BT/vfd 硬件**(dts 已禁用相关节点,内核裁剪 WLAN/BT 协议栈,rootfs 无相关组件)。

电源方案(无 SATA 板):无 I2C PMIC(i2c0 禁用是刻意的)——vdd_cpu/vdd_logic 为 PWM 调压 DC-DC
(800-1200mV,DVFS 有效),其余固定 LDO;SATA 板改用 RK809-5(vdd_cpu 仍 PWM 调压)。
NTP 源钉阿里云(`/etc/systemd/timesyncd.conf.d/10-nvr.conf`:`ntp.aliyun.com ntp1.aliyun.com`,
cn.pool 兜底)——Debian 默认池会先连试境外 IPv6 地址超时数轮,无 RTC 的板子这段时间只能用旧时间。
注意 ntp2~ntp7.aliyun.com 与 ntp.aliyun.com 是同一个 anycast 地址,列多个不增加冗余。
RTC:无 SATA 板无 RTC,靠 systemd-timesyncd clock file(每分钟落盘)恢复时间;
SATA 板**用外挂 HYM8563**(i2c1@0x51,CR1220 纽扣电池备电,rtc0,内核 hctosys/systohc 直接读写)。
2026-10-21 起从 RK809 内置 RTC 切过来:RK809 那颗**没有备电**,实测断电一夜读回出厂值 2017-08-04
(断电两分钟能撑住只是靠电容)。两颗同时注册时 RK809 作为 MFD 子设备先抢 rtc0,
`aliases { rtc0 = &hym8563 }` 无效,所以 nvr.config 关掉了 `CONFIG_RTC_DRV_RK808`。
新板 HYM8563 从没写过时间时读出 2000 年,NTP 对时后内核十几秒内自动写入。fake-hwclock 已从 rootfs 裁掉。
**DDR 调频(dmc)按板区分**:无 SATA 板开 auto-freq(324↔1056);**SATA 板 dmc 关闭、定频 1056**——
该板开调频后随机 Oops(非法指令/PID 1 段错误),panic 时 cur_freq 均为 324MHz,loader 降 780 无改善,
关 dmc 后 4 核+硬编压力与 memtester 1GB 全过。两板差异:无 SATA 板 dmc 的 center-supply 是 950mV 固定
`vdd_fixed`(调频不动电压),SATA 板是 RK809 `vdd_logic` 900mV(真调压)。恢复调频的路径写在 SATA dts 注释里。
TF 卡槽:**SATA 板没有**(2026-10-20 确认,产测不测 tf);无 SATA 板据早先记录有卡槽,待核实。
sdmmc0 两块板都保持启用(dwmmc "No normal pinctrl" 告警无害)。
USB:**OTG 口(fcc00000,usbdrd)只有 USB2**(box.dtsi 只接 u2phy0_otg、maximum-speed=high-speed,nvr dts 改为 host),
插 USB3 U 盘也只跑 480M;**USB3 是 usbhost30(fd000000,combphy1)那个口**。产测 usb3 项要求 U 盘插在后者
**adc-keys 已禁用**:box-demo 参考设计声明了 volume up/down 两个按键,本板没有,而该节点
每 100ms 轮询一次 saradc 找按键(实测约每秒 10 次中断)。关掉后 saradc 无消费者,不再周期唤醒。
看门狗 /dev/watchdog0 可用,**nvr-edge 需实现喂狗**。

已完成:librknnrt 2.5.0(配 rknpu 0.9.8);首块板整机点亮验证(eMMC/网口/加速全家/分区自适应);
开机 logo 全程无缝(u-boot drm-logo 预留区页对齐 + 360px um 标志;2026-09-16 换树后
该对齐由上游 `align_size = PAGE_SIZE` 提供,不再是本仓补丁);
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
  ⚠ **写入命令的退出码不可信**:原厂 `external/rktoolkit/vendor_storage.c` 的 main() 丢掉了
  `vendor_storage_write()` 的返回值(第 447 行调用后直接 `return 0`),`vendor_storage -w` 无论成败
  都退出 0,靠 `set -e` 挡不住。`nvr-provision` 因此在写完后**回读逐字段比对**,不一致即退出非零,
  产线工装应据退出码拦机。样机上实测过这个坑:MAC 有值而 SN 一直是空的,旧版脚本照样打印
  「已写入」并退出 0(`/proc/device-tree/serial-number` 那时回落到 SoC 芯片 ID)。
  SN 16 位、`UMNVR3566` 开头;u-boot 下次启动把 SN 注入 `/serial-number`(nvr-edge/vsync 的设备 SN),
  MAC1 注入 gmac1(dts 别名 `ethernet0`,因此网口名是 **end0**);MAC2 给 USB 网口(r8152 无 EEPROM,
  开机随机):`nvr-usb-eth-link` 按 vendor 区生成 `/etc/systemd/network/20-usb-eth.link`,由 udev 在网卡
  出现、尚未 UP 时套上,**写文件后下次开机生效**。不要在运行中改 r8152 的 MAC(曾间歇性 Tx timeout
  卡死并冻结整机网络)。Debian 的 `73-usb-net-by-mac.link` 会抢先匹配 USB 网卡、盖掉 persistent 策略,
  这就是它原来每次开机 MAC 都变的原因。工具是官方
  `external/rktoolkit/vendor_storage.c`,构建期交叉编译进 `/usr/local/sbin`。**upgrade_tool 只能写 SN 不能写 MAC**
- **产测 `nvr-factory`**(单板自动测试 + 扫码写号 + 120 分钟老化 + 组装后自动收尾;人工项未做):
  开机由 `nvr-factory-stage.service` 读 vendor 区阶段标记(`VENDOR_CUSTOM_ID_20`):空且无 SN → 单板测试,
  `pcba-pass` → **老化**(`AGING_MINUTES` 默认 120 分钟,3 路 memtester + NPU + 硬编码循环满载,每 10 秒巡检,
  任一路报错或温度超 `AGING_THERMAL_MAX_C` 判失败;**必须一次开机连续跑满,中途断电下次从零重来**,
  因为只有跑满才写 `aging-pass`),`aging-pass` → **组装后上电即自动收尾**(不快检不扫码,清现场、
  阶段 → `shipped`,然后**重启**而非关机:组装工位若没上过电,第一次上电的就是用户)→ 正常启动;
  ssh 手动 `nvr-factory finish` 仍默认关机。收尾清空 machine-id,DHCP 客户端标识随之变化,IP 会变;
  **产测期间 getty@tty1、nvr、vsync 都不启动**(drop-in 条件)。
  **工作灯约定**(板上只有工作灯 GPIO0_C3 可控,另一颗蓝灯 LED1 直接接 3.3V 是电源灯):单板测试中快闪、
  老化中心跳闪、通过常亮、任何一步失败慢闪(1 秒)。老化架无显示器,只看这颗灯
  ⚠ **开发板影响**:新刷机、没写过 SN 的板子开机会进产测、nvr-edge 不起来,开发时
  `nvr-factory stage set shipped` 后重启;产测上线前已写过 SN 的板子不受影响。RV1126B 等未适配板型直接正常启动。
  **运行时输出一律英文**(fbcon 只有西文字形;注释仍用中文)。tty1 顶部彩色结论栏 + 全部测试项与测量值,
  内核只编 16x32 字体使 1080p 下可读(720p 一屏 22 行,SATA 板 13 项占 20 行,再加项要换布局)。
  ⚠ tty1 画面依赖 nvr.config 2026-10-20 补的 `CONFIG_FB`/`DRM_FBDEV_EMULATION`:此前内核 FB 未开,
  FRAMEBUFFER_CONSOLE 被 Kconfig 静默丢弃,HDMI 在内核起来后**没有任何画面**(只有 u-boot logo,且仅当开机时已接显示器)
  **启动期间 HDMI 只显示 logo**:bootargs 不带 `console=tty1`(内核日志、systemd 启动状态只走串口),
  且开 `FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER`,fbcon 等 tty1 第一次有文字(约 10 秒处 getty 登录提示,
  或产测画面)才接管屏幕。SATA 板实测通过(2026-10-20)。开机时没接显示器则 u-boot 不出 logo,之后接上只见登录提示
  ⚠ **HDMI 固定输出 RGB**(公共 dts 的 `&hdmi { force_output_bus_format_RGB; }`):新树 u-boot 在显示器支持
  YCbCr444 时默认输出 YUV444,内核接管 logo 沿用它,与内核默认的 RGB 对不上,黑底显示成紫色
  (2026-10-21 实测)。该属性只有 u-boot 读(u-boot 用的是内核 dtb),内核默认就是 RGB
  ⚠ 只往 tty1 写字不够:fbcon 接管时的普通提交替换不掉 logo 图层,画面会停在 logo 上(getty 能切过去是因为
  它把终端重置回文本模式)。`nvr-factory` 的 `fb_show` 用 perl 发 KDSETMODE 图形→文本触发强制提交,其他要上屏的程序照此处理
  **写号用扫码枪插主板**:主板贴预印条码(SN + 两个 MAC,条码里先 MAC1 千兆、后 MAC2 USB 网口),单板全过后
  屏幕提示扫码,`nvr-factory` 从 tty1 读一行、严格解析(对不上的片段整条拒绝,提示重扫)后调 nvr-provision。
  不能防重号(板子看不到别的板)。真实条码格式待拿到标签核对;带 `MAC1:` 之类文字前缀的格式目前会被拒。
  明细 JSON 在 `/run/nvr-factory/`,ssh 上也可调 `nvr-factory result/provision/finish`。
  屏幕与工作灯只在产测模式(`/run/nvr-factory/active` 存在)下才动:出厂后 ssh 调 `nvr-factory test`
  排查问题不会弄乱用户的 HDMI 画面和灯
  写号只认本次开机**完整跑完且无跳过项**的 PASS。判定阈值在 `/etc/nvr/factory.conf`(DDR 容量等待按 BOM 校准)。
  npu 项依赖构建时从 `external/rknpu2`(不入库)取头文件与 mobilenet 模型编出 `npu-check`,缺则该项判失败。
  2026-10-20 在 SATA 板(4GB/64G eMMC,9 月 9 日内核)上从 /tmp 跑过 `test`:board/ddr/emmc/eth/usbeth/rtc/
  npu/venc/thermal/watchdog 通过,单板约 75 秒(memtester 占 60 秒);旧版 mobilenet 模型在 librknnrt 2.3.2/2.5.0 上均可用,
  单次推理约 5ms。sata/usb3/tf/hdmi 因没接工装盘、U 盘、TF 卡、显示器判失败,**这四项的通过路径未验证**。
  阶段切换、systemd 单元、tty1 画面、写号与 finish 只在开发机上用替身跑过,未上板
- **主机名** `UMI-<SN 后 6 位>`(`nvr-hostname.service` 每次开机幂等):两块板同名时路由器按主机名派同一 IP
- **两个网口都走 DHCP,千兆 end0 优先**(`08-usb-eth.network` metric 2000,`10-lan.network` metric 100):
  两口同网段时内核只看 metric,相同会把 RTSP 和默认出口压到 100M 的 RTL8152 上(实测踩过)。
  **USB 口按 `Driver=r8152` 匹配且文件名排在前面**(networkd 取字典序第一个匹配的 .network):
  接口名不是稳定契约,USB 网卡现在叫 eth1 只是因为 udev 没为它生成基于路径的名字;换 USB 口
  或换版 systemd 都可能变成 `en` 开头,那样会被 `Name=en*` 抢走、拿到 metric 100 与千兆口并列。
  **千兆口只能按名字匹配**:udev 不给 stmmac 平台网卡上报 `ID_NET_DRIVER`(`ethtool -i` 报
  `st_gmac`,`udevadm info` 里没有该属性),写 `Driver=` 匹配不上 → 网口拿不到任何配置、没有
  DHCP。改这两份配置前先在板上核对 `networkctl status`。`05-` 前缀留给 nvr-edge 运行时写的
  网卡配置,优先级高于出厂这两份
- **RPS 收包分流**(`nvr-net-tuning.service`,`rps_cpus=0xe`):GMAC 只有一个 RX 队列,中断固定
  落在 CPU0,不开 RPS 时从软中断到 TCP 协议栈整条收包路径都挤在这一个核上(实测 NET_RX 软中断
  CPU0 1050 万次、其余三核各约 38 万)。4~6 路 RTSP over TCP 全走这条路,CPU0 先到顶。
  掩码留出 CPU0 给硬中断与 NAPI,和 IRQ 抢同一个核会互相打断
- **网口灯**:RTL8211F LCR 由 PHY 节点 `realtek,led-lcr` 指定(stmmac 的 led_fixup 原来写死 0xc160),
  NVR 板取 0xc20b(LED0 常亮 link,LED1/LED2 收发闪烁),两颗灯都闪、没有常亮则改回 0xc160
- **ssh host key 首启生成**:镜像不带 host key,`nvr-ssh-hostkeys.service` 首启 `ssh-keygen -A`,每台设备
  各不相同。代价是每刷一次固件 known_hosts 都会报 key 变化,开发期用 `-o StrictHostKeyChecking=no` 即可
- **machine-id 出厂为空**(构建期 `: > /etc/machine-id`,`/var/lib/dbus/machine-id` 软链过去):
  0 字节是 systemd 约定的首启标记,PID 1 开机自行生成。**不清空则全部设备共用一个 id**,而
  systemd-networkd 的 DUID 默认由它派生(实测清空前后 `DUID-EN/Vendor` 确实随之改变),
  DHCPv6 靠 DUID 认设备会撞车,D-Bus 与 journald 的机器身份也重复。
  连带必须 `systemctl mask systemd-firstboot.service`:空 machine-id 会让它的
  `ConditionFirstBoot=yes` 成立,而它的命令是 `--prompt-locale --prompt-timezone
  --prompt-root-password`,会在串口上等人输入、卡死启动
- **系统自愈与收敛**(overlay-nvr/etc/systemd):PID 1 喂硬件看门狗(`RuntimeWatchdogSec=30s`,内核或
  PID 1 卡死 30 秒自动复位;nvr-edge 自己的喂狗仍待做);journald 封顶 64M;apt-daily/e2scrub/dpkg-db-backup
  定时器已 mask,adbd 已关(USB 是 host 模式);根分区 noatime。板上常驻服务 13 个,启动 8 秒
- **命名陷阱(勿按名字误删)**:`debian/linaro-rootfs.img` 沿用 linaro 时代命名,内容实为 **bookworm**,
  是 `rockdev/rootfs.img` 的真正来源(`mk-image.sh` 硬编码此输出名);`debian/binary/` 是
  bookworm 脚本的 `TARGET_ROOTFS_DIR`。`overlay/`、`overlay-firmware/`、
  `overlay-debug/` 是 Rockchip 原始素材,bookworm 构建脚本按需取用后再裁剪
  (如 overlay-firmware 是全量 linux-firmware,复制后只留 rockchip),**不要按名字误删**
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

- 选板:`./build.sh lunch`,配置文件在 `device/rockchip/rk356x/BoardConfig-*.mk` 与 `device/rockchip/rv1126b/BoardConfig-*.mk`,选中后软链到 `device/rockchip/.BoardConfig.mk`
- ⚠ 切板与构建要分两条命令:`build.sh` 启动时就 source 了板级配置,
  `./build.sh <BoardConfig>.mk uboot` 会用**切板前**的配置去编,编出来的是上一块板的固件
- 区分逻辑:芯片级(`RK_UBOOT_DEFCONFIG`、rkbin loader)/ 板级(`RK_KERNEL_DIR` 选内核树 + `RK_KERNEL_DTS`,核心)/ 系统级(rootfs、分区表 parameter)
- 现有板子(RK3566 两块 + RV1126B 两块,`rk356x/BoardConfig.mk` 默认项已改指 SATA 板):
  - `BoardConfig-rk3566-nvr-ddr3-v1.0.mk`:NVR 无 SATA 板(硬件同为 V1.0,旧命名 v10 已统一为 v1.0),单网口(千兆 gmac1),8颗 8bit DDR3,**kernel** + DTS `rk3566-nvr-ddr3-v1.0`(override 风格,基于官方 box-demo dtsi,含电源域 1.8V/RGMII 时延等实板参数)+ defconfig 片段 `nvr.config`
  - `BoardConfig-rk3566-nvr-ddr3-sata-v1.0.mk`:NVR SATA 板(原理图 UMI-NVR-RK3566-V1.0),双网口(千兆 gmac1 + 板载 USB 百兆 RTL8152,见下文网口章节),DTS `rk3566-nvr-ddr3-sata-v1.0` include 无 SATA 板 dts 只维护差异:SATA 硬盘位(sata2/combphy2,combphy1 保留 USB3 host)、RK809-5 PMIC(box.dtsi 占位 regulator 删除后按原 label 重建,vdd_cpu 仍 PWM 调压)、HYM8563 RTC、RK809 codec 声卡;内核配置与无 SATA 板完全一致
  - `rv1126b/BoardConfig-rv1126b-evb1-v10.mk`:RV1126B 官方 EVB1 V10 标准配置,DTS `rv1126b-evb1-v10`
    (官方树自带),内核 defconfig `rv1126b_defconfig`。**仅验证到能编出 uboot.img 与 boot.img**,
    rootfs/固件打包与真机启动都未做;`RK_CFG_BUILDROOT`/`RK_CFG_RECOVERY` 留空(buildroot 无 rv1126b 配置)
  - `rv1126b/BoardConfig-rv1126b-nvr-sata-v1.0.mk`:NVR RV1126B SATA 板(原理图 UMI-NVR-RV1126B-V1.0,2026-10-21 建档,
    **真机未验**)。DTS `rv1126b-nvr-sata-v1.0`(独立 dts 不 include EVB dtsi,电源树照官方 EVB1 V12:
    CPU PWM 调压 + RK801 PMIC 供 NPU/LOGIC/DDR/1V8/3V3)+ 片段 `rv1126b-nvr.config`(在 Aura 片段基础上加
    SCSI/USB 存储/UAS、RTL8152、motorcomm/realtek PHY、gpio-leds)。
    硬件:LPDDR3、eMMC 系统盘、SoC 内置 RTC(CR1220 备电)、千兆 RGMII(YT8531C/RTL8211F 二选一,
    **M1 引脚组**,PHY 25M 由 SoC 输出,复位 GPIO5_B4)、USB 百兆 RTL8152B。
    **RV1126B 无原生 SATA**:硬盘走 JMS578 USB3-SATA 桥——SS 对接 dwc3(固定 host,USB2 对接 PL2586 hub,
    hub 下游 2 个 USB-A + RTL8152B),JMS578 的 USB2 对接 EHCI 作降级。盘在系统里是 USB(UAS)盘,
    产测的 sata 项与 nvr-edge 挂盘逻辑若按 /dev/sda 的 SATA 属性判断需适配。
    灯:work-led GPIO5_D7(低有效,产测用)、power-led GPIO5_D6(回路经硬盘 DAS 脚,不插盘不亮)。
    无 SD 卡槽、无 USB-C 下载口(MaskRom 烧录)、音频与 WiFi 模组位未配。
    **上板待办**:RGMII 时延标定(现为 EVB 值,Aura 上这组值丢包 25%)、LED/PHY 复位极性、DAS 空闲电平
- ⚠ **两块板的固件不通用,烧前先确认 `.BoardConfig.mk` 软链指向哪块**。SATA 板 dts 会
  `/delete-node/` 掉 `vcc_1v8`/`vcc_3v3` 等固定 regulator,改由 i2c0 上的 RK809 提供;
  这份固件烧到无 SATA 板上,PMIC 不存在 → regulator 全缺 → `pmu_io_domains` 配不起来 →
  **网口不通、拿不到 IP**(实际踩过)。反向(无 SATA 固件烧 SATA 板)则丢 SATA 盘与 RTC。
  换板后必须重编内核:`./docker/run.sh ./build.sh kernel` 再 mkfirmware/updateimg;
  rootfs 两块板共用,不必重建。快速自检:反编译 dtb 看 `rk809` 节点数,无 SATA 板应为 0。
  两块板的 dts 与 BoardConfig 直到 2026-09 才补入库(此前只有旧名 v10 在库里),改完记得 `git status`
- DDR 类型由 rkbin 闭源 blob 自动识别(DDR3/DDR4/LP4X 同一 blob),换内存不改源码;调参用 `rkbin/tools/ddrbin_tool`

## git 仓库结构(重要)

- **单仓**:2026-09-09 由 Rockchip repo 多仓库结构收敛而来,各子目录的 `.git` 已拆除,内容直接入本仓;
  远端 `git@github.com:umi-cloud/nvr_os.git`,在 `main` 上开发。原子仓的独立历史备份在
  `/data/backup/nvr-os-subrepos-20260909/`(git bundle);`.repo/` 已于 2026-10-21 删除(拉不到任何东西)
- 不入库(`.gitignore`):`buildroot/output/`、`buildroot/dl/`、`rockdev/`、`prebuilts/gcc/`、
  `debian/overlay-firmware/`、`debian/*.tar.gz`、`external/` 下的大件等,清单见 README「最小可构建集」;
  内核与 u-boot 的构建产物由各自 `.gitignore` 排除
- **改了 SDK 里的文件,同步更新 [`docs/nvr-customizations.md`](docs/nvr-customizations.md)**:
  单仓里没有原厂基线可 diff,那份清单是唯一能分辨"哪些是我们改的"的地方
- 与官方基线对比:内核浅克隆 armbian `rk-6.1-rkr7.2` 按 `git ls-files` 逐文件比对;rkbin 对照
  rockchip-linux/rkbin 的 GitHub 镜像(做法见 docs/nvr-customizations.md 上游更新状态一节)
- 5.10 内核及 libmali/rkwifibt/rkaiq/chromium/xserver 等老组件已随 2026-09-08 下线删除,需要时从
  `/data/backup/nvr-os-legacy-20260908/` 的 bundle 还原,或从 Rockchip 官方重新获取
- 换下来的旧内核树、烧写前的板子备份:`/data/backup/nvr-os-kernel-rkr61-20261021/`、
  `/data/backup/nvr-os-sata-board-flash-backup-20261021/`

## 分区(NVR 两块板共用 parameter-nvr.txt)

uboot 4M / misc 4M / **boot 128M** / recovery 64M / **rootfs 5G** / **userdata 10G** / **vcache:grow**。
无 SATA 板与 SATA 板共用同一张表,改一处两块板同时生效(vcache:grow 自适应不同 eMMC 容量)。
实测样机 eMMC 为 **32G**(29.12 GiB 可用),vcache 实得 13.9G;换 64G/128G eMMC 只有 vcache 变大。
容量依据(实测):rootfs 出厂占用约 1.1G(/usr 1.1G 是大头,含 libmali/WPE/ffmpeg/思源黑体),
5G 余量充足;userdata 现用不到 1G,10G 为应用数据(模型、录像索引等)预留。
rootfs.img 本身只有 867M,fstab 的 `x-systemd.growfs` 每次开机在线扩到分区大小(已满时毫秒级空操作),
改分区不必重建 rootfs。userdata、vcache 不烧镜像,fstab 的 `x-systemd.makefs` 在分区无文件系统时自动
mkfs.ext4,按 PARTLABEL 挂到 `/userdata`、`/vcache`。(原自写的 format-data-parts 脚本已删除)
改分区表必须整机重烧。

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

遵循 [共享文档约定](../nvr-contracts/docs/shared/doc-convention.md)。历史资料集中于 `nvr-contracts/archive/<project>/`；新增已完成的过程记录应及时归档，现行文档只维护有效说明与未完成事项。
