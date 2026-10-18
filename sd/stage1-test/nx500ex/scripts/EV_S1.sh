#!/bin/sh
# 검증용: EV 를 누른 채 반셔터 -> AF 보조광 두 번 깜빡임, 표식 기록
for i in 1 2; do
  echo 1 > /sys/devices/platform/leds-gpio/leds/af/brightness; sleep 0.3
  echo 0 > /sys/devices/platform/leds-gpio/leds/af/brightness; sleep 0.3
done
echo "$(date '+%H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime) ===== EV_S1 marker" >> /tmp/nx500ex-mon.log
{
  echo "$(date '+%Y-%m-%d %H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime) EV_S1"
  # 블루투스 칩 상태 (UP/DOWN, 주소). 칩이 내려가 있으면 hci0 가 없다고 나온다.
  /usr/sbin/hciconfig hci0 2>&1 | grep -E 'hci0|BD Address|UP|DOWN' | sed 's/^/  bt /'
} >> /mnt/mmc/nx500ex/log/boot.log
sync
