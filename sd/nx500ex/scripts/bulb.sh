#!/bin/sh
# 벌브: 반셔터+셔터를 정한 초만큼 누르고 있다가 뗀다.
# 카메라를 M 모드, 셔터 속도 BULB 로 두고 쓴다. 연사 드라이브면 그동안 계속 찍히므로 단사로 둘 것.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중. EV 두 번으로 중단" 3; exit 0; }
[ "$(dial)" = DIALMODE_MANUAL ] || { popup "M 모드, 셔터 BULB 에서 사용" 3; exit 0; }
N=$(ask "벌브 노출 시간 (초, 1~3600):" "$(conf_get bulb_sec 30)" 1 3600) || exit 0
conf_set bulb_sec "$N"
popup "벌브 ${N}초. 2초 뒤 시작 (EV 두 번 = 중단)" 2
(
  fin() { st key release s2 > /dev/null 2>&1; st key release s1 > /dev/null 2>&1; lcd_restore; rm -f $JOBPID; }
  trap 'fin; jlog "bulb stopped at ${i}s"; exit 0' TERM
  i=0
  sleep 2
  lcd_dark
  jlog "bulb start ${N}s"
  st key push s1 > /dev/null 2>&1; st key push s2 > /dev/null 2>&1
  while [ $i -lt "$N" ]; do sleep 1; i=$((i+1)); done
  fin; jlog "bulb done ${N}s"
  popup "벌브 완료" 2
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
