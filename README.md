# nvr-os

RK3566 NVR 板的 Linux SDK:kernel 6.1 + Debian 12 bookworm headless。

项目文档统一见 [nvr-contracts](../nvr-contracts/docs/nvr-os/README.md)。本仓执行约定见 [CLAUDE.md](CLAUDE.md)。

## 仓库结构

本仓原为 Rockchip `repo` 多仓库结构,2026-09-09 收敛为单仓:各子目录的 `.git`
已拆除,内容直接纳入本仓。各子仓原有的独立提交历史保存在
`/data/backup/nvr-os-subrepos-20260909/` 的 git bundle 里(debian、device/rockchip、
docs、u-boot、tools、buildroot、rkbin 七份,外加 kernel 的完整 `.git` 目录)。

`.repo/` 已不可用:Rockchip Gerrit 需要账号,本机没有,`repo sync` 拉不回任何东西。
把 SDK 收进单仓正是为了不再依赖它。

## 最小可构建集

为控制仓库体积(GitHub 软上限 5G),以下内容**不入库**,克隆后需自行补齐:

| 路径 | 体积 | 构建是否必需 | 来源 |
|---|---|---|---|
| `prebuilts/gcc/` | 1.4G | **是**,内核与 vendor_storage 交叉编译 | Rockchip SDK 原始 `prebuilts` 仓,或 ARM 官方 aarch64-none-linux-gnu 工具链 |
| `debian/overlay-firmware/` | 565M | **是**,rootfs 构建时复制后裁剪出 rockchip 子集 | 上游 linux-firmware,或 Rockchip SDK 原始 debian 仓 |
| `external/rknpu2/` | 813M | **产测固件需要**:产测 NPU 自检取它的头文件与测试模型;运行库仍取 `debian/packages/arm64/rknpu2/` 那份 | Rockchip rknpu2 发布页 |
| `external/rknn-toolkit2/` | 277M | 否,PC 侧模型转换工具 | 同上 |
| `external/security/` | 105M | 否 | Rockchip SDK |
| `docs/Common/` | 533M | 否,厂商 PDF 参考资料 | Rockchip 官方文档包 |
| `tools/windows/` | 317M | 否,Windows 烧写工具 | Rockchip 工具包 |

补齐前两项即可完整构建。这台开发机上它们仍在工作区里,只是被 `.gitignore` 排除。

## 构建

一律在 docker 环境里编译,宿主机缺内核构建依赖:

```bash
docker build --network=host -t nvr-os-builder:20.04 docker/
./docker/run.sh ./build.sh kernel    # 内核 → boot.img
./docker/run.sh ./build.sh debian    # bookworm rootfs
./mkfirmware.sh                      # 在宿主机跑,汇总到 rockdev/
./build.sh updateimg                 # 整机包 rockdev/update.img
```

选板见 `./build.sh lunch`,现有四块:`rk3566-nvr-ddr3-v1.0`(无 SATA,单网口)、
`rk3566-nvr-ddr3-sata-v1.0`(SATA,双网口,默认)、`rv1126b-evb1-v10`(RV1126B 官方 EVB
标准配置,仅打通构建链)与 `rv1126b-nvr-sata-v1.0`(RV1126B 自研 SATA 板,双网口,
SATA 走 USB3-SATA 桥;依原理图建档,真机未验)。各板固件不通用,细节见 CLAUDE.md。
