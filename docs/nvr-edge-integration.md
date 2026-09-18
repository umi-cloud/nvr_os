# nvr-edge 集成约定(nvr-os ↔ nvr-edge)

本文是**镜像仓与 nvr-edge 的目录与路径约定**,两仓共同基准,变更需双端同步。

- 上游依据:`nvr-contracts/docs/client-edge-agent.md` 第九节(运行环境需求)
- 适用板型:`BoardConfig-rk3566-nvr-ddr3-v1.0.mk`(kernel + Debian 12 bookworm headless)

## 0. 集成范围(已定)

| 项 | 决定 |
|---|---|
| 镜像内置组件 | **仅 nvr-edge 主程序**一个二进制 |
| sidecar / ffmpeg / ffprobe / go2rtc | 不内置,全部走通道② 远程下发 |
| 引擎 `.so` 与模型 | 不内置,走通道③ 模型 bundle 下发 |
| `/vcache` | **不归 nvr-edge**,由其他程序消费,本文不涉及 |

## 1. 存储分层

| 分区 | 挂载点 | 属性 | 承载 | 更新通道 |
|---|---|---|---|---|
| rootfs 5G | `/` | 出厂基线,**目标只读** | 系统 + nvr-edge 基线 + 引导器 | ① 整机镜像 OTA |
| userdata 10G | `/userdata` | 可写 | work-dir:DB / 配置 / 模型 / 双槽 | ②③ 应用自更新 |
| — | `/tmp` | **tmpfs** | 无盘时录像段暂存 | — |
| 外接盘 | `/media/nvr` | 可写 | 有盘时录像根 | — |

原则:升级频率不同的东西不同层。系统年更、二进制月更、模型周更。

## 2. 目录约定

### 2.1 镜像层(rootfs)

| 路径 | 内容 |
|---|---|
| `/usr/local/bin/nvr` | **引导器**(systemd ExecStart 目标,见第 4 节) |
| `/usr/local/lib/nvr/nvr-edge` | 出厂基线主程序真身(**不入 git**,见第 6 节) |
| `/usr/local/nvr/plugins/` | 板级优化二进制预留位(当前空,见 3.2) |
| `/lib/systemd/system/nvr.service` | 服务单元 |
| `/usr/local/lib/nvr/VERSION` | 基线版本/commit/sha256,构建期写入 `os-release` 的 `NVR_AGENT_*` 字段 |
| `/etc/nvr/nvr.env` | 运行参数默认值;设备身份由 `/userdata/nvr/nvr.env` 覆盖 |
| `/etc/os-release` 的 `NVR_AGENT_*` | 出厂基线版本(见第 5 节) |
| `/etc/systemd/network/10-lan.network` | 有线 DHCP(见 2.4) |
| `/usr/lib/librknnrt.so` | NPU runtime,下发引擎 `.so` 的依赖 |

镜像内容由 `debian/overlay-nvr/` 提供,`mk-rootfs-bookworm.sh` 在装配段拷入。基线二进制与 `VERSION` **不入 git**,由 `debian/sync-nvr-edge.sh` 从 nvr-edge 的 `make baseline` 产物装入并执行门禁(第 6 节);缺基线时 rootfs 构建直接失败,不会静默产出没有应用层的镜像。

### 2.2 数据层(work-dir = `/userdata/nvr`)

派生规则见 `nvr-edge/internal/const/const.go:46`(`InitPaths`),此处只列结果:

| 路径 | 内容 | 通道 |
|---|---|---|
| `/userdata/nvr/config/nvr.db` | SQLite 主库 | — |
| `/userdata/nvr/config/model_cache/` | 模型缓存 | — |
| `/userdata/nvr/config/diskless_budget.json` | 无盘配额 | — |
| `/userdata/nvr/data/selfupdate/<组件>/{slot-a,slot-b,tmp,current→}` | 5 组件双槽 | ② |
| `/userdata/nvr/data/models/` | 引擎 `.so` + 模型 + `algorithm_config.json` | ③ |
| `/userdata/nvr/data/offlineq/` | 离线上报队列 | — |

