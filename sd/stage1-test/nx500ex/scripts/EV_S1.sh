#!/bin/sh
# 검증용: EV 를 누른 채 반셔터 -> AF 보조광 두 번 깜빡임, keyscan 상태 기록
for i in 1 2; do
  echo 1 > /sys/devices/platform/leds-gpio/leds/af/brightness; sleep 0.3
  echo 0 > /sys/devices/platform/leds-gpio/leds/af/brightness; sleep 0.3
done
LOG=/mnt/mmc/nx500ex/log/boot.log
{
  echo "$(date '+%Y-%m-%d %H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime) EV_S1"
  # pidof 가 없으므로 /proc 을 직접 훑는다
  for d in /proc/[0-9]*; do
    c=$(cat $d/comm 2>/dev/null)
    case "$c" in
      keyscan|bluetoothd*) echo "  $c pid=${d#/proc/} $(grep -E '^State' $d/status)";;
    esac
  done
} >> $LOG 2>&1
