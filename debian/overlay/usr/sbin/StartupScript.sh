#!/bin/bash

killall rtk_hciattach
echo 0 > /sys/class/rfkill/rfkill0/state
echo 0 > /proc/bluetooth/sleep/btwrite
sleep 1
echo 1 > /sys/class/rfkill/rfkill0/state
echo 1 > /proc/bluetooth/sleep/btwrite
sleep 1
insmod  /lib/modules/88x2cs.ko 
insmod  /lib/modules/hci_uart.ko 
rtk_hciattach -n -s 115200 /dev/ttyS1 rtk_h5 &
sleep 1

set_tz_offset.sh
