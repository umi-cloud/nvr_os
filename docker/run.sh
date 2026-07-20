#!/bin/bash
# 进入 RK3566 SDK docker 编译环境
# 用法:
#   docker/run.sh                     # 交互 bash
#   docker/run.sh ./build.sh kernel   # 直接执行构建命令
set -e

SDK_DIR=$(cd "$(dirname "$0")/.." && pwd)
IMG=nvr-os-builder:20.04

if ! docker image inspect "$IMG" >/dev/null 2>&1; then
    echo "镜像 $IMG 不存在,先构建: docker build -t $IMG $SDK_DIR/docker/"
    exit 1
fi

TTY_FLAG=""
[ -t 0 ] && TTY_FLAG="-it"

# --privileged: debian rootfs 构建需要 chroot + binfmt + mount
# --network=host: 规避 bridge 网络下 buildkit/DNS 问题,rootfs 构建需在线装包
# --security-opt no-new-privileges=false: 宿主 daemon.json 全局禁 setuid 提权,
#   此容器需 sudo(rootfs 构建脚本内部大量使用),按容器覆盖,不影响全局策略
exec docker run --rm $TTY_FLAG --privileged \
    --network=host \
    --security-opt no-new-privileges=false \
    -v "$SDK_DIR":/sdk \
    -w /sdk \
    -u builder \
    "$IMG" "$@"
