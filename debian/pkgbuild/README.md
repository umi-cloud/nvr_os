# Rockchip 用户态组件(mpp / librga / gst-rockchip)deb 重打配方

**给谁看**:要升级 `packages/arm64/{mpp,rga,gst-rkmpp}` 下 deb 的人。
**核验基线**:2026-09-04,mpp 1.1.0、librga 1.10.6_[3]、gst-rockchip 1.14-5,SATA 板回归通过。

## 为什么要在 bookworm arm64 chroot 里打

deb 必须用 bookworm 构建(CLAUDE.md 记的坑:bullseye 构建的同版本号配 6.1 内核会在 MPP 层段错误)。
docker 构建镜像是 Ubuntu 20.04,所以用 `debian/bookworm-base-arm64.tar.gz` 展开一个 arm64 chroot,
靠 qemu binfmt 在容器里原生跑 dpkg-buildpackage。

## 步骤

1. 取源码到 `rockdev/pkgbuild/src/`(rockdev 不入库):
   - mpp:`git clone --depth 1 --branch <tag> https://github.com/rockchip-linux/mpp.git`,自带 debian/;
     在 `debian/changelog` 顶部加一条 `mpp (1:<版本>-1)` —— **必须带 epoch 1**,上游 changelog 一直写 1.5.0-1,
     不加 epoch 新包版本号反而比旧的小
   - librga:上游 airockchip/librga **只发预编译库**(`libs/Linux/gcc-aarch64/librga.so`,SONAME 无版本号)+ 头文件,
     没有 debian/。用本目录的 `librga-debian/` 打:把 `librga.so` 放 `prebuilt/`、头文件放 `include/`,
     `debian/` 复制过去,改 changelog 版本(同样带 epoch 1)。rules 里额外做了 `librga.so.2` 符号链接,
     兼容按旧链接名找库的二进制
   - gst-rockchip:**不要重编,沿用 1.14-4 的二进制**。实测同一份 2022 源码对 mpp 1.1.0 头文件重编后
     (1.14-5 / 1.14-6,无论配新旧 librga),1080p I420 输入走 RGA 转换时内核报
     `rga: job_commit failed / request commit failed`,gst 协商失败;而 1.14-4 旧二进制配
     mpp 1.1.0 + librga 1.10.6 运行正常(它按运行时 ABI 调用,与新头文件的编译期差异无关)。
     交叉验证过四种组合,变量只在"插件是否用新头文件重编"。要重编须先排查 mpp 1.1.0 头文件里
     与 gst 插件相关的结构/枚举变化,上游插件仓库已不可达
2. 建 chroot(docker 内,一次性):
   ```sh
   R=/sdk/rockdev/pkgbuild/rootfs
   sudo tar -xzf /sdk/debian/bookworm-base-arm64.tar.gz -C $R
   for m in proc sys dev dev/pts; do sudo mount --bind /$m $R/$m; done
   sudo chroot $R apt-get install -y build-essential debhelper dh-exec cmake meson ninja-build \
        pkg-config libdrm-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libx11-dev fakeroot
   ```
3. 源码拷进 `$R/build/`,`sudo chroot $R /bin/bash /build/build.sh`(本目录的 build.sh):
   按 mpp → librga → gst 顺序构建,前一个的 -dev 装进 chroot 供后一个链接,产物在 `$R/out/`
4. 新 deb 替换 `packages/arm64/{mpp,rga,gst-rkmpp}/` 里的旧文件(**同名包只能留一个版本**,
   mk-rootfs 用通配符 `dpkg -i`,两版并存会装错),重建 rootfs
5. 板上回归:`mpi_enc_test -w 640 -h 480 -t 7 -n 10 -o /tmp/s.h264` 输出非零码流;
   `mpi_dec_test -i /tmp/s.h264 -t 7 -n 10`;
   `gst-launch-1.0 videotestsrc num-buffers=60 ! video/x-raw,width=1280,height=720 ! mpph264enc ! h264parse ! mppvideodec ! fakesink`