`data/models/` 同时是 sidecar 的 `--libs-dir`(`internal/app/app.go:302`),即**插件与模型同目录**,由 `cloud.models_dir` 单一配置项决定(默认值见 `internal/config/config.go:815`)。

目录由 nvr-edge 启动时自建(`internal/app/startup_dirs.go`),**镜像侧不做 seed**,只需保证 `/userdata` 已挂载且可写。

### 2.3 媒体层

| 路径 | 条件 | 用途 |
|---|---|---|
| `/media/nvr` | 外接盘经 udev 挂载 | 录像根 `BaseDir` |
| `/media/nvr/cache` | 有盘 | 录像段暂存 |
| `/tmp/cache` | **无盘** | 录像段暂存 → 必须是 tmpfs |

判定逻辑:`const.go:91` 扫 `/proc/mounts` 找 `/media/nvr` 挂载点;无盘时 `CacheDir` 落 `/tmp/cache`(`const.go:78`)。

> **`/tmp` 必须是 tmpfs**(已落地)。Debian bookworm 默认不启用 `tmp.mount`,若不补条目,
> 无盘时录像段会直接写 eMMC 上的 rootfs 分区,既磨损 eMMC 又可能撑爆 rootfs。
> `debian/mk-rootfs-bookworm.sh` 的 fstab 已含:
>
> ```
> tmpfs	/tmp	tmpfs	defaults,noatime,nosuid,nodev,size=512M,mode=1777	0	0
> ```

### 2.4 网络与 DNS

不装 NetworkManager,由 **systemd-networkd**(systemd 自带,零额外包)接管有线 DHCP。依据:本板无 WiFi/BT,产品形态为有线接入免配网(`nvr-contracts/docs/app.md:54`),nvr-edge 侧对 NM 零依赖(无 `nmcli`、无 D-Bus、不碰 `/etc/network`,仅用 `net.Interfaces()` 做 WS-Discovery 与带宽统计)。

```ini
# /etc/systemd/network/10-lan.network
[Match]
Name=en*          # 不绑死 systemd 的 device-tree 命名(本板为 end1)

[Network]
DHCP=yes
```

**不装 systemd-resolved**:networkd 只管 IP,`/etc/resolv.conf` 是静态文件且无任何组件会改写它,DNS 即镜像内固定值(阿里公共 DNS v4/v6 各两条),DHCP 下发的 DNS 不参与。

> 构建期 `mk-rootfs-bookworm.sh` 会把构建机的 `resolv.conf` 拷进 rootfs 供 chroot 内 apt 使用;docker 构建下那是 Docker Engine 生成的 `127.0.0.53`,板上完全无效。收尾段已覆盖为设备端默认值。

现场调试命令相应改为 `networkctl status`(不再有 `nmcli`)。

### 2.5 启动时序

`systemd-networkd-wait-online` 保持屏蔽(沿用原有的加速启动策略),因此 `network-online.target` 开机即就绪而 DHCP 仍在进行,`nvr.service` 的 `After=network-online.target` 形同虚设 —— 首启窗口内组件下发与 NTP 会先失败一轮,二者均有重试(控制面首连为 1s→2min 指数退避)。要改为真正等待网络,去掉构建脚本中的 mask 即可,代价是无网时开机等待 wait-online 超时。

## 3. 二进制解析优先级

### 3.1 各组件查找顺序

| 组件 | 顺序 | 代码位置 |
|---|---|---|
| sidecar | `$NVR_SIDECAR_BIN` → 双槽 `sidecar/current/sidecar` → PATH `nvr-sidecar` | `internal/app/app.go:286` |
| go2rtc | 双槽 `go2rtc/current/go2rtc` → PATH → 已有外部进程 | `internal/app/go2rtc_runtime.go:136` |
| ffmpeg / ffprobe | 双槽 → `/usr/local/nvr/plugins/<bin>` → `/usr/lib/ffmpeg/<ver>/bin/` → PATH | `internal/camera/ffmpeg.go:154` |
| nvr-edge | **见第 4 节** | — |

> **命名不一致(勿踩)**:sidecar 在双槽内文件名为 `sidecar`,在 PATH 上为 `nvr-sidecar`。其余组件双槽内外同名。

### 3.2 `/usr/local/nvr/plugins/`

