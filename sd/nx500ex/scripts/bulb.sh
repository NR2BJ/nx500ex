#!/bin/sh
# 벌브: 셔터를 BULB 로 바꾸고 정한 초만큼 셔터를 누르고 있다가 떼고, 원래 셔터 속도로 되돌린다.
# 시간은 메뉴 벌브 > 노출 (conf/bulb_sec). M 모드에서 쓴다. 드라이브는 그동안 단사로 바꿨다가 되돌린다.
# 끝나고 사진이 안 생겼으면(초점 실패) 알린다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중. EV 두 번으로 중단" 3; exit 0; }
[ "$(dial)" = DIALMODE_MANUAL ] || { popup "M 모드에서 사용" 3; exit 0; }
N=$(conf_get bulb_sec 30 1 3600)
IDX=$(shutter_idx)
case "$IDX" in ''|*[!0-9-]*) popup "셔터 값을 읽지 못함" 3; exit 0 ;; esac
popup "벌브 ${N}초. 2초 뒤 시작 (EV 두 번 = 중단)" 2
(
  fin() { keys_release; lcd_restore; [ "$IDX" != "$BULB_IDX" ] && shutter_set $IDX; drive_restore; rm -f $JOBPID; }
  trap 'fin; jlog "bulb stopped after $(( ($(now_cs) - T0) / 100 ))s"; exit 0' TERM
  T0=$(now_cs)
  drive_save; drive_single
  [ "$IDX" != "$BULB_IDX" ] && shutter_set $BULB_IDX
  sleep 2
  N0=$(dcim_count)
  jlog "bulb start ${N}s (shutter $IDX -> $(shutter_idx))"
  key push s1; key push s2
  T0=$(now_cs)
  # 카메라가 촬영 화면으로 바뀐 뒤에 덮는다
  sleep 1; lcd_dark
  END=$((T0 + N * 100))
  while [ $(now_cs) -lt $END ]; do sleep 0.2; done
  key release s2; key release s1
  jlog "bulb released after $(( ($(now_cs) - T0) / 100 ))s"
  lcd_restore
  # 초점을 못 잡으면 셔터가 눌리지 않는다. 노출이 끝난 뒤 사진이 생겼는지 확인
  if wait_file $N0 10; then R="벌브 완료"; else R="사진 없음 (초점 실패?)"; fi
  fin; jlog "bulb done: $R"
  popup "$R" 3
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
