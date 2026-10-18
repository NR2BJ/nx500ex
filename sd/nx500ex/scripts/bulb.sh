#!/bin/sh
# 벌브: 셔터를 BULB 로 바꾸고 정한 초만큼 누르고 있다가 떼고, 원래 셔터 속도로 되돌린다.
# M 모드에서 쓴다. 연사 드라이브면 그동안 계속 찍히므로 단사로 둘 것.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중. EV 두 번으로 중단" 3; exit 0; }
[ "$(dial)" = DIALMODE_MANUAL ] || { popup "M 모드에서 사용" 3; exit 0; }
N=$(ask "벌브 노출 시간 (초, 1~3600):" "$(conf_get bulb_sec 30)" 1 3600) || exit 0
conf_set bulb_sec "$N"
IDX=$(shutter_idx)
case "$IDX" in ''|*[!0-9-]*) popup "셔터 값을 읽지 못함" 3; exit 0 ;; esac
popup "벌브 ${N}초. 2초 뒤 시작 (EV 두 번 = 중단)" 2
(
  fin() { sta key release s2; sta key release s1; lcd_restore; [ "$IDX" != "$BULB_IDX" ] && shutter_set $IDX; rm -f $JOBPID; }
  trap 'fin; jlog "bulb stopped at ${i}s"; exit 0' TERM
  i=0
  [ "$IDX" != "$BULB_IDX" ] && shutter_set $BULB_IDX
  sleep 2
  jlog "bulb start ${N}s (shutter $IDX -> $(shutter_idx))"
  sta key push s1; sleep 0.3; sta key push s2
  # 카메라가 촬영 화면으로 바뀐 뒤에 덮는다
  sleep 1; lcd_dark
  i=1; while [ $i -lt "$N" ]; do sleep 1; i=$((i+1)); done
  fin; jlog "bulb done ${N}s"
  popup "벌브 완료" 2
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