`internal/camera/ffmpeg.go:19` 硬编码 `/usr/local/nvr/plugins/ffmpeg`,在 Rockchip SoC 且 `ffmpeg.path=default` 时**优先于 PATH**。当前约定为空目录 —— 若日后决定内置带 rkmpp 硬编解码的 ffmpeg,放这里即可生效,无需改 nvr-edge。

## 4. 主程序自更新:引导器约定

### 问题

updater 将新版主程序写入 `data/selfupdate/nvr-edge/current/nvr-edge`,健康自检通过后切 symlink,再 `os.Exit(0)` 由 systemd 重启(`internal/selfupdate/restarter.go`)。但:

- systemd `ExecStart` 若直指 `/usr/local/bin/nvr`,重启拉起的仍是 rootfs 旧版;
- `internal/app/process_restart.go:22` 用 `os.Executable()` 重启自身,同样是旧版;
- 代码中**无任何位置**调用 `SelfUpdateBinPath("nvr-edge")`(其余 4 组件均有)。

结果:主程序永远停在出厂版本,且 trial 无法 confirm,`RecoverBoot` 会反复判回滚。

### 约定

`/usr/local/bin/nvr` 是**引导器**,不是主程序本体。实现见
`debian/overlay-nvr/usr/local/bin/nvr`(本文只述约定,不复制脚本,以免两处失配),行为是:

1. **把出厂基线复制到可写目录再启动**:运行体是 `<work-dir>/bin/nvr-edge`,缺失或
   0 字节时才从 `/usr/local/lib/nvr/nvr-edge` 补一份(先落 `.tmp` 再 `mv`)。
   不直接 exec rootfs 里的基线,是因为 nvr-edge 把 `os.Executable()` 当作"systemd 固定
   启动路径",自更新切槽后会把活动槽二进制复制回这个路径;指向 `/usr` 时
   `ProtectSystem=full` 下只读 → 复制失败 → `Install()` 整体回滚,表现为
   **裸机首次 OTA 必然失败且永远卡在出厂版本**。
2. **不做"槽优先"选择**:哪个槽活动由 updater 的 `state.json` 说了算(回滚也走它),
   引导器只保证固定路径上有一个能跑的二进制。已存在的运行体不会被基线覆盖 ——
   **换了 rootfs 里的基线不会让已部署设备升级**,升级只走 OTA;要强制回到出厂版本,
   删掉运行体并清 `data/selfupdate/nvr-edge/state.json` 再重启。
3. **组装启动参数**(见下),并在 `nvr.env` 未注入时用设备树序列号兜底 device-sn。

**参数必须在引导器里组装,不能写进 unit 的 ExecStart**:systemd 对不带引号的 `${VAR}`
做 word splitting,空值会让整个参数消失。未绑定设备(`nvr.env` 身份留空)因此退化成
`--agent-id --device-sn`,Go flag 把后一个开关当成前一个的值,agent-id 被静默设成
`"--device-sn"`(`flags.NArg()==0`,不报错),设备带着错身份连云平台。

**`XDG_CACHE_HOME` 必须显式指向 userdata**:tursogo 启动时把动态库解压到
`os.UserCacheDir()`,默认 `$HOME/.cache` 落在 `/root`,被 unit 的 `ProtectHome=yes`
挡死并直接 panic。unit 已设 `Environment=XDG_CACHE_HOME=/userdata/nvr/.cache`。

由此得到的性质:

- rootfs 可只读 —— 运行体与自更新都只写 `/userdata`;
- 首启运行体为空,自动从出厂基线补一份,裸机可启动;
- 回滚天然生效 —— updater 按 `state.json` 把活动槽同步回运行体,引导器无状态;
- 某次同步没落上时,下次启动 `RecoverBoot` 会再 activate 一遍并请求重启,自愈;
- 引导器本身极简,不参与任何更新通道。

## 5. rootfs 对外 ABI 面

组件全部远程下发后,rootfs 提供的 ABI 面即成为对外契约,**改动会破坏已下发组件**。

镜像只在 `/etc/os-release` 声明出厂基线(freedesktop 规范允许的发行方扩展字段,加 `NVR_` 前缀),即 OTA 之后运行时推不出来的出厂 nvr 版本:

