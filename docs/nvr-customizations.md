# NVR 定制清单

**是什么**：本仓相对 Rockchip 原厂 SDK 改了哪些文件、为什么改。

**给谁看**：接手本仓的开发者。SDK 有十一万多个文件,其中属于本项目的约一百个,
这份清单让人知道该看哪些、哪些是原厂的不要动。

**核验基线**：kernel 于 2026-10-21 对照 armbian `rk-6.1-rkr7.2`(c983fbbf8);其余 2026-09-09,
其余子仓的原厂分支(备份在 `/data/backup/nvr-os-subrepos-20260909/`)。

## 为什么需要这份清单

本仓原为 repo 多仓库结构,每个子仓有 `nvr-custom` 分支,一条
`git diff <原厂基线> nvr-custom` 就能看出改了什么。2026-09-09 收敛为单仓后,
原厂代码与定制改动在同一个提交里落地,仓库内部**不再有基线可 diff**,
只能靠这份清单。改了 SDK 里的文件请同步更新这里。

## 内核(kernel/)

原厂基线 armbian `rk-6.1-rkr7.2`(c983fbbf8),6.1.172。2026-10-21 由 `rk-6.1-rkr6.1`(6.1.118)整树替换,
我们的改动原样带过来,另删掉了 GPU OPP 掩码(见上游更新状态一节)。只动了 10 个文件:

| 文件 | 性质 | 说明 |
|---|---|---|
| `arch/arm64/boot/dts/rockchip/rk3566-nvr-ddr3-v1.0.dts` | 新增 | 无 SATA 板设备树,override 风格基于官方 box-demo dtsi |
| `arch/arm64/boot/dts/rockchip/rk3566-nvr-ddr3-sata-v1.0.dts` | 新增 | SATA 板,include 上一份只维护差异 |
| `arch/arm64/configs/nvr.config` | 新增 | defconfig 片段,与官方 `rk3566.config` 叠加使用;2026-10-21 起 device-mapper 核心内置(`BLK_DEV_DM`、`DM_UEVENT`,不开具体 target) |
| `arch/arm64/boot/dts/rockchip/rv1126b-nvr-sata-v1.0.dts` | 新增 | RV1126B NVR SATA 板(UMI-NVR-RV1126B-V1.0),独立 dts 不 include EVB dtsi;2026-10-21 建档,真机未验 |
| `arch/arm64/configs/rv1126b-nvr.config` | 新增 | RV1126B 板级片段,叠加在官方 `rv1126b_defconfig` 上(USB 存储/UAS、RTL8152、PHY、LED、MPP、容器) |
| `arch/arm64/boot/dts/rockchip/Makefile` | 修改 | 加入 `rv1126b-nvr-sata-v1.0.dtb`(原 Luckfox Aura 条目已随该板型删除) |
| `drivers/net/ethernet/stmicro/stmmac/stmmac_main.c` | 修改 | RTL8211F 网口灯 LCR 原来写死 0xc160,改为读 PHY 节点的 `realtek,led-lcr` |
| `logo.bmp` / `logo_kernel.bmp` | 替换 | 开机 logo |
| `.gitignore` | 修改 | 排除构建产物 |

两份 dts 里的关键决策都写在注释里:DDR 定频与 dmc 关闭的实验记录、
RK809 与 HYM8563 的 RTC 取舍、电源域、RGMII 时延、ISP/CSI 链禁用、adc-keys 禁用。

## rootfs(debian/)

| 路径 | 性质 | 说明 |
|---|---|---|
| `mk-rootfs-bookworm.sh` | 新增 | bookworm rootfs 构建脚本,debootstrap 直建,不用 linaro 基底 |
| `overlay-nvr/` | 新增 | 本项目应用层,42 个文件,见下表 |
| `nvr-factory/npu-check.c` | 新增 | 产测 NPU 自检源码,构建时交叉编译进 `/usr/local/lib/nvr-factory/` |
| `pkgbuild/` | 新增 | mpp/librga 的 bookworm arm64 打包配方与踩坑记录 |
| `authorized_keys` | 新增 | 设备专用 ssh 公钥,构建时装入 `/root/.ssh/` |
| `packages/` | 增删 | 换成 bookworm 构建的 deb;`packages/apt-mirror-bookworm/` 是本地 apt 快照 |
| `mk-image.sh` | 修改 | 配合 bookworm 输出 |
| `mk-rootfs-bullseye.sh` 等 | 删除 | bullseye 时代脚本,2026-09-08 下线 |

