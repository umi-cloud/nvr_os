#!/bin/bash
# 从 nvr-edge 仓同步出厂基线主程序到 overlay-nvr。
#
# 镜像只内置 nvr-edge 一个组件,sidecar/ffmpeg/ffprobe/go2rtc 与引擎 .so、模型
# 全部由平台远程下发(见 docs/nvr-edge-integration.md)。本脚本只负责把
# nvr-edge 的 arm64 制品放到 overlay-nvr 并记录版本,不参与编译。
#
# 用法: ./sync-nvr-edge.sh [nvr-edge 仓路径]   默认 ../../nvr-edge
set -eu

EDGE_REPO=${1:-../../nvr-edge}
SRC_BIN="$EDGE_REPO/nvr-linux-arm64"
DST_DIR=overlay-nvr/usr/local/lib/nvr
DST_BIN="$DST_DIR/nvr-edge"

cd "$(dirname "$0")"

[ -f "$SRC_BIN" ] || {
	echo -e "\033[31m 找不到 $SRC_BIN;先在 nvr-edge 仓执行 SIDECAR_CC=aarch64-linux-gnu-gcc make release \033[0m" >&2
	exit 1
}

# 必须是 arm64 ELF —— 开发机上直接 make 会产出 x86_64,装进镜像才发现就晚了
if ! file -b "$SRC_BIN" | grep -q 'ELF 64-bit.*ARM aarch64'; then
	echo -e "\033[31m $SRC_BIN 不是 ARM aarch64 ELF: $(file -b "$SRC_BIN") \033[0m" >&2
	exit 1
fi

# glibc 符号版本不得高于 rootfs 的 2.36,否则装进镜像也跑不起来。
# 主程序通常无版本化符号引用(readelf 报 no version information),此时跳过。
MAX_GLIBC=$(readelf -V "$SRC_BIN" 2>/dev/null | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1 || true)
if [ -n "$MAX_GLIBC" ]; then
	want=2.36
	got=${MAX_GLIBC#GLIBC_}
	if [ "$(printf '%s\n%s\n' "$want" "$got" | sort -V | tail -1)" != "$want" ]; then
		echo -e "\033[31m $SRC_BIN 需要 $MAX_GLIBC,超出 rootfs 的 glibc $want \033[0m" >&2
		exit 1
	fi
	echo "  glibc 需求: $MAX_GLIBC (<= $want)"
else
	echo "  glibc 需求: 无版本化符号引用"
fi

VER=$(grep -oP 'agentVersion\s*=\s*"\K[^"]+' "$EDGE_REPO/cmd/nvr/main.go" 2>/dev/null || echo unknown)
COMMIT=$(git -C "$EDGE_REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)
SHA=$(sha256sum "$SRC_BIN" | cut -d' ' -f1)

mkdir -p "$DST_DIR"
install -m 755 "$SRC_BIN" "$DST_BIN"

# 供 mk-rootfs-bookworm.sh 组装 /etc/nvr-release
cat > "$DST_DIR/VERSION" <<EOF
version=$VER
commit=$COMMIT
sha256=$SHA
EOF

echo -e "\033[32m nvr-edge 基线已同步: $VER ($COMMIT) $(du -h "$DST_BIN" | cut -f1) \033[0m"
