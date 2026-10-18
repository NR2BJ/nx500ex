#!/bin/sh
# 메뉴 Self-Timer: 5초 셀프타이머. 화면에 항상 안내를 띄운다.
# 메뉴의 Timer Lamp 가 켜져 있으면(scripts/auto/timer_lamp.sh 있음) 앞쪽 AF 보조광이 4초간 천천히, 마지막 1초는 빠르게 깜빡인다.
# 브라케팅, 연사 설정은 그대로 적용된다. keyscan 이 기다리지 않도록 백그라운드로 실행한다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
L=/sys/devices/platform/leds-gpio/leds/af/brightness
popup "Self-timer 5s" 5
[ -f "$D/scripts/auto/timer_lamp.sh" ] || L=/dev/null
(
  for i in 1 2 3 4; do echo 1 > $L; sleep 0.5; echo 0 > $L; sleep 0.5; done
  for i in 1 2 3 4 5; do echo 1 > $L; sleep 0.1; echo 0 > $L; sleep 0.1; done
  st key push s1; st key push s2; st key release s2; st key release s1
) > /dev/null 2>&1 &
