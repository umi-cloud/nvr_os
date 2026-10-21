#!/bin/bash -e

# NVR headless Debian 12 (bookworm, glibc 2.36) rootfs
# 调用约定与 mk-rootfs-bullseye.sh 一致: VERSION=debug ARCH=arm64 ./mk-rootfs-bookworm.sh
# 差异: 不依赖 linaro 桌面基底,直接 debootstrap;不装 X/桌面;
#       安装硬件加速组件: mpp / rga / rknpu2 / libmali(g24p0-x11-wayland-gbm,同时支持 GBM/X11/Wayland)

TARGET_ROOTFS_DIR="binary"
MIRROR=${MIRROR:-http://deb.debian.org/debian}
BASE_TARBALL=bookworm-base-arm64.tar.gz

case "${ARCH:-$1}" in
	arm|arm32|armhf)
		echo "bookworm rootfs 仅支持 arm64" && exit 1
		;;
	*)
		ARCH=arm64
		;;
esac

if [ ! $VERSION ]; then
	VERSION="release"
fi
echo -e "\033[36m Building bookworm ($VERSION) for $ARCH \033[0m"

finish() {
	sudo umount -l $TARGET_ROOTFS_DIR/dev 2>/dev/null || true
	sudo umount -l $TARGET_ROOTFS_DIR/proc 2>/dev/null || true
	sudo umount -l $TARGET_ROOTFS_DIR/sys 2>/dev/null || true
	exit -1
}
trap finish ERR

# ---------- 基底(带缓存,重建 rootfs 不重复 debootstrap) ----------
# 注意: SDK 所在盘常带 nodev 挂载参数,chroot 内设备节点不可用会导致
# debootstrap 失败,故基底在容器内部文件系统(/tmp)构建,仅产物 tar 落盘
if [ ! -e $BASE_TARBALL ]; then
	echo -e "\033[36m debootstrap bookworm base... \033[0m"
	BASE_WORK=$(mktemp -d /tmp/bookworm-base.XXXXXX)
	sudo debootstrap --arch=$ARCH --foreign bookworm $BASE_WORK/rootfs $MIRROR
	sudo cp /usr/bin/qemu-aarch64-static $BASE_WORK/rootfs/usr/bin/
	sudo chroot $BASE_WORK/rootfs /debootstrap/debootstrap --second-stage
	sudo tar -cpzf $BASE_TARBALL -C $BASE_WORK/rootfs .
	sudo rm -rf $BASE_WORK
fi

echo -e "\033[36m Extract base \033[0m"
sudo rm -rf $TARGET_ROOTFS_DIR
sudo mkdir -p $TARGET_ROOTFS_DIR
sudo tar -xpf $BASE_TARBALL -C $TARGET_ROOTFS_DIR

