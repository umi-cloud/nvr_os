# RK3566 Linux5.10 SDK 编译环境
# 构建: docker build -t nvr-os-builder:20.04 docker/
# 使用: docker/run.sh [命令],默认进入 bash
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive TZ=Asia/Shanghai LANG=en_US.UTF-8

# Rockchip 官方依赖 + kernel/buildroot/debian rootfs 构建所需
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ssh openssh-client ca-certificates \
    make gcc g++ gcc-multilib g++-multilib patchelf chrpath \
    libssl-dev libncurses-dev liblz4-tool lz4 zstd bzip2 xz-utils unzip cpio \
    expect gawk texinfo diffstat bison flex fakeroot cmake bc \
    device-tree-compiler u-boot-tools \
    binfmt-support qemu-user-static live-build \
    python2 python3 python3-pip python3-pyelftools python-is-python3 \
    rsync file wget curl locales sudo time kmod \
    mtools dosfstools parted e2fsprogs \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8

# bookworm rootfs 构建需要新版 debootstrap 和 bookworm 签名密钥(focal 自带的都太旧)。
# pool 里只留最新小版本,旧版本会被删(2026-10-22 1.0.144 已下架),重建失败时到
# http://deb.debian.org/debian/pool/main/d/debootstrap/ 查当前版本号改这里
RUN curl -fsSL -o /tmp/debootstrap.deb http://deb.debian.org/debian/pool/main/d/debootstrap/debootstrap_1.0.145_all.deb \
    && curl -fsSL -o /tmp/keyring.deb http://deb.debian.org/debian/pool/main/d/debian-archive-keyring/debian-archive-keyring_2023.3+deb12u2_all.deb \
    && dpkg -i /tmp/debootstrap.deb /tmp/keyring.deb \
    && rm /tmp/debootstrap.deb /tmp/keyring.deb

# buildroot(recovery 等)额外依赖,独立一层避免重建主依赖层
RUN apt-get update && apt-get install -y --no-install-recommends \
    patch perl less dpkg-dev \
    && rm -rf /var/lib/apt/lists/*

# 非交互构建:禁用分页器(repo/git 在 tty 下会调 less 挂起构建)
ENV PAGER=cat GIT_PAGER=cat

# 与宿主机用户同 UID/GID,保证挂载目录文件属主一致
RUN groupadd -g 1000 builder && useradd -m -u 1000 -g 1000 -s /bin/bash builder \
    && echo 'builder ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/builder

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /sdk
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
