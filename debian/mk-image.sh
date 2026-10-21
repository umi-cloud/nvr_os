#!/bin/bash -e

TARGET_ROOTFS_DIR=./binary
ROOTFSIMAGE=linaro-rootfs.img
# 镜像只留少量空闲:设备每次开机由 fstab 的 x-systemd.growfs 在线扩到整个分区(5G),
# 镜像里的空闲空间只会让整包变大(原先 300MB,占镜像 27%)。mkfs.ext4 -d 建出的镜像
# resize2fs 收不动(-P 估算即为当前大小),所以直接控制建时的余量;实测空闲约等于这个值
EXTRA_SIZE_MB=96
# 扩容生效前的开机写入(machine-id、ssh host key 等)至少要这么多空闲
MIN_FREE_MB=64
IMAGE_SIZE_MB=$(( $(sudo du -sh -m ${TARGET_ROOTFS_DIR} | cut -f1) + ${EXTRA_SIZE_MB} ))


echo Making rootfs!

if [ -e ${ROOTFSIMAGE} ]; then
	rm ${ROOTFSIMAGE}
fi

sudo ./post-build.sh ${TARGET_ROOTFS_DIR}

dd if=/dev/zero of=${ROOTFSIMAGE} bs=1M count=0 seek=${IMAGE_SIZE_MB}

sudo mkfs.ext4 -d ${TARGET_ROOTFS_DIR} ${ROOTFSIMAGE}

FREE_MB=$(sudo dumpe2fs -h ${ROOTFSIMAGE} 2>/dev/null |
	awk -F': *' '/^Free blocks/{f=$2} /^Block size/{b=$2} END{print int(f*b/1048576)}')
if [ "$FREE_MB" -lt "$MIN_FREE_MB" ]; then
	echo "rootfs 镜像空闲只有 ${FREE_MB}MB(< ${MIN_FREE_MB}MB),调大 EXTRA_SIZE_MB" >&2
	exit 1
fi

echo Rootfs Image: ${ROOTFSIMAGE} ${IMAGE_SIZE_MB}MB,空闲 ${FREE_MB}MB