`overlay-nvr/` 的内容:

| 文件 | 作用 |
|---|---|
| `usr/local/bin/nvr` | 引导器,从可写的 `/userdata/nvr/bin/` 启动主程序并组装参数 |
| `usr/local/bin/vsync` | vsync 引导器 |
| `usr/local/lib/nvr/nvr-edge` + `VERSION` | 出厂基线主程序与版本记录 |
| `usr/local/lib/vsync/vsync` | vsync 出厂基线 |
| `usr/local/sbin/nvr-provision` | 产线写 SN 与两个 MAC 到 vendor storage |
| `usr/local/bin/memtester` | 取自 Rockchip `overlay-debug`(4.5.0),产测 ddr 项与老化要用;rootfs 改 release 构建后不再带 overlay-debug |
| `usr/local/sbin/nvr-factory` + `usr/local/lib/nvr-factory/` | 产测:按 vendor 区阶段标记决定开机行为,单板自动测试、tty1 显示、写号与出厂收尾 |
| `etc/nvr/factory.conf` | 产测判定阈值 |
| `usr/lib/systemd/system/*.service.d/10-nvr-factory.conf` | 产测期间不启动 getty@tty1、nvr、vsync |
| `usr/local/sbin/nvr-usb-eth-link` | 按 vendor 区第二个 MAC 生成 USB 网口的 `.link` |
| `usr/local/sbin/nvr-hostname` | 主机名设为 `UMI-<SN 后 6 位>` |
| `usr/local/sbin/nvr-net-tuning` | 开启 RPS,把收包处理摊到 CPU0 之外 |
| `usr/lib/systemd/system/*.service` | 上述脚本的 unit,以及 nvr/vsync 主服务 |
| `etc/nvr/` | MQTT CA 证书与两个组件的环境变量 |
| `etc/systemd/system.conf.d/10-nvr-watchdog.conf` | PID 1 喂硬件看门狗,30 秒 |
| `etc/systemd/journald.conf.d/10-nvr.conf` | 日志封顶 64M |

`nvr.service` 的沙箱配置与 nvr-edge 的行为强耦合(`ProtectSystem=full` 下靠
systemd-run 代执行挂盘与写网络配置),改之前先读该文件的注释。

## 板级配置(device/rockchip/)

| 文件 | 说明 |
|---|---|
| `rk356x/BoardConfig-rk3566-nvr-ddr3-v1.0.mk` | 无 SATA 板 |
| `rk356x/BoardConfig-rk3566-nvr-ddr3-sata-v1.0.mk` | SATA 板,`BoardConfig.mk` 默认指向它 |
| `rk356x/parameter-nvr.txt` | 两块板共用的分区表 |
| `rv1126b/BoardConfig-rv1126b-evb1-v10.mk` | 新增,RV1126B EVB1 V10 官方标准配置,用于打通构建链 |
| `rv1126b/BoardConfig-rv1126b-nvr-sata-v1.0.mk` | 新增,RV1126B 自研 SATA 板(双网口,SATA 走 JMS578 USB3 桥);2026-10-21 替代 Luckfox Aura 开发板板型 |
| `rv1126b/parameter-nvr.txt` | 软链到 `rk356x/parameter-nvr.txt`,与 rk3566 共用分区表 |
| `rv1126b/parameter.txt`、`boot.its`、`boot4recovery.its` | 取自官方 rv1126b SDK,未改 |
| `common/build.sh` | rootfs 改为 `VERSION=release` 构建(原 debug,会带 overlay-debug 的 rockchip-test、demo 与测试视频);`updateimg` 打包前核对 loader/u-boot 芯片、boot.img 板型、parameter 与 rootfs 模块 |

