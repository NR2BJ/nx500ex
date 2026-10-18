#!/bin/sh
# 장노출 (메뉴 이름 "벌브"): 셔터 속도를 정한 시간(1/3 스톱 표준값 중 그 이하에서 가장 긴 값, 최대 30초)으로 맞춰
# 보통 단사로 찍고 셔터를 되돌린다. 시간은 메뉴 벌브 > 노출 (conf/bulb_sec). M 모드에서 쓴다.
# 카메라의 BULB 는 스크립트의 셔터 떼기나 st cap capt stop 으로 끝나지 않고 30초에 끝났다 (2026-10-19 실기).
# 그래서 30초를 넘는 노출은 하지 않는다. 무음 셔터는 1/5 초보다 긴 노출이 안 되므로 거부한다.
# 드라이브는 그동안 단사로 바꿨다가 되돌린다. 사진이 안 생기면(초점 실패) 알린다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중" 3; exit 0; }
[ "$(dial)" = DIALMODE_MANUAL ] || { popup "M 모드에서 사용" 3; exit 0; }
silent_on && { popup "무음 셔터에서는 장노출 불가<br>(1/5초까지만 됨)" 4; exit 0; }
N=$(conf_get bulb_sec 30 1 30)
IDX=$(shutter_idx)
case "$IDX" in ''|*[!0-9-]*) popup "셔터 값을 읽지 못함" 3; exit 0 ;; esac
T=1; V=0
for p in 1:0 2:-16 3:-27 4:-32 5:-37 6:-43 8:-48 10:-53 13:-59 15:-64 20:-69 25:-75 30:-80; do
  [ "${p%:*}" -le "$N" ] && { T=${p%:*}; V=${p#*:}; }
done
popup "장노출 ${T}초 (EV 두번=중단)" 2
(
  fin() { keys_release; lcd_restore; shutter_set $IDX; drive_restore; rm -f $JOBPID; }
  trap 'fin; jlog "bulb stopped"; exit 0' TERM
  drive_save; drive_single
  shutter_set $V
  sleep 2
  N0=$(dcim_count)
  jlog "bulb start ${T}s (shutter $IDX -> $(shutter_idx))"
  s1_hold; sleep 0.5; s2_click; key release s1
  sleep 1; lcd_dark
  wait_file $N0 $((T + 10)) && R="장노출 완료" || R="사진 없음 (초점 실패?)"
  fin; jlog "bulb done: $R"
  popup "$R" 3
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
