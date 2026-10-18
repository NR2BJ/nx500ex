#!/bin/sh
# 벌브: 셔터를 BULB 로 바꾸고 정한 초만큼 셔터를 누르고 있다가 떼고, 원래 셔터 속도로 되돌린다.
# 시간은 메뉴 벌브 > 노출 (conf/bulb_sec). M 모드에서 쓴다. 연사 드라이브면 그동안 계속 찍히므로 단사로 둘 것.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중. EV 두 번으로 중단" 3; exit 0; }
[ "$(dial)" = DIALMODE_MANUAL ] || { popup "M 모드에서 사용" 3; exit 0; }
N=$(conf_get bulb_sec 30 1 3600)
IDX=$(shutter_idx)
case "$IDX" in ''|*[!0-9-]*) popup "셔터 값을 읽지 못함" 3; exit 0 ;; esac
popup "벌브 ${N}초. 2초 뒤 시작 (EV 두 번 = 중단)" 2
(
  fin() { keys_release; lcd_restore; [ "$IDX" != "$BULB_IDX" ] && shutter_set $IDX; rm -f $JOBPID; }
  trap 'fin; jlog "bulb stopped after $(( ($(now_cs) - T0) / 100 ))s"; exit 0' TERM
  T0=$(now_cs)
  [ "$IDX" != "$BULB_IDX" ] && shutter_set $BULB_IDX
  sleep 2
  jlog "bulb start ${N}s (shutter $IDX -> $(shutter_idx))"
  key push s1; key push s2
  T0=$(now_cs)
  # 카메라가 촬영 화면으로 바뀐 뒤에 덮는다
  sleep 1; lcd_dark
  END=$((T0 + N * 100))
  while [ $(now_cs) -lt $END ]; do sleep 0.2; done
  key release s2; key release s1
  jlog "bulb released after $(( ($(now_cs) - T0) / 100 ))s"
  fin; jlog "bulb done"
  popup "벌브 완료" 2
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