# 精简: 不安装文档/手册页/无关语言(en/zh 保留)
sudo mkdir -p $TARGET_ROOTFS_DIR/etc/dpkg/dpkg.cfg.d
sudo tee $TARGET_ROOTFS_DIR/etc/dpkg/dpkg.cfg.d/01-slim > /dev/null <<'EOF'
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/info/*
path-exclude /usr/share/locale/*
path-include /usr/share/locale/en*
path-include /usr/share/locale/zh*
path-include /usr/share/locale/locale.alias
EOF

# ---------- 装配 ----------
sudo cp /usr/bin/qemu-aarch64-static $TARGET_ROOTFS_DIR/usr/bin/

# overlay: udev 规则、rockchip 脚本等;debug 版本附加调试工具
sudo cp -rpf overlay/* $TARGET_ROOTFS_DIR/
if [ "$VERSION" == "debug" ]; then
	sudo cp -rpf overlay-debug/* $TARGET_ROOTFS_DIR/
fi
# 移除 overlay 带来的桌面时代服务和 WiFi/BT 服务(本板无此硬件)
sudo rm -f $TARGET_ROOTFS_DIR/usr/lib/systemd/system/resize-disk.service \
	$TARGET_ROOTFS_DIR/usr/lib/systemd/system/rockchip.service \
	$TARGET_ROOTFS_DIR/usr/lib/systemd/system/rkwifibt.service \
	$TARGET_ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/resize-disk.service \
	$TARGET_ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/rockchip.service \
	$TARGET_ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/rkwifibt.service \
	$TARGET_ROOTFS_DIR/etc/init.d/resize-disk.sh $TARGET_ROOTFS_DIR/etc/init.d/rockchip.sh \
	$TARGET_ROOTFS_DIR/etc/init.d/rkwifibt.sh \
	$TARGET_ROOTFS_DIR/etc/Powermanager/03wifibt $TARGET_ROOTFS_DIR/etc/Powermanager/04wifibt
# overlay 为 dragon 板(bullseye)共用,其 NetworkManager 配置在本板无用 —— 网络改由
# systemd-networkd 接管;残留配置目录会误导现场排查,一并移除(勿删 overlay 内的原件)
sudo rm -rf $TARGET_ROOTFS_DIR/etc/NetworkManager
# NVR 应用层: nvr-edge 出厂基线 + 引导器 + systemd unit(见 docs/nvr-edge-integration.md)
# 只内置 nvr-edge 一个组件,sidecar/ffmpeg/ffprobe/go2rtc 与引擎 .so、模型均远程下发
if [ -x overlay-nvr/usr/local/lib/nvr/nvr-edge ]; then
	sudo cp -rpf overlay-nvr/* $TARGET_ROOTFS_DIR/
	# cp -p 连属主一起保留,装进镜像就成了构建机的 UID 1000(builder/song)。
	# 设备上 1000 可能是别的用户甚至不存在,系统文件必须归 root。
	sudo chown -R root:root $TARGET_ROOTFS_DIR/usr/local $TARGET_ROOTFS_DIR/etc/nvr \
		$TARGET_ROOTFS_DIR/usr/lib/systemd/system $TARGET_ROOTFS_DIR/etc/systemd $TARGET_ROOTFS_DIR/etc/udev
	# cp -p 原样保留权限,源文件漏了可执行位就会装出一个 203/EXEC 起不来的服务
	# (vsync 启动脚本踩过:真机手动 chmod 过,恰好掩盖了镜像里的 644)
	for f in $TARGET_ROOTFS_DIR/usr/local/bin/* $TARGET_ROOTFS_DIR/usr/local/sbin/*; do
		[ -f "$f" ] && [ ! -x "$f" ] && {
			echo -e "\033[33m 补可执行位: ${f#$TARGET_ROOTFS_DIR} \033[0m"
			sudo chmod 755 "$f"
		}
	done
else
	# 基线二进制不入 git(见 docs/nvr-edge-integration.md 第 6 节),克隆后必须先同步。
	# 这里不能只告警跳过:那样会静默产出一个没有 nvr 应用层的镜像,烧进设备才发现
	echo -e "\033[31m overlay-nvr 无 nvr-edge 基线;先执行 ./sync-nvr-edge.sh \033[0m" >&2
	exit 1
fi

# Rockchip 官方 vendor storage 工具(external/rktoolkit),产线写 SN/MAC 与开机套 USB 网口 MAC 都靠它。
# 静态链接,构建机上用 SDK 自带的 aarch64 工具链编;源码不入 overlay,避免二进制入库。
CROSS_GCC=$(ls ../prebuilts/gcc/linux-x86/aarch64/*/bin/aarch64-none-linux-gnu-gcc 2>/dev/null | head -1)
if [ -n "$CROSS_GCC" ] && [ -f ../external/rktoolkit/vendor_storage.c ]; then
	$CROSS_GCC -O2 -static -o /tmp/vendor_storage.$$ ../external/rktoolkit/vendor_storage.c
	sudo install -m 755 /tmp/vendor_storage.$$ $TARGET_ROOTFS_DIR/usr/local/sbin/vendor_storage
	rm -f /tmp/vendor_storage.$$
	echo -e "\033[36m vendor_storage 工具已编入 \033[0m"
else
	echo -e "\033[33m 未找到交叉编译器或 external/rktoolkit,跳过 vendor_storage \033[0m"
