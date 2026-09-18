#!/bin/bash
# 把 nvr-edge 的出厂基线装进 overlay-nvr,并在装入前执行门禁。
#
# 镜像只内置 nvr-edge 一个组件,sidecar/ffmpeg/ffprobe/go2rtc 与引擎 .so、模型
# 全部由平台远程下发(见 docs/nvr-edge-integration.md)。本脚本不编译,只校验与安装。
#
# 输入是 nvr-edge 的 `make baseline` 产物 out/baseline/{nvr-edge,VERSION}:那条路径
# 保证基线来自某个已提交版本、内嵌前端、用仓库内的正式云控配置(规范见集成约定第 6 节)。
# 基线二进制不入 git,克隆后需重新跑一遍本脚本才能构建带 nvr 的 rootfs。
#
# 用法: ./sync-nvr-edge.sh [nvr-edge 仓路径]   默认 ../../nvr-edge
set -eu

EDGE_REPO=${1:-../../nvr-edge}
SRC_DIR="$EDGE_REPO/out/baseline"
SRC_BIN="$SRC_DIR/nvr-edge"
SRC_VER="$SRC_DIR/VERSION"
DST_DIR=overlay-nvr/usr/local/lib/nvr
DST_BIN="$DST_DIR/nvr-edge"

cd "$(dirname "$0")"

die() { echo -e "\033[31m $* \033[0m" >&2; exit 1; }

[ -f "$SRC_BIN" ] && [ -f "$SRC_VER" ] || \
	die "找不到 $SRC_DIR 下的基线;先在 nvr-edge 仓执行 make baseline"

field() { sed -n "s/^$1=//p" "$SRC_VER"; }
VER=$(field version)
COMMIT=$(field commit)
SHA_REC=$(field sha256)
CLOUD_HOST=$(field cloud_host)
WEB_FILES=$(field web_files)

# ---- 门禁 1:产物与 VERSION 必须是同一次构建 ----
SHA=$(sha256sum "$SRC_BIN" | cut -d' ' -f1)
[ "$SHA" = "$SHA_REC" ] || die "二进制 sha256 与 VERSION 记录不符($SHA != $SHA_REC)"

# ---- 门禁 2:必须来自已提交版本 ----
# 脏树编出来的基线无法复现,也说不清里面到底有什么(历史上出过 commit=xxx+dirty 的基线)
case "$COMMIT" in
	*[!0-9a-f]* | "") die "commit 不是干净的完整 sha1: '$COMMIT'" ;;
esac
[ ${#COMMIT} -eq 40 ] || die "commit 不是完整 sha1: '$COMMIT'"
git -C "$EDGE_REPO" cat-file -e "$COMMIT^{commit}" 2>/dev/null || \
	die "commit $COMMIT 不在 nvr-edge 仓里"

# ---- 门禁 3:必须是 arm64 ELF ----
# 开发机上直接 make 会产出 x86_64,装进镜像才发现就晚了
file -b "$SRC_BIN" | grep -q 'ELF 64-bit.*ARM aarch64' || \
	die "$SRC_BIN 不是 ARM aarch64 ELF: $(file -b "$SRC_BIN")"

# ---- 门禁 4:glibc 符号版本不得高于 rootfs 的 2.36 ----
# 主程序通常无版本化符号引用(readelf 报 no version information),此时跳过
MAX_GLIBC=$(readelf -V "$SRC_BIN" 2>/dev/null | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1 || true)
if [ -n "$MAX_GLIBC" ]; then
	want=2.36
	got=${MAX_GLIBC#GLIBC_}
	[ "$(printf '%s\n%s\n' "$want" "$got" | sort -V | tail -1)" = "$want" ] || \
		die "$SRC_BIN 需要 $MAX_GLIBC,超出 rootfs 的 glibc $want"
	echo "  glibc 需求: $MAX_GLIBC (<= $want)"
else
	echo "  glibc 需求: 无版本化符号引用"
fi

# ---- 门禁 5:必须内嵌前端 ----
# FULL=0 的快速构建只塞一个空占位 index.html,装进出厂镜像就是没有 Web 界面的设备
[ "${WEB_FILES:-0}" -gt 1 ] || die "基线未内嵌前端(web_files=${WEB_FILES:-0})"

# ---- 门禁 6:云控环境必须是正式 ----
# 取该 commit 上的配置为准,不在本仓写死域名;测试环境的地址一旦混进出厂镜像,
# 设备上线即连错平台,且要整机重烧才能纠正
PROD_HOST=$(git -C "$EDGE_REPO" show "$COMMIT:internal/config/cloud.json" |
	sed -n 's/.*"host"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
TEST_HOST=$(git -C "$EDGE_REPO" show "$COMMIT:internal/config/cloud.test.json" 2>/dev/null |
	sed -n 's/.*"host"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true)
[ -n "$PROD_HOST" ] || die "读不到 $COMMIT 的 cloud.json 云控地址"
[ "$CLOUD_HOST" = "$PROD_HOST" ] || die "VERSION 记的云控地址不是正式环境($CLOUD_HOST != $PROD_HOST)"
grep -aqF "$PROD_HOST" "$SRC_BIN" || die "二进制里找不到正式云控地址 $PROD_HOST"
if [ -n "$TEST_HOST" ] && [ "$TEST_HOST" != "$PROD_HOST" ]; then
	# 不能写成 `grep && die`:set -e 下 grep 未命中(正是期望结果)会让脚本整体退出
	if grep -aqF "$TEST_HOST" "$SRC_BIN"; then
		die "二进制里嵌着测试云控地址 $TEST_HOST"
	fi
fi
echo "  云控环境: 正式 ($PROD_HOST)"

mkdir -p "$DST_DIR"
install -m 755 "$SRC_BIN" "$DST_BIN"
# mk-rootfs-bookworm.sh 据此写 /etc/os-release 的 NVR_AGENT_* 出厂基线字段
install -m 644 "$SRC_VER" "$DST_DIR/VERSION"

echo -e "\033[32m nvr-edge 基线已同步: $VER ($(echo "$COMMIT" | cut -c1-9)) $(du -h "$DST_BIN" | cut -f1) \033[0m"
