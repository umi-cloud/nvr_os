#! /bin/bash

while true
do
	echo "==================================================="
	echo "Led CMD:"
        echo "#c0  -->Turn off all lights"
	echo "#c1  -->Turn off time lights only"
	echo "#s0  -->Turn on all lights"
	echo "#s1  -->Turn on time lights only"
	echo "#mxcccc: mx(m0~m5)   cccc(4 characters)"
	echo "=================================================="

	echo "Turn on all lights"
	echo  "#s0" > /sys/devices/platform/openvfd/attr/led
	sleep 1
	echo "Turn off time lights"
	echo  "#c1" > /sys/devices/platform/openvfd/attr/led
	sleep 1
	
	echo "Turn off all light"
	echo  "#c0" > /sys/devices/platform/openvfd/attr/led
	sleep 1
	echo "Trun on time lights"
	echo  "#s1" > /sys/devices/platform/openvfd/attr/led
	sleep 4

	echo "#c0"  > /sys/devices/platform/openvfd/attr/led
	echo  1 > /sys/devices/platform/openvfd/attr/b6
	sleep 2
	echo  " b0 ~ b6"
	echo  1 > /sys/devices/platform/openvfd/attr/b1
	echo  1 > /sys/devices/platform/openvfd/attr/b0
	sleep 2

	echo "#c0"  > /sys/devices/platform/openvfd/attr/led
	sleep 1

	mode=0
	while true; do
		echo  "#m${mode}8888" > /sys/devices/platform/openvfd/attr/led
		sleep 1 
        	let mode++	
		[ ${mode} -gt 5 ] || continue

		echo  "#m21234" > /sys/devices/platform/openvfd/attr/led
		sleep 2
		echo  "#m3ABCD" > /sys/devices/platform/openvfd/attr/led
		sleep 2
		break;
	done
done