fi

# 串口 getty:Rockchip overlay 的 serial-getty@.service 写死 --autologin root,串口敲回车
# 直接进 root shell、连密码都不要。去掉它,串口按 root/root 登录(CLAUDE.md 记的兜底方式)。
sudo sed -i 's/ --autologin root//' $TARGET_ROOTFS_DIR/usr/lib/systemd/system/serial-getty@.service

# ssh root 密钥登录:公钥来自 debian/authorized_keys(公钥入库是安全的,私钥永远不入)
# 装了公钥才会在 chroot 段禁用密码认证 —— 没有公钥就禁密码会造出一台谁也登不上的机器
if [ -s authorized_keys ]; then
	sudo install -d -m 700 $TARGET_ROOTFS_DIR/root/.ssh
	sudo install -m 600 authorized_keys $TARGET_ROOTFS_DIR/root/.ssh/authorized_keys
	echo -e "\033[36m ssh 公钥已装入($(grep -c . authorized_keys) 把) \033[0m"
else
	echo -e "\033[33m 无 debian/authorized_keys,ssh 保持密码登录 \033[0m"
fi

# WiFi/BT/NPU 等固件
sudo cp -rpf overlay-firmware/* $TARGET_ROOTFS_DIR/
# overlay-firmware 是全量 linux-firmware;本板无 WiFi/BT,只保留 rockchip
sudo find $TARGET_ROOTFS_DIR/usr/lib/firmware -mindepth 1 -maxdepth 1 \
	! -name rockchip -exec rm -rf {} +
# /system 为 WiFi/BT 厂商固件目录,整体移除
sudo rm -rf $TARGET_ROOTFS_DIR/system

# Rockchip 组件包(仅 headless 需要的子集)
sudo mkdir -p $TARGET_ROOTFS_DIR/packages
sudo cp -pf packages/$ARCH/mpp/librockchip-mpp1_*.deb \
	packages/$ARCH/mpp/librockchip-vpu0_*.deb \
	packages/$ARCH/mpp/rockchip-mpp-demos_*.deb \
	packages/$ARCH/rga/librga2_*.deb \
	packages/$ARCH/libmali/libmali-bifrost-g52-g24p0-x11-wayland-gbm_*.deb \
	packages/$ARCH/gst-rkmpp/gstreamer1.0-rockchip1_*.deb \
	packages/$ARCH/gst-plugins-bad1.0/gstreamer1.0-plugins-bad_1.22*.deb \
	packages/$ARCH/gst-plugins-bad1.0/libgstreamer-plugins-bad1.0-0_1.22*.deb \
	$TARGET_ROOTFS_DIR/packages/
# NPU runtime v2.5.0(airockchip/rknn-toolkit2,配 6.1 内核 rknpu 驱动 0.9.8;2026-10-21 由 2.3.2 升级,SATA 板实测无驱动版本警告)
sudo cp -rpf packages/$ARCH/rknpu2/rknpu2-rk356x-v2.5.0 $TARGET_ROOTFS_DIR/packages/rknpu2

# apt 源:packages/apt-mirror-bookworm 有内容则全走本地快照(严格钉版、离线可复现);
# 否则在线构建并在结束后自动把本次下载的全部 deb 捕获入镜像目录
APT_MIRROR_DIR=packages/apt-mirror-bookworm
if ls $APT_MIRROR_DIR/*.deb >/dev/null 2>&1; then
	echo -e "\033[36m 使用本地 apt 镜像($(ls $APT_MIRROR_DIR/*.deb | wc -l) 个包) \033[0m"
	sudo mkdir -p $TARGET_ROOTFS_DIR/packages-mirror
	sudo cp -pf $APT_MIRROR_DIR/*.deb $TARGET_ROOTFS_DIR/packages-mirror/
	( cd $TARGET_ROOTFS_DIR/packages-mirror && \
	  dpkg-scanpackages --multiversion . 2>/tmp/scanpkg.err | sudo tee Packages > /dev/null )
	sudo tee $TARGET_ROOTFS_DIR/etc/apt/sources.list > /dev/null <<'EOF'
deb [trusted=yes] file:///packages-mirror ./
EOF
else
	echo -e "\033[33m 本地 apt 镜像为空:在线构建并捕获 \033[0m"
	sudo touch $TARGET_ROOTFS_DIR/.capture-apt
	sudo tee $TARGET_ROOTFS_DIR/etc/apt/sources.list > /dev/null <<'EOF'
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF
fi

# 主机名 / hosts / fstab / dns(chroot 内 apt 需要)
# rootfs 多芯片共用,默认名不带芯片型号;有序列号的板子开机由 nvr-hostname 改成 UMI-<SN后6位>
echo nvr | sudo tee $TARGET_ROOTFS_DIR/etc/hostname > /dev/null
sudo tee $TARGET_ROOTFS_DIR/etc/hosts > /dev/null <<'EOF'
127.0.0.1	localhost
127.0.1.1	nvr
::1		localhost ip6-localhost ip6-loopback
EOF
sudo tee $TARGET_ROOTFS_DIR/etc/fstab > /dev/null <<'EOF'
/dev/root	/	ext4	defaults,noatime,x-systemd.growfs	0	1
PARTLABEL=userdata	/userdata	ext4	defaults,noatime,nofail,x-systemd.makefs	0	2
PARTLABEL=vcache	/vcache	ext4	defaults,noatime,nofail,x-systemd.makefs	0	0
tmpfs	/tmp	tmpfs	defaults,noatime,nosuid,nodev,size=512M,mode=1777	0	0
EOF

# 网络: systemd-networkd(systemd 自带,替代 NetworkManager)
# 本板无 WiFi/BT,产品形态为有线接入免配网,NM 的连接管理与 D-Bus 链路用不上。
# 不装 systemd-resolved —— networkd 只管 IP,DNS 由下方静态 resolv.conf 固定,
# 职责单一且不会有任何组件回头改写它。
# 两个口分两份配置,靠路由 metric 定优先级:gmac1(systemd 按设备树别名命名为 end0,曾是 end1)
# 是千兆 RGMII 口,metric 100;USB 网口(r8152,无别名叫 eth1,RTL8152 只有 100M)metric 2000。
# 两口同网段时内核只看 metric,实测两者都 1024 会把摄像头 RTSP 和默认出口全压到 100M 的 USB 口上,
# 千兆口空转。
# **USB 口按驱动匹配,且文件名排在千兆口之前**(08- < 10-)。接口名不是稳定契约:
# USB 网卡现在叫 eth1,只是因为 udev 没为它生成基于路径的名字而落到内核默认名;
# 换个 USB 口或换版 systemd 都可能变成 en 开头,那样会被 Name=en* 抢走、拿到
# metric 100 与千兆口并列,正是上面那个坑。networkd 取**字典序第一个**匹配的
# .network,所以 08- 先把 r8152 认走,10-lan 只可能剩下千兆口。
# 千兆口只能按名字匹配:udev 不给 stmmac 平台网卡上报 ID_NET_DRIVER
# (ethtool 报 st_gmac,udevadm info 里没有该属性),写 Driver= 会匹配不上 →
# 网口拿不到任何配置、没有 DHCP。改这两行前先在板上核对 `networkctl status`。
# 05- 前缀留给 nvr-edge 运行时写的网卡配置,优先级高于出厂这两份。
sudo mkdir -p $TARGET_ROOTFS_DIR/etc/systemd/network
sudo tee $TARGET_ROOTFS_DIR/etc/systemd/network/10-lan.network > /dev/null <<'EOF'
[Match]
Name=en*

[Network]
DHCP=yes

[DHCPv4]
RouteMetric=100
EOF
sudo tee $TARGET_ROOTFS_DIR/etc/systemd/network/08-usb-eth.network > /dev/null <<'EOF'
[Match]
Driver=r8152

[Network]
DHCP=yes

[DHCPv4]
RouteMetric=2000
EOF

# NTP:不配则吃编译进去的 FallbackNTP(debian.pool.ntp.org)。实测设备在国内会先
# 连试多个境外 IPv6 地址超时,第四个才通(日志三条 Timed out 后才 Contacted)。
# 这块板无 RTC,对不上时只能用 clock file 的旧时间,而录像索引与事件时间戳都依赖
# 系统时间,故钉阿里云。两个主源都只有 A 记录(无 AAAA),从根上避开 v6 超时。
# 用 drop-in 而非改 timesyncd.conf:后者是发行版配置,升级会冲突。
# 只列这两个:ntp2~ntp7.aliyun.com 实测全部解析到与 ntp.aliyun.com 相同的
# anycast 地址(203.107.6.88),多写不增加冗余;ntp1 才是独立地址(121.199.69.55)。
# ntp.cloud.aliyuncs.com 是 ECS 内网源(100.100.x),公网无响应,不能用。
# 实测(2026-08):ntp.aliyun.com stratum3/24ms、ntp1 stratum2/11ms。
# FallbackNTP 仅在阿里云全部不可达时才启用,给无 RTC 的板子留条后路。
sudo mkdir -p $TARGET_ROOTFS_DIR/etc/systemd/timesyncd.conf.d
sudo tee $TARGET_ROOTFS_DIR/etc/systemd/timesyncd.conf.d/10-nvr.conf > /dev/null <<'EOF'
[Time]
NTP=ntp.aliyun.com ntp1.aliyun.com
FallbackNTP=cn.pool.ntp.org
EOF

# 分区首启处理改用 systemd 原生机制(fstab 里的 x-systemd.growfs / x-systemd.makefs):
#  根分区每次开机由 systemd-growfs-root 在线扩到分区大小(已满时毫秒级空操作,刷机后自动扩);
#  userdata/vcache 由 systemd-makefs@ 在无文件系统时 mkfs.ext4。原来自写的 format-data-parts
#  脚本每次开机要等 by-partlabel 设备出现再 blkid,占 300-700ms 且挡在 local-fs-pre 前面。
sudo cp /etc/resolv.conf $TARGET_ROOTFS_DIR/etc/resolv.conf

# ---------- chroot 安装 ----------
sudo mount -o bind /dev $TARGET_ROOTFS_DIR/dev
sudo mount -t proc none $TARGET_ROOTFS_DIR/proc
sudo mount -t sysfs none $TARGET_ROOTFS_DIR/sys
sudo mount -t devpts none $TARGET_ROOTFS_DIR/dev/pts 2>/dev/null || true

sudo chroot $TARGET_ROOTFS_DIR /bin/bash -e <<'EOF'
export DEBIAN_FRONTEND=noninteractive
APT_INSTALL="apt-get install -y --no-install-recommends"

apt-get update
# debootstrap 基底缓存里的包(perl-base、liblzma5、libpcre2、tzdata 等)只靠 install 不会升级,
# 清空 apt 快照联网重建时也拿不到安全更新;离线时只从本地快照取版本,不影响可复现
apt-get -y upgrade

# 基础系统 + 网络 + ssh + 存储/调试工具(headless,本板无 WiFi/BT)
${APT_INSTALL} systemd-sysv systemd-timesyncd udev dbus kmod sudo locales \
	ca-certificates bash-completion \
	ethtool \
	iputils-ping curl wget openssh-server \
	parted dosfstools e2fsprogs \
	smartmontools \
	htop usbutils vim-tiny less \
	libdrm2 \
	libwayland-client0 libwayland-server0 libx11-6 libx11-xcb1 libxcb1 libxcb-dri2-0 libxcb-dri3-0 libxcb-present0 libxcb-xfixes0 \
	gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good

# locale / 时区
sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
# LC_TIME 单独设 C.UTF-8:en_US 的时间格式是 12 小时制(date 输出 03:56 PM),
# 排查日志时要和 journal 的 24 小时制来回换算。C.UTF-8 是 glibc 内置、
# 无需 locale-gen,给出 24 小时制且格式稳定,便于脚本解析。
update-locale LANG=en_US.UTF-8 LC_TIME=C.UTF-8
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo Asia/Shanghai > /etc/timezone

# Rockchip 加速组件(bullseye 构建的 deb 在更新的 glibc 上直接可用)
dpkg -i /packages/librockchip-mpp1_*.deb /packages/librockchip-vpu0_*.deb \
	/packages/rockchip-mpp-demos_*.deb /packages/librga2_*.deb \
	/packages/libmali-bifrost-g52-g24p0-x11-wayland-gbm_*.deb \
	/packages/gstreamer1.0-rockchip1_*.deb
# plugins-bad 只抽需要的插件(h264/h265parse、kmssink):
# 装元包会经 gl/gtk/flite 依赖链拖入 LLVM+GTK 等 ~300M,NVR 用不到
# deb 已随仓库落在 packages/arm64/gst-plugins-bad1.0/,离线可复现
dpkg-deb --fsys-tarfile /packages/gstreamer1.0-plugins-bad_1.22*.deb | tar -x -C / \
	./usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgstvideoparsersbad.so \
	./usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgstkms.so
dpkg-deb --fsys-tarfile /packages/libgstreamer-plugins-bad1.0-0_1.22*.deb | tar -x -C / \
	--wildcards "./usr/lib/aarch64-linux-gnu/libgstcodecparsers-1.0.so.0*"

# NPU: rknn_server + librknnrt(v2.5.0)
install -m755 /packages/rknpu2/rknn_server /packages/rknpu2/start_rknn.sh /packages/rknpu2/restart_rknn.sh /usr/bin/
install -m644 /packages/rknpu2/librknnrt.so /usr/lib/
ldconfig

# rknn_server 服务(默认启用:rknn-toolkit2 python 连板调试/模型部署即插即用)
cat > /lib/systemd/system/rknn-server.service <<'UNIT'
[Unit]
Description=Rockchip NPU rknn_server
After=multi-user.target

[Service]
ExecStart=/usr/bin/rknn_server
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

# 时钟:SATA 板有 HYM8563 RTC(内核 hctosys 开机恢复,timesyncd NTP 校准并回写);
# 无 SATA 板(v1.0)无 RTC,靠 timesyncd clock file(每分钟落盘)恢复,已不用 fake-hwclock

# 开发期账号: root/root。密码保留给串口 console —— 密钥丢失时的唯一后路,
# 且 ssh 已禁密码认证,密码弱不构成远程风险
echo root:root | chpasswd

# ssh 策略写成 drop-in:sshd_config 第 12 行的 Include 在主文件设置之前,
# 先出现的配置生效,drop-in 因此权威,且回滚只需删这一个文件
if [ -s /root/.ssh/authorized_keys ]; then
	cat > /etc/ssh/sshd_config.d/10-nvr.conf <<'SSHD'
# 仅密钥登录。密码认证关闭后,root 密码只对串口 console 有效。
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
SSHD
	# 主文件里那行显式的 yes 会让人误判实际策略,一并对齐
	sed -i 's/#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
else
	echo "无 authorized_keys:保持密码登录,避免造出登不上的机器"
	sed -i 's/#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
fi

mkdir -p /userdata /vcache
systemctl enable rknn-server.service

# smartctl 供 nvr-edge 读盘健康;smartd 后台守护默认关闭
# (无 SATA 板无 SMART 设备,起来即失败;SATA 板需要后台监控时现场 enable)
systemctl disable smartd.service 2>/dev/null || true

# 设备形态收敛:关掉对离线 NVR 无意义、还会写 eMMC/联网的周期任务与服务
#  apt-daily*:设备不在线升级;e2scrub*:只针对 LVM;dpkg-db-backup:每天备份 dpkg 库;
#  adbd:USB 是 host 模式,adb gadget 永远起不来,只是白占 1.4 秒启动时间
for u in apt-daily.timer apt-daily-upgrade.timer e2scrub_all.timer dpkg-db-backup.timer; do
	systemctl disable $u 2>/dev/null || true
	systemctl mask $u 2>/dev/null || true
done
systemctl disable adbd.service e2scrub_reap.service 2>/dev/null || true

# ssh host key:镜像里不带,首启由 nvr-ssh-hostkeys.service 生成,每台设备各不相同
rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub
systemctl enable nvr-ssh-hostkeys.service

# machine-id:同 ssh host key,是每台设备必须唯一的身份,不能随镜像出厂。
# 截成 0 字节是 systemd 约定的「首启」标记,PID 1 开机自行生成并落盘。
# 不清空的后果:全部设备共用一个 machine-id,而 systemd-networkd 的 DUID 默认
# 由它派生(实测板上为 DUID-EN/Vendor:0000ab11...),DHCPv6 靠 DUID 认设备会直接
# 撞车;D-Bus 机器标识、journald 上报的机器身份也一并重复。
: > /etc/machine-id
# dbus 的那份改为软链,否则它会留着镜像里的旧值,与 /etc/machine-id 不一致
ln -sf /etc/machine-id /var/lib/dbus/machine-id
# 空 machine-id 会让 ConditionFirstBoot=yes 成立,而 systemd-firstboot 的命令是
# --prompt-locale --prompt-timezone --prompt-root-password,会在串口上等人输入、
# 卡住启动。本镜像这三项都已在构建期定好,该单元必须 mask。
systemctl mask systemd-firstboot.service

# USB 网口 MAC:按 vendor 区第二个 MAC 生成 .link,由 udev 开机套用(不在运行中改 MAC)
if [ -f /lib/systemd/system/nvr-usb-eth-link.service ]; then
	systemctl enable nvr-usb-eth-link.service
fi

# 主机名唯一化(UMI-<SN 后 6 位>),两块板同名会被路由器派同一个 IP
# RPS:GMAC 单队列,中断固定在 CPU0,不开 RPS 时整条收包路径都挤在一个核上
if [ -f /lib/systemd/system/nvr-net-tuning.service ]; then
	systemctl enable nvr-net-tuning.service
fi

if [ -f /lib/systemd/system/nvr-hostname.service ]; then
	systemctl enable nvr-hostname.service
fi

# 串口控制台:内核 cmdline 是 console=tty1 console=ttyFIQ0,但 Debian 只自动启用
# getty@tty1(要接 HDMI+键盘)。不显式开这个,串口就只有单向打印、敲回车没反应,
# 而 ssh 又只认密钥 —— 密钥一丢就只能重烧,所谓"串口 root/root 兜底"根本不存在。
# ttyFIQ0 由 Rockchip FIQ debugger 提供(CONFIG_FIQ_DEBUGGER_CONSOLE_DEFAULT_ENABLE=y)。
systemctl enable serial-getty@ttyFIQ0.service

# 网络由 systemd-networkd 接管(配置见 /etc/systemd/network/10-lan.network)
systemctl enable systemd-networkd.service

# nvr-edge: 仅在 overlay-nvr 带了出厂基线时启用
if [ -f /lib/systemd/system/nvr.service ]; then
	systemctl enable nvr.service
fi

# vsync 同步插件(32 位 ARM 静态二进制,依赖内核 CONFIG_COMPAT=y)
if [ -f /lib/systemd/system/vsync.service ]; then
	systemctl enable vsync.service
fi

# 加速启动
# 注意: wait-online 被屏蔽后 network-online.target 开机即就绪,而 DHCP 仍在进行;
# nvr.service 的 After=network-online.target 因此形同虚设,首启窗口内组件下发与
# NTP 会先失败一轮(均有重试)。要改为真正等待网络,去掉此处的 mask 即可。
systemctl mask systemd-networkd-wait-online.service

# 精简: 清除 debootstrap 基底阶段已装入的文档/手册/无关语言
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*
find /usr/share/locale -mindepth 1 -maxdepth 1 \
	! -name 'en*' ! -name 'zh*' ! -name locale.alias -exec rm -rf {} +

systemctl set-default multi-user.target

# 清理(捕获模式保留 apt 缓存,由宿主侧取走后删除)
if [ ! -e /.capture-apt ]; then
	apt-get clean
fi
rm -rf /var/lib/apt/lists/* /packages
EOF

GLIBC_VER=$(sudo chroot $TARGET_ROOTFS_DIR /usr/bin/ldd --version 2>/dev/null | head -1 | grep -oE '[0-9.]+$' || echo '?')

sudo umount $TARGET_ROOTFS_DIR/dev/pts 2>/dev/null || true
sudo umount $TARGET_ROOTFS_DIR/dev
sudo umount $TARGET_ROOTFS_DIR/proc
sudo umount $TARGET_ROOTFS_DIR/sys

# 捕获:把本次 apt 下载的全部 deb 落库,下次构建即为离线钉版
if [ -e $TARGET_ROOTFS_DIR/.capture-apt ]; then
	mkdir -p $APT_MIRROR_DIR
	sudo cp -pf $TARGET_ROOTFS_DIR/var/cache/apt/archives/*.deb $APT_MIRROR_DIR/ 2>/dev/null || true
	sudo chown $(id -u):$(id -g) $APT_MIRROR_DIR/*.deb 2>/dev/null || true
	echo -e "\033[36m 已捕获 $(ls $APT_MIRROR_DIR/*.deb 2>/dev/null | wc -l) 个 deb 到 $APT_MIRROR_DIR \033[0m"
	sudo rm -f $TARGET_ROOTFS_DIR/.capture-apt
	sudo find $TARGET_ROOTFS_DIR/var/cache/apt/archives -name '*.deb' -delete
fi
sudo rm -rf $TARGET_ROOTFS_DIR/packages-mirror

# 设备端恢复在线源(板上 apt 正常使用官方仓库)
sudo tee $TARGET_ROOTFS_DIR/etc/apt/sources.list > /dev/null <<'EOF'
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

# 设备端默认 DNS: 覆盖掉 chroot 阶段拷入的构建机 resolv.conf
# (docker 构建时那份是 Docker Engine 生成的,指向宿主 systemd-resolved 的
#  127.0.0.53,板上完全无效)
# 无 NetworkManager / systemd-resolved,不存在任何会改写本文件的组件,
# 故这四条即设备最终生效的 DNS;DHCP 下发的 DNS 不参与
sudo rm -f $TARGET_ROOTFS_DIR/etc/resolv.conf
sudo tee $TARGET_ROOTFS_DIR/etc/resolv.conf > /dev/null <<'EOF'
nameserver 223.5.5.5
nameserver 223.6.6.6
nameserver 2400:3200::1
nameserver 2400:3200:baba::1
EOF

# 出厂基线写进 /etc/os-release(freedesktop 规范允许发行方扩展字段,按规范加 NVR_ 前缀)。
# 只写 OTA 之后运行时推不出来的出厂 nvr 版本;芯片、架构、glibc、librknnrt 版本
# 由 nvr-edge 运行时探测(镜像里写死会随 OTA 过时,rootfs 又由多颗芯片共用)。
if [ -f overlay-nvr/usr/local/lib/nvr/VERSION ]; then
	AGENT_VER=$(grep -oP '^version=\K.*' overlay-nvr/usr/local/lib/nvr/VERSION)
	AGENT_COMMIT=$(grep -oP '^commit=\K.*' overlay-nvr/usr/local/lib/nvr/VERSION)
	AGENT_SHA=$(grep -oP '^sha256=\K.*' overlay-nvr/usr/local/lib/nvr/VERSION)
	OS_RELEASE=$TARGET_ROOTFS_DIR/etc/os-release
	sudo sed -i '/^NVR_AGENT_/d' $OS_RELEASE
	sudo tee -a $OS_RELEASE > /dev/null <<EOF
NVR_AGENT_BASELINE="$AGENT_VER"
NVR_AGENT_COMMIT="$AGENT_COMMIT"
NVR_AGENT_SHA256="$AGENT_SHA"
EOF
fi

sudo rm -f $TARGET_ROOTFS_DIR/usr/bin/qemu-aarch64-static

echo -e "\033[32m bookworm rootfs 完成: $TARGET_ROOTFS_DIR (glibc $GLIBC_VER) \033[0m"
