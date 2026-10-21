# nvr-factory 公共函数,由主程序与各测试项 source。
# 测试项约定:stdout 只输出一行结论(测量值或失败原因,英文),过程细节写 stderr;退出码 0 = 通过。

FACTORY_LIB=/usr/local/lib/nvr-factory
FACTORY_RUN=/run/nvr-factory
NPU_BIN=$FACTORY_LIB/npu-check
NPU_MODEL=$FACTORY_LIB/npu-check.rknn
# 阶段标记存厂商区自定义 ID 0x20,与 SN(VENDOR_SN_ID)/MAC(VENDOR_LAN_MAC_ID)并列,
# 恢复出厂与整机重烧都不擦
STAGE_ID=VENDOR_CUSTOM_ID_20

. /etc/nvr/factory.conf
# 调试用覆盖,在 /run 下,重启即失效,不会带进出厂状态
[ -f "$FACTORY_RUN/factory.conf" ] && . "$FACTORY_RUN/factory.conf"

# 板型:rk3566-nvr-sata / rk3566-nvr / 空(未知)
board() {
	case "$(tr '\0' ' ' < /proc/device-tree/compatible 2>/dev/null)" in
	*rockchip,rk3566-nvr-ddr3-sata-v1.0*) echo rk3566-nvr-sata ;;
	*rockchip,rk3566-nvr-ddr3-v1.0*) echo rk3566-nvr ;;
	esac
}

# 读厂商区某 ID 的原始字节(-t file 落盘,不经 vendor_storage 的打印格式);未写过时输出为空
vendor_read() {
	local f
	f=$(mktemp)
	vendor_storage -r "$1" -t file -i "$f" >/dev/null 2>&1
	tr -d '\0' < "$f"
	rm -f "$f"
}

stage_get() { vendor_read "$STAGE_ID"; }

# 写入后回读校验:vendor_storage -w 无论成败都退出 0(见 nvr-provision 文件头)
stage_set() {
	vendor_storage -w "$STAGE_ID" -t string -i "$1" >/dev/null 2>&1
	sync
	[ "$(stage_get)" = "$1" ] || { echo "failed to write stage: $1" >&2; return 1; }
}

sn_get() { vendor_read VENDOR_SN_ID | grep -aoE 'UMNVR[0-9A-Za-z]+' | head -1; }

# 所有 thermal zone 的最高温度(摄氏度)
max_temp_c() {
	local z t max=0
	for z in /sys/class/thermal/thermal_zone*/temp; do
		t=$(cat "$z")
		[ "$t" -gt "$max" ] && max=$t
	done
	echo $((max / 1000))
}

# 网口检查:有 link、协商到 $2 Mbps 全双工、DHCP 拿到地址、对网关(或 ETH_PING_TARGET)ping 零丢包。
# 成功输出一行结论,失败输出原因并返回 1
nic_check() {
	local ifc=$1 want=$2 n=/sys/class/net/$1 i speed duplex t out
	[ -d "$n" ] || { echo "no $ifc"; return 1; }
	for i in $(seq 10); do
		[ "$(cat "$n/carrier" 2>/dev/null)" = 1 ] && break
		sleep 1
	done
	[ "$(cat "$n/carrier" 2>/dev/null)" = 1 ] || { echo "$ifc no link"; return 1; }
	speed=$(cat "$n/speed"); duplex=$(cat "$n/duplex")
	[ "$speed" = "$want" ] && [ "$duplex" = full ] ||
		{ echo "$ifc link ${speed}M/${duplex}, need ${want}M/full"; return 1; }
	for i in $(seq 30); do
		ip -4 -o addr show dev "$ifc" | grep -q inet && break
		sleep 1
	done
	ip -4 -o addr show dev "$ifc" | grep -q inet || { echo "$ifc no DHCP address"; return 1; }
	t=${ETH_PING_TARGET:-$(ip -4 route show default dev "$ifc" | awk '{print $3; exit}')}
	[ -n "$t" ] || { echo "$ifc no default gateway and ETH_PING_TARGET unset"; return 1; }
	out=$(ping -c "$ETH_PING_COUNT" -i 0.2 -W 1 -I "$ifc" "$t" 2>&1)
	echo "$out" >&2
	echo "$out" | grep -q ' 0% packet loss' ||
		{ echo "$ifc ping $t $(echo "$out" | grep -o '[0-9.]*% packet loss')"; return 1; }
	echo "$ifc ${want}M/full, ping $t 0% loss"
}

# 块设备顺序读速率(MB/s),绕过页缓存。$1=设备 $2=读取量(MB)
read_mbps() {
	local t0 t1
	t0=$(date +%s%N)
	dd if="$1" of=/dev/null bs=1M count="$2" iflag=direct 2>/dev/null || return 1
	t1=$(date +%s%N)
	echo $(($2 * 1000000000 / (t1 - t0 + 1)))
}

# 块设备所在 USB 设备的协商速率(Mbps);非 USB 设备输出空
usb_speed_of() {
	local d
	d=$(readlink -f "/sys/block/$1/device")
	while [ -n "$d" ] && [ "$d" != / ]; do
		[ -f "$d/speed" ] && { cat "$d/speed"; return; }
		d=${d%/*}
	done
}

# JSON 字符串转义:反斜杠与引号转义,其余控制字符(含换行、制表符)删掉
json_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\000-\037'; }
