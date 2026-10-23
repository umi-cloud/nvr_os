#!/bin/bash
# 出货固件唯一入口(宿主机跑):  ./release.sh <板型>
#   例: ./release.sh rk3566-nvr-ddr3-sata-v1.0      ./release.sh rv1126b-nvr-sata-v1.0
# kernel/、u-boot/、debian/ 的产物、rockdev/ 的软链与 .BoardConfig.mk 都是两颗芯片共用的全局状态,
# 手工切板、只重编一部分再打包会混出别的芯片的固件(2026-10 实测:RV1126B 内核配 RK3566 的 loader)。
# 这里加锁后显式切板、全量重编、打包前逐项核对(build.sh 的 check_updateimg_inputs),
# 产物放进 rockdev/<板型>/<板型>-<时间>/ 并生成 README/SHA256SUMS。约 15~20 分钟
set -eo pipefail
TOP=$(cd "$(dirname "$0")" && pwd)
cd "$TOP"

board=${1:?用法: ./release.sh <板型>,板型即 BoardConfig-<板型>.mk}
board=${board#BoardConfig-}
board=${board%.mk}
conf=$(ls device/rockchip/*/BoardConfig-"$board".mk 2>/dev/null | head -1)
if [ -z "$conf" ]; then
	echo "找不到板型 $board,可选:" >&2
	ls device/rockchip/*/BoardConfig-*.mk | sed 's#.*/BoardConfig-##; s#\.mk$##' >&2
	exit 2
fi

# 同一时刻只允许一次出货构建;直接调 build.sh 的构建不受此锁约束,出货前确认没有别人在编
mkdir -p rockdev
exec 9>rockdev/.release.lock
flock -n 9 || { echo "另一个 release.sh 正在构建,稍后再试" >&2; exit 1; }

ts=$(date +%Y%m%d-%H%M)
out=rockdev/$board/$board-$ts
mkdir -p "$out"
log=$out/build.log
echo "板型 $board → $out(日志 $log)"

ln -rsf "$conf" device/rockchip/.BoardConfig.mk

step() {
	echo "== $(date +%T) $*" | tee -a "$log"
	"$@" >>"$log" 2>&1 || { tail -30 "$log" >&2; echo "失败: $*,完整日志 $log" >&2; exit 1; }
}
step ./docker/run.sh ./build.sh uboot
step ./docker/run.sh ./build.sh kernel
step ./docker/run.sh ./build.sh debian
step ./mkfirmware.sh
step ./build.sh updateimg

cp rockdev/update.img "$out/update-$board-$ts.img"
for f in MiniLoaderAll.bin uboot.img boot.img parameter.txt; do
	cp -L "rockdev/$f" "$out/"
done

# README 只写自动取得的事实,不手写
# shellcheck disable=SC1090
dts=$(. "./$conf" >/dev/null 2>&1; echo "$RK_KERNEL_DTS")
product=$(. "./$conf" >/dev/null 2>&1; echo "$RK_TARGET_PRODUCT")
dirty=$(git status --porcelain)
{
	echo "板型      $board($conf)"
	echo "芯片      $product"
	echo "DTS       $dts"
	echo "内核      $(cat kernel/include/config/kernel.release)"
	echo "loader    $(basename "$(readlink -f rockdev/MiniLoaderAll.bin)")"
	echo "分区表    $(readlink -f rockdev/parameter.txt | sed "s#^$TOP/##")"
	echo "源码      $(git rev-parse --short HEAD) $(git log -1 --format=%s)"
	echo "构建时间  $(date '+%F %T')"
	echo
	echo "整包      update-$board-$ts.img(upgrade_tool uf;MaskRom 下先 db MiniLoaderAll.bin 再 uf)"
	echo "分区单烧  MiniLoaderAll.bin uboot.img boot.img parameter.txt"
	if [ -n "$dirty" ]; then
		echo
		echo "⚠ 构建时工作区有 $(echo "$dirty" | wc -l) 处未提交改动,已编进固件:"
		echo "$dirty"
	fi
} >"$out/README.txt"
(cd "$out" && sha256sum -- *.img *.bin parameter.txt >SHA256SUMS)
(cd "rockdev/$board" && zip -9 -qr "$board-$ts.zip" "$board-$ts" -x "*/build.log")

echo "完成: $out/"
echo "      rockdev/$board/$board-$ts.zip"
[ -z "$dirty" ] || echo "注意: 工作区有未提交改动,已写入 README"
