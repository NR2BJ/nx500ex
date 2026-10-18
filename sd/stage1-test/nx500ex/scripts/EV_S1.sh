#!/bin/sh
# 검증용: EV 를 누른 채 반셔터 -> AF 보조광 두 번 깜빡임, keyscan 상태 기록
for i in 1 2; do
  echo 1 > /sys/devices/platform/leds-gpio/leds/af/brightness; sleep 0.3
  echo 0 > /sys/devices/platform/leds-gpio/leds/af/brightness; sleep 0.3
done
LOG=/mnt/mmc/nx500ex/log/boot.log
{
  echo "$(date '+%Y-%m-%d %H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime) EV_S1"
  for p in $(pidof keyscan); do
    echo "  keyscan pid=$p $(grep -E '^State' /proc/$p/status)"
    sed "s/^/  keyscan cgroup /" /proc/$p/cgroup
  done
  for p in $(pidof bluetoothd.orig bluetoothd); do
    echo "  bluetoothd pid=$p $(grep -E '^State' /proc/$p/status)"
  done
} >> $LOG 2>&1
