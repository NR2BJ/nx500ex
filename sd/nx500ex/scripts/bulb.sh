#!/bin/sh
# 벌브: 셔터를 BULB 로 바꾼 뒤 셔터 버튼을 하드웨어 수준 (GPIO) 으로 정한 시간만큼 누르고 있는다. 30초 제한 없음.
# 시간은 메뉴 벌브 > 노출 (conf/bulb_sec, 초). M 모드에서. 끝나면 셔터 값을 원래대로 돌린다. EV 두 번이면 중단 (그때까지 노출).
# BULB 전환: 설정값을 30초 (-80) 로 쓰고 앞 다이얼을 한 클릭 (st key jog) 돌리면 바로 BULB (-96). 한 칸씩 27번 돌리는 것보다 빠르다.
#   설정값으로 BULB 를 바로 쓰면 앱이 30초 장노출로 다루므로 마지막 한 클릭은 꼭 다이얼로. 화면 끄기 (검은 창) 중에는 다이얼 클릭이 안 먹는다.
# 복귀: BULB 에서 다이얼 한 클릭 (30초) 뒤 설정값을 원래 값으로 (BULB 상태에서는 설정값 쓰기가 안 먹음).
# 초점: 반셔터 2초 뒤 셔터를 누르고 1.5초 안에 라이브 뷰가 멈추지 않으면 (노출이 시작되지 않음 = 초점 실패) 바로 놓고 알린다.
# 내력: st key 로 누른 셔터는 BULB 를 못 끝내고 (앱이 드라이버에 버튼 상태를 물어 봄) GPIO 로 누르면 물리 버튼과 같다 (2026-10-26, docs/research/2026-10-26-key-injection.md).
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중" 3; exit 0; }
[ "$(dial)" = DIALMODE_MANUAL ] || { popup "M 모드에서 사용" 3; exit 0; }
silent_on && { popup "무음 셔터에서는 벌브 불가" 3; exit 0; }
N=$(conf_get bulb_sec 60 1 3600)
IDX=$(shutter_idx)
case "$IDX" in ''|*[!0-9-]*) popup "셔터 값을 읽지 못함" 3; exit 0 ;; esac
popup "벌브 ${N}초 (EV 두번=중단)" 2
(
  restore_shutter() {
    [ "$IDX" = "$BULB_IDX" ] && return 0
    [ "$(shutter_idx)" = "$BULB_IDX" ] && { st key jog jog1_cw > /dev/null 2>&1; sleep 0.8; }
    shutter_set $IDX; sleep 1
    [ "$(shutter_idx)" = "$IDX" ] || jog_shutter_to $IDX
  }
  fin() { hw_release_all; keys_release; restore_shutter; drive_restore; rm -f $JOBPID; }
  trap 'fin; jlog "bulb stopped"; popup "벌브 중단" 2; exit 0' TERM
  drive_save; drive_single
  if [ "$IDX" != "$BULB_IDX" ]; then
    shutter_set -80; sleep 1.2
    st key jog jog1_ccw > /dev/null 2>&1; sleep 0.8
    [ "$(shutter_idx)" = "$BULB_IDX" ] || jog_shutter_to $BULB_IDX
    if [ "$(shutter_idx)" != "$BULB_IDX" ]; then fin; jlog "bulb: BULB 전환 실패 (idx $(shutter_idx))"; popup "BULB 로 못 바꿈<br>화면 끄기 중이면 먼저 걷으세요" 4; exit 0; fi
  fi
  sleep 0.5
  N0=$(dcim_count)
  jlog "bulb start ${N}s (shutter $IDX -> $(shutter_idx), gpio)"
  hw_s1 press; sleep 2
  hw_s2 press; T0=$(now_cs); sleep 1
  # 노출이 시작되면 라이브 뷰 버퍼가 멈춘다 (실기: 셔터 뒤 0.5초 안에 마지막 프레임, 그 뒤 변화 없음). AF 가 늦게 끝나면 시작도 늦으므로 최대 3.5초까지 본다
  STARTED=0; _k=0
  while [ $_k -lt 5 ]; do lv_moving || { STARTED=1; break; }; _k=$((_k + 1)); done
  if [ $STARTED = 0 ]; then
    hw_release_all; jlog "bulb: 초점 실패 (노출 시작 안 됨)"
    fin; popup "초점 실패: 노출이 시작되지 않음<br>반셔터로 초점을 맞춘 뒤 다시" 4; exit 0
  fi
  REST=$(( N * 100 - ($(now_cs) - T0) ))
  [ $REST -gt 0 ] && sleep $(( REST / 100 )).$(( REST % 100 ))
  hw_s2 release; sleep 0.5; hw_s1 release
  wait_file $N0 $((N + 30)) && R="벌브 ${N}초 완료" || R="사진 없음"
  fin; jlog "bulb done: $R"
  popup "$R" 3
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
