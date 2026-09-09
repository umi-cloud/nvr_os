#!/bin/bash

flag="true"
while (true)
do
	if [ $flag = "true" ]; then
		flag="false"		 
		echo 1 > /sys/devices/platform/openvfd/attr/agingled
		echo 0 > /sys/class/leds/sys_led/brightness
	else
		flag="true"
		echo 0 > /sys/devices/platform/openvfd/attr/agingled
		echo 1 > /sys/class/leds/sys_led/brightness
	fi
	sleep 1
done
