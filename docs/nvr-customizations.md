# NVR 定制清单

**是什么**：本仓相对 Rockchip 原厂 SDK 改了哪些文件、为什么改。

**给谁看**：接手本仓的开发者。SDK 有十一万多个文件,其中属于本项目的约一百个,
这份清单让人知道该看哪些、哪些是原厂的不要动。

**核验基线**：2026-09-09,对照 kernel `origin/rk-6.1-rkr6.1`、
其余子仓的原厂分支(备份在 `/data/backup/nvr-os-subrepos-20260909/`)。

## 为什么需要这份清单

本仓原为 repo 多仓库结构,每个子仓有 `nvr-custom` 分支,一条
`git diff <原厂基线> nvr-custom` 就能看出改了什么。2026-09-09 收敛为单仓后,
原厂代码与定制改动在同一个提交里落地,仓库内部**不再有基线可 diff**,
只能靠这份清单。改了 SDK 里的文件请同步更新这里。

## 内核(kernel/)

原厂基线 armbian `rk-6.1-rkr6.1`,即官方 `linux-6.1-stan-rkr6.1`,6.1.118。
只动了 7 个文件:

| 文件 | 性质 | 说明 |
|---|---|---|
| `arch/arm64/boot/dts/rockchip/rk3566-nvr-ddr3-v1.0.dts` | 新增 | 无 SATA 板设备树,override 风格基于官方 box-demo dtsi |
| `arch/arm64/boot/dts/rockchip/rk3566-nvr-ddr3-sata-v1.0.dts` | 新增 | SATA 板,include 上一份只维护差异 |
| `arch/arm64/configs/nvr.config` | 新增 | defconfig 片段,与官方 `rk3566.config` 叠加使用 |
| `drivers/net/ethernet/stmicro/stmmac/stmmac_main.c` | 修改 | RTL8211F 网口灯 LCR 原来写死 0xc160,改为读 PHY 节点的 `realtek,led-lcr` |
| `logo.bmp` / `logo_kernel.bmp` | 替换 | 开机 logo |
| `.gitignore` | 修改 | 排除构建产物 |

两份 dts 里的关键决策都写在注释里:DDR 定频与 dmc 关闭的实验记录、
RK809 与 HYM8563 的 RTC 取舍、电源域、RGMII 时延、ISP/CSI 链禁用、adc-keys 禁用。

## rootfs(debian/)

| 路径 | 性质 | 说明 |
|---|---|---|
| `mk-rootfs-bookworm.sh` | 新增 | bookworm rootfs 构建脚本,debootstrap 直建,不用 linaro 基底 |
| `overlay-nvr/` | 新增 | 本项目应用层,20 个文件,见下表 |
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

其余 BoardConfig 与 `parameter-buildroot-*` 已于 2026-09-08 随旧板下线删除。

## 其他

| 文件 | 说明 |
|---|---|
| `tools/linux/Linux_Pack_Firmware/rockdev/rk356x-nvr-package-file` | update.img 打包清单,`build.sh updateimg` 依赖 |
| `u-boot/` | 一处改动:drm-logo 预留内存 size 页对齐,6.1 内核校验要求 |
| `buildroot/fs/cpio/cpio.mk` | 一处改动 |
| `docs/nvr-edge-integration.md` | rootfs 对下发组件承诺的 ABI 面 |
| `docker/` | 编译环境,Dockerfile 与 run.sh,宿主机缺依赖必须走它 |
| `CLAUDE.md` / `README.md` | 工作约定与仓库说明 |

`rkbin/` 的唯一提交是原厂的 checkpatch 脚本改动,不是本项目的。

## 上游更新状态

核验日期 2026-09-09。

| 组件 | 当前 | 上游最新 | 结论 |
|---|---|---|---|
| kernel | 6.1.118(rk-6.1-rkr6.1) | 6.1.172(rk-6.1-rkr7.2) | **有更新可用** |
| mpp | 1.1.0 | 1.1.0 | 已是最新 tag |
| librga | 1.10.6 | tag 到 v1.10.0 | 我们用的是更新的二进制发布 |
| librknnrt | 2.3.2 | v2.3.2 | 已是最新 |
| rknpu 驱动 | 0.9.8 | 随内核 | rkr7.2 里仍是 0.9.8 |
| libmali | g52-g24p0 | 内核 kbase 有 g29p1 | 无配套用户态库,不能单独升 |
| gst-rockchip 插件 | 1.14-4 | 按分支发布 | **刻意钉住**,重编后 1080p I420 走 RGA 必失败 |
| u-boot / rkbin / debian / device | 原厂分支 | Gerrit 需账号 | 本机无账号,拉不到更新 |

内核升 rkr7.2 是唯一实质可做的升级,带来 54 个 stable 点版本、RGA 内核侧 1.3.13、
Mali kbase g29p1。代价是我们改的 `stmmac_main.c` 需要重新适配,两份 dts 要验证,
且整机要重新走一遍点亮与浸泡。建议留到量产冻结前再做,不要在调试期动。
