#!/bin/sh
# 장노출 (메뉴 이름 "벌브"). 시간은 메뉴 벌브 > 노출 (conf/bulb_sec). M 모드에서 쓴다.
#  30초 이하: 셔터 속도를 그 시간(1/3 스톱 표준값 중 가장 가까운 값)으로 맞춰 보통 단사로 찍고 셔터를 되돌린다.
#  30초 초과: 셔터를 BULB 로 바꾸고 셔터를 누르고 있다가 떼며, 캡처 중지 명령(st cap capt stop)도 보낸다 (시험 중).
# 카메라의 BULB 는 스크립트가 보낸 "셔터 떼기" 로 끝나지 않고 30초까지 갔다 (2026-10-19 실기). 펌웨어의 BULB 는
# 노출 프레임 더하기와 검은 프레임 촬영을 하는 별도 경로다 (Bulb_Image, Bulb_Black, FrameAdd).
# 드라이브는 그동안 단사로 바꿨다가 되돌린다. 사진이 안 생기면(초점 실패) 알린다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중. EV 두 번으로 중단" 3; exit 0; }
[ "$(dial)" = DIALMODE_MANUAL ] || { popup "M 모드에서 사용" 3; exit 0; }
N=$(conf_get bulb_sec 30 1 3600)
IDX=$(shutter_idx)
case "$IDX" in ''|*[!0-9-]*) popup "셔터 값을 읽지 못함" 3; exit 0 ;; esac
# 초 -> 셔터 값 (1스톱 = 16, 1초 = 0). N 이하에서 가장 긴 표준값
LONG=0; T=1
if [ "$N" -le 30 ]; then
  for p in 1:0 2:-16 3:-27 4:-32 5:-37 6:-43 8:-48 10:-53 13:-59 15:-64 20:-69 25:-75 30:-80; do
    [ "${p%:*}" -le "$N" ] && { T=${p%:*}; V=${p#*:}; }
  done
else
  LONG=1; T=$N; V=$BULB_IDX
fi
popup "장노출 ${T}초. 2초 뒤 시작 (EV 두 번 = 중단)" 2
(
  fin() { keys_release; lcd_restore; shutter_set $IDX; drive_restore; rm -f $JOBPID; }
  trap '[ $LONG = 1 ] && st cap capt stop > /dev/null 2>&1; fin; jlog "bulb stopped"; exit 0' TERM
  drive_save; drive_single
  shutter_set $V
  sleep 2
  N0=$(dcim_count)
  jlog "bulb start ${T}s (shutter $IDX -> $(shutter_idx), long=$LONG)"
  if [ $LONG = 0 ]; then
    s1_hold; sleep 0.5; s2_click; key release s1
    sleep 1; lcd_dark
    wait_file $N0 $((T + 10)) && R="장노출 완료" || R="사진 없음 (초점 실패?)"
  else
    key push s1; key push s2
    T0=$(now_cs)
    sleep 1; lcd_dark
    END=$((T0 + T * 100))
    while [ $(now_cs) -lt $END ]; do sleep 0.2; done
    key release s2; key release s1
    st cap capt stop > /dev/null 2>&1
    jlog "bulb released after $(( ($(now_cs) - T0) / 100 ))s, capt stop sent"
    wait_file $N0 $((T + 10)) && R="장노출 완료" || R="사진 없음 (초점 실패?)"
  fi
  fin; jlog "bulb done: $R"
  popup "$R" 3
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
