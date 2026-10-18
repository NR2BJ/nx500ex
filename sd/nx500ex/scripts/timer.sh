#!/bin/sh
# 메뉴 Self-Timer: 셀프타이머. 시간은 메뉴 Timer Delay 로 설정 (conf/timer_delay, 기본 5초).
# 화면에 항상 안내를 띄운다. 지금 드라이브 모드(브라케팅, 연사) 그대로 촬영한다.
# 메뉴의 Timer Lamp 가 켜져 있으면(scripts/auto/timer_lamp.sh 있음) 앞쪽 AF 보조광이
# 마지막 1초 전까지 천천히, 마지막 1초는 빠르게 깜빡인다.
# keyscan 이 기다리지 않도록 백그라운드로 실행한다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
N=$(cat "$D/conf/timer_delay" 2>/dev/null)
case "$N" in ''|*[!0-9]*) N=5 ;; esac
[ "$N" -lt 2 ] && N=2
[ "$N" -gt 60 ] && N=60
L=/sys/devices/platform/leds-gpio/leds/af/brightness
[ -f "$D/scripts/auto/timer_lamp.sh" ] || L=/dev/null
popup "Self-timer ${N}s" "$N"
(
  i=1; while [ $i -lt "$N" ]; do echo 1 > $L; sleep 0.5; echo 0 > $L; sleep 0.5; i=$((i+1)); done
  for i in 1 2 3 4 5; do echo 1 > $L; sleep 0.1; echo 0 > $L; sleep 0.1; done
  st key push s1; st key push s2; st key release s2; st key release s1
) > /dev/null 2>&1 &
