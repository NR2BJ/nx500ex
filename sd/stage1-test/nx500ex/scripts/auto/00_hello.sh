#!/bin/sh
# 검증용: 켤 때마다 AF 보조광 1초, 기록 남김
echo 1 > /sys/devices/platform/leds-gpio/leds/af/brightness
sleep 1
echo 0 > /sys/devices/platform/leds-gpio/leds/af/brightness
echo "$(date '+%Y-%m-%d %H:%M:%S') auto/00_hello, uptime $(cut -d' ' -f1 /proc/uptime)" >> /mnt/mmc/nx500ex/log/boot.log
sync
