#!/bin/sh
# 검증용: EV 를 누른 채 반셔터 -> AF 보조광 두 번 깜빡임
for i in 1 2; do
  echo 1 > /sys/devices/platform/leds-gpio/leds/af/brightness; sleep 0.3
  echo 0 > /sys/devices/platform/leds-gpio/leds/af/brightness; sleep 0.3
done
echo "$(date '+%Y-%m-%d %H:%M:%S') EV_S1" >> /mnt/mmc/nx500ex/log/boot.log