其余 BoardConfig 与 `parameter-buildroot-*` 已于 2026-09-08 随旧板下线删除。

## 其他

| 文件 | 说明 |
|---|---|
| `tools/linux/Linux_Pack_Firmware/rockdev/rk356x-nvr-package-file` | update.img 打包清单,`build.sh updateimg` 依赖 |
| `tools/linux/Linux_Pack_Firmware/rockdev/rv1126b-package-file` | 新增,rv1126b 打包清单(暂不含 oem/userdata) |
| `u-boot/` | 2026-10-23 整棵换为 Rockchip 上游 `github.com/rockchip-linux/u-boot` next-dev **锁定在 `1c535d65b8`(2026-07-28)**,不自动跟进。next-dev 是原厂开发主线(SDK 发布包即其快照),此提交未经原厂发布测试,靠本项目上板验证兜底:2026-10-23 在 RK3566 SATA 板上验证启动、开机 logo 交接内核、HDMI 固定 RGB、SATA、双网口、reboot loader 与产测各项均正常(RV1126B 只编译通过)。相对此前的 rv1126b SDK(2025-06-20)多出 A/B 修复、RK3566 访问 AHCI 卡死修复、2026-03 批量 CVE 补丁与 RV1126B 大内存/温度驱动等;旧树备份在 `/data/backup/nvr-os-uboot-rv1126bsdk-20261023/`。除 `.gitignore` 追加 `/*.bin.digest`、`/*.bin.gz` 外为纯原厂 |
| `buildroot/fs/cpio/cpio.mk` | 一处改动 |
| `docs/nvr-edge-integration.md` | rootfs 对下发组件承诺的 ABI 面 |
| `docker/` | 编译环境,Dockerfile 与 run.sh,宿主机缺依赖必须走它 |
| `release.sh` | 新增,出货固件唯一入口:加锁、切板、全量重编、核对后按板型出包到 `rockdev/<板型>/` |
| `CLAUDE.md` / `README.md` | 工作约定与仓库说明 |

`rkbin/` 的唯一提交是原厂的 checkpatch 脚本改动,不是本项目的。

## 上游更新状态

核验日期 2026-10-21(上次 2026-09-09);同日已升级 librknnrt、RK3566 启动固件(DDR/BL31/BL32)与 Debian 安全更新,内核按决定不升。查法:内核看 armbian/linux-rockchip 各分支 Makefile;
用户态库看 rockchip-linux/mpp、airockchip/librga、airockchip/rknn-toolkit2、JeffyCN/mirrors(libmali)
与 tsukumijima/libmali-rockchip;启动固件看 **rockchip-linux/rkbin 的 GitHub 公开镜像**(不需要 Gerrit
账号,上次记成"拉不到"是错的);Debian 对比 bookworm-security 的 Packages 与 rootfs 的 dpkg status。

