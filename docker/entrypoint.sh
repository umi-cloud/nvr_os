#!/bin/bash
# 注册 qemu binfmt(debian rootfs 构建 chroot arm64 需要,注册进宿主内核,全局生效)
# SDK 脚本会把 qemu-*-static 拷进目标 rootfs,普通注册即可,无需 F 标志
if [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    sudo mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
    sudo update-binfmts --import qemu-aarch64 2>/dev/null || true
    sudo update-binfmts --import qemu-arm 2>/dev/null || true
fi
exec "$@"
