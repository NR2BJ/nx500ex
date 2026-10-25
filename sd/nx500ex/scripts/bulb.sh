#!/bin/sh
# 벌브: 앞 다이얼을 돌려 셔터를 BULB 로 바꾼 뒤 셔터 버튼을 하드웨어 수준 (GPIO) 으로 정한 시간만큼 누르고 있는다. 30초 제한 없음.
# 시간은 메뉴 벌브 > 노출 (conf/bulb_sec, 초). M 모드에서. 끝나면 셔터 값을 원래대로 돌린다. EV 두 번이면 중단 (그때까지 노출).
# 내력: st key 로 누른 셔터는 BULB 를 못 끝내고 (앱이 드라이버에 버튼 상태를 물어 봄), prefman 으로 BULB 를 쓰면 30초 장노출이 됐다 (2026-10-19).
#   GPIO 로 누르면 물리 버튼과 같아 40초 벌브가 EXIF 40.0초로 찍혔다 (2026-10-26). 장노출 노이즈 제거가 켜져 있으면 노출 시간만큼 더 기다린다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중" 3; exit 0; }
[ "$(dial)" = DIALMODE_MANUAL ] || { popup "M 모드에서 사용" 3; exit 0; }
silent_on && { popup "무음 셔터에서는 벌브 불가" 3; exit 0; }
N=$(conf_get bulb_sec 60 1 3600)
IDX=$(shutter_idx)
case "$IDX" in ''|*[!0-9-]*) popup "셔터 값을 읽지 못함" 3; exit 0 ;; esac
popup "벌브 ${N}초 (EV 두번=중단)" 2
(
  fin() { hw_release_all; keys_release; [ "$IDX" != "$BULB_IDX" ] && jog_shutter_to $IDX; drive_restore; rm -f $JOBPID; }
  trap 'fin; jlog "bulb stopped"; exit 0' TERM
  drive_save; drive_single
  if [ "$IDX" != "$BULB_IDX" ] && ! jog_shutter_to $BULB_IDX; then fin; jlog "bulb: BULB 전환 실패 (idx $(shutter_idx))"; popup "BULB 로 못 바꿈" 3; exit 0; fi
  sleep 0.5
  N0=$(dcim_count)
  jlog "bulb start ${N}s (shutter $IDX -> $(shutter_idx), gpio)"
  hw_s1 press; sleep 2
  hw_s2 press; sleep $N; hw_s2 release; sleep 0.5; hw_s1 release
  wait_file $N0 $((N + 30)) && R="벌브 ${N}초 완료" || R="사진 없음 (초점 실패?)"
  fin; jlog "bulb done: $R"
  popup "$R" 3
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
