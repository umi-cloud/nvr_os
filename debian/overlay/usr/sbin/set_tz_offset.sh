#!/bin/bash

#refresh timezone
while (true)
do
        date +"%z" > /sys/devices/platform/openvfd/attr/led
        sleep 10
done