```
NVR_AGENT_BASELINE="1.4.0"
NVR_AGENT_COMMIT="a982cf9"
NVR_AGENT_SHA256="e270ef5e…"
```

其余 ABI 信息不写进镜像,由 nvr-edge 运行时探测:rootfs 由 rk3566 与 rv1126b 共用,写死的芯片名在另一颗芯片上是错的,版本号随 OTA 也会过时。现状(2026-09-17 核实):

- 芯片型号、glibc 版本:`platform.DetectChip` 探测,随设备注册上报(`cloud/payload.go` 的 `glibc_version`)
- librknnrt 版本:**尚无运行时探测与上报**
- `NVR_AGENT_*`:**尚无读取方**

> 此前的 `/etc/nvr-release`(JSON 清单,含写死的 `soc`)已于 2026-09-17 移除:全仓库只有写入方,文档所述"随 `components/status` 上报"从未实现。

必须长期保证的接口:

| 接口 | 现状 | 依赖方 |
|---|---|---|
| `/usr/lib/librknnrt.so` 2.3.2(配 rknpu 驱动 0.9.8) | `mk-rootfs-bookworm.sh:219` 已装 | 下发的引擎 `.so` |
| glibc 2.36 | bookworm 基底 | sidecar(动态链接,不可 static/musl) |
| `/dev/rknpu`、`/dev/dri/*` | 已通 | 引擎 |
| CA 证书 | 已装 | 组件下载 TLS |
| `/dev/watchdog0` | 节点可用,喂狗未实现 | nvr-edge |

> **glibc 不升级。** 主程序无任何 `GLIBC_x.y` 版本化符号引用(`readelf -V` 报 no version information),仅 22 个基础未定义符号;sidecar 正式构建即 `debian:bookworm-slim`(2.36),自洽。glibc 只向后兼容,rootfs 版本越低,可下发组件的构建面越宽。
>
> 对应约束:**组件发布侧必须以 bookworm 为构建基线**,发布门禁校验 `readelf -V <bin> | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1` ≤ 2.36。开发机(Ubuntu 24.04 等)直接 `make release` 产出的 sidecar 会带 `GLIBC_2.38`,推到设备上必然起不来。

## 6. 出厂基线规范

镜像内置的 nvr-edge 是设备出厂时唯一的应用层,裸机首启、OTA 失败回滚、恢复出厂都落回它。
规则如下,由 `nvr-edge` 的 `make baseline` 与本仓 `debian/sync-nvr-edge.sh` 共同保证。

**怎么产出**(nvr-edge 仓):

```bash
make baseline              # 当前 HEAD
make baseline REV=v1.5.2   # 指定 tag/commit
```

- **只从已提交版本编**:在 `REV` 的临时 worktree 里构建,工作区未提交的改动进不了出厂镜像。
  历史上出过 `commit=a982cf9+dirty` 的基线 —— 无法复现,也说不清里面有什么。
- **固定正式云控**,且只认仓库内的 `cloud.json`:本地私有的 `cloud.prod.json` 不在 worktree 里,
  故同一 commit 编出的基线内容确定。
- **必须内嵌前端**:`FULL=0` 那种快速构建只塞一个空占位,装进出厂镜像等于设备没有 Web 界面。
- 产物 `out/baseline/{nvr-edge,VERSION}`;`VERSION` 记版本、完整 commit、sha256、构建时间、
  云控环境与地址、前端文件数。

**怎么装入**(本仓):`./debian/sync-nvr-edge.sh [nvr-edge 仓路径]`,六道门禁全过才写入 overlay:

| 门禁 | 拦的是什么 |
|---|---|
| sha256 与 `VERSION` 一致 | 二进制与版本记录对不上(装了 A 记了 B) |
| commit 是完整 sha1 且在 nvr-edge 仓里 | 脏树产物、来路不明的二进制 |
| ARM aarch64 ELF | 开发机直接编出的 x86_64 |
| glibc 符号 ≤ 2.36 | 高版本构建环境的产物,装进 bookworm 起不来 |
| `web_files > 1` | 没有前端的空壳基线 |
| 嵌的是正式云控地址、且不含测试地址 | 出厂设备连错平台 —— 要整机重烧才能纠正 |