| 组件 | 当前 | 上游最新 | 结论 |
|---|---|---|---|
| kernel | **6.1.172(rk-6.1-rkr7.2,2026-10-21 升级)** | 6.1.172;另有新分支 rk-6.12-rkr1 = 6.12.69 | 已升 rkr7.2,见下。两个新分支都有 rk3566 与 rv1126b,rknpu 均为 0.9.8,Mali kbase 均为 g29p1 |
| mpp | 1.1.0 | 1.1.0(develop 比它多 57 个提交) | 已是最新 tag |
| librga | 1.10.6 | 1.10.6_[3](仓库最后提交 2026-06) | 无新版本 |
| librknnrt | **2.5.0**(2026-10-21 升级) | 2.5.0 | 已升。SATA 板实测:0.9.8 驱动下无版本警告,产测模型输出一致,单次推理 5.1→4.7ms;rknn_server 同步换 2.5.0 |
| rknpu 驱动 | 0.9.8 | 随内核 | rkr7.2、6.12 里仍是 0.9.8 |
| libmali | g52-g24p0 | g52 仍只有 g13p0、g24p0 | 没有与 g29p1 配套的用户态库,升内核前要先验证 g24p0 配 g29p1 kbase |
| gst-rockchip 插件 | 1.14-4 | 按分支发布 | **刻意钉住**,重编后 1080p I420 走 RGA 必失败 |
| RK3566 DDR 初始化 | **v1.26**(2026-10-21 升级) | v1.26 | 已升,SATA 板串口确认生效。 修复多为 LPDDR4/4X/DDR4;v1.26 有一条通用的"概率性启动异常"修复;没有针对 DDR3 低频稳定性的修复,对 SATA 板 dmc 问题估计无帮助 |
| SPL / usbplug | v1.14 / v1.17 | v1.14 / v1.17 | 已是最新 |
| BL31 | **v1.46**(2026-10-21 升级) | v1.46 | 已升,只修 dmcinfo 接口取容量 |
| BL32(OP-TEE) | **v2.18**(2026-10-21 升级) | v2.18 | 已升,安全补丁、安全存储异常掉电恢复、PKCS11 修复 |
| RV1126B 启动固件 | DDR v1.03 / SPL v1.03 / BL31 v1.07 | DDR v1.10(lp4x tb 版)/ SPL v1.06 / BL31 v1.13 | 有更新,随 RV1126B 自研板选型时一并评估 |
| u-boot | rv1126b SDK 2025-06 树 | 未查 | 2026-09-16 换树,见上表 |
| Debian 基础包 | 12.15,apt 快照 **2026-10-21** 重捕获 | 12.15 | 已升:13 个安全更新(openssl/libssl3、libexpat1、liblzma5、libpcre2、libpng16、libssh2、perl-base、ca-certificates、tzdata、gstreamer base/good 等)全部进镜像;gstreamer 1080p I420 经 RGA 闭环复测通过。构建脚本补了 `apt-get upgrade`,否则 debootstrap 基底里的包清空快照也升不上去 |

**rkr7.2 升级(2026-10-21,先在临时目录做可行性验证,随后整树替换仓库 kernel/ 并在 SATA 板复测)**:
- 我们对内核的全部改动(与上游 rkr6.1 逐文件比对):两份 RK3566 dts、`nvr.config`、`stmmac_main.c` 一个函数、两张 logo,
  另有 RV1126B 的 dts/config/Makefile 条目(RV1126B 工作已停)。移植到 rkr7.2:
  - `stmmac_main.c` 补丁直接打上(偏移 143 行),网口灯 `lcr=0xc20b` 生效
  - **必须删掉** rk3566-nvr-ddr3-v1.0.dts 里给 `gpu_opp_table` 补的 `opp-supported-hw`:rkr7.2 的 rk3566.dtsi
    已删表级 `rockchip,supported-hw`,再带掩码会让 GPU 丢光 OPP、无 devfreq;删后恢复 200~700MHz simple_ondemand。
    `dmc_opp_table` 的掩码仍需保留(上游没动 dmc 表)
- 结果:启动、产测 11 项(无工装盘与 U 盘的 sata/usb3 未测)、RGA 闭环(驱动 v1.3.13)、HDMI RGB、控制台延迟接管、
  HYM8563、NPU 全部正常;**libmali g24p0 配 kbase g29p1 实测可用**(OpenCL 向量加法正确、EGL 1.5/GLES 3.2,重复 3 次);
  eMMC 读速与旧内核持平(~150MB/s),新驱动初始化时多 3 行 "Can't reduce the clock below 52MHz" 提示,无影响
- 未做:120 分钟老化、无 SATA 板验证、内存调频(无 SATA 板)在新内核上的表现

可做的升级按代价从小到大:rootfs 安全更新(重建 rootfs)< librknnrt 2.5.0(换一个 .so,已上板验证)
< BL32/BL31/DDR(重打 loader 与 trust,需整机重烧并复测启动)< 内核 rkr7.2 或 6.12(`stmmac_main.c`
等改动要重新适配、两份 dts 要验证、libmali 配对要确认,整机重新点亮与浸泡)。内核仍建议留到量产冻结前再做。