正式地址取自该 commit 的 `cloud.json`,不在本仓写死域名。

**不入 git**:基线 40M,每换一版仓库就多一份历史,`.gitignore` 已排除二进制与 `VERSION`。
代价是克隆后必须先跑一次同步脚本才能构建带 nvr 的 rootfs(`README` 最小可构建集同理)。

**何时更新**:跟随发版更新,单独一个提交,不夹在别的改动里。更新基线不会让已部署设备升级
(引导器不覆盖已有运行体,见第 4 节),只影响新烧录的设备与恢复出厂。

## 7. 实施状态

### nvr-os 侧(已完成,待上板验证)

| 改动 | 位置 |
|---|---|
| `overlay-nvr/`:引导器 + 基线 + `nvr.service` + `nvr.env` | `debian/overlay-nvr/` |
| 基线同步脚本(校验 aarch64 ELF 与 glibc 上限) | `debian/sync-nvr-edge.sh` |
| 装配 overlay-nvr(无基线则跳过并告警) | `mk-rootfs-bookworm.sh` 装配段 |
| fstab 增加 tmpfs `/tmp` | 同上,fstab 段 |
| NetworkManager → systemd-networkd | 同上,包列表 / networkd 配置 / enable |
| 移除 overlay 带来的 NM 配置(dragon 板共用 overlay,不动原件) | 同上,减法段 |
| `systemctl enable nvr.service`(条件启用) | 同上,chroot 段 |
| 构建期往 `/etc/os-release` 写出厂基线 `NVR_AGENT_*` | 同上,收尾段 |
| 设备端默认 DNS 覆盖构建机 `resolv.conf` | 同上,收尾段 |

**验证方式**:`./docker/run.sh ./build.sh debian` 重建 rootfs → `./mkfirmware.sh`(宿主机)→ 整机烧写。重点验网络(`networkctl status`、`ip route`)、`/tmp` 是否 tmpfs(`findmnt /tmp`)、`nvr.service` 是否起来(`systemctl status nvr`)、`/etc/os-release` 里的 `NVR_AGENT_*` 字段。

### nvr-edge 侧(待办)

1. **组件发布门禁**:glibc 符号版本校验 ≤ 2.36(第 5 节)。开发机(Ubuntu 24.04 等)直接 `make release` 产出的 sidecar 带 `GLIBC_2.38`,一旦下发到全部设备,健康自检失败回滚、组件永远装不上,现场表现为"检测功能开不了"
2. **非镜像部署下主程序自更新仍失效**:`cmd/debian/install.sh` + `cmd/debian/nvr.service` 走 `/opt/nvr` 且 `ExecStart` 直指基线,无引导器(第 4 节)。板子走镜像预装、由 overlay-nvr 解决,不执行该脚本;通用 Debian/x86 安装若要支持主程序自更新需同样处理
3. `dev-mock-rk.sh` 的 `/usr/local/nvr` 测试布局保留,仅作开发态,不进入产品约定

## 8. 未定项

| 项 | 说明 |
|---|---|
| rootfs 只读 + A/B | 当前为单 rootfs + recovery。改分区表须整机重烧,量产后改代价极高,建议本版定表。5G×2 + 10G + vcache 在 32G eMMC 可容纳(样机实测 29.12 GiB,vcache 余 13.9G) |
| ffmpeg 是否破例内置 | 全远程下发时,出厂设备在首次联网拿到下发前无录像与检测能力,首启需下载 ffmpeg 静态包(~80MB)+ go2rtc + sidecar + 模型;产线视频链路自检需先联网。若不可接受,ffmpeg 内置至 `/usr/local/nvr/plugins/ffmpeg` 即可,其余仍远程 |
| tmpfs 大小 | 已按 4GB 内存设 512M;需 `free -h` 确认板载内存,2GB 板下调至 256M。tmpfs 按需分配、配置值为上限 |
| 引擎 `.so` 的 glibc 需求 | 厂商产物未到手,`readelf -V` 一查即知;若厂商用 Ubuntu 22.04/24.04 构建会要 2.35/2.38,正解是要求其改用 bookworm 重编,而非升级 rootfs |
