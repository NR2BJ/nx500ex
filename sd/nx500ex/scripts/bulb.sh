#!/bin/sh
# 벌브: 셔터를 BULB 로 바꾼 뒤 셔터 버튼을 하드웨어 수준 (GPIO) 으로 정한 시간만큼 누르고 있는다. 30초 제한 없음.
# 시간은 메뉴 벌브 > 노출 (conf/bulb_sec, 초). M 모드에서. 끝나면 셔터 값을 원래대로 돌린다.
# 중단: 누르고 있는 동안 아무 키나 누르면 그때까지의 노출로 끝 (nxwake). 카메라가 먼저 끝내면 (재생 등) 파일이 생긴 것을 보고 놓는다. EV 두 번 (작업 중단) 도 됨.
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
    # BULB 면 한 클릭으로 30초로 나온 뒤 설정값 쓰기. 카메라가 사진 처리 중이면 안 먹을 수 있어 몇 번 다시 시도, 그래도 안 되면 다이얼로
    _t=0
    while [ $_t -lt 6 ]; do
      [ "$(shutter_idx)" = "$BULB_IDX" ] && { st key jog jog1_cw > /dev/null 2>&1; sleep 0.8; }
      shutter_set $IDX; sleep 1
      [ "$(shutter_idx)" = "$IDX" ] && return 0
      _t=$((_t + 1)); sleep 1
    done
    jog_shutter_to $IDX
  }
  fin() { [ -n "$WPID" ] && kill $WPID 2>/dev/null; hw_release_all; keys_release; restore_shutter; drive_restore; rm -f $JOBPID; }
  trap 'fin; jlog "bulb stopped"; popup "벌브 중단" 2; exit 0' TERM
  drive_save; drive_single
  screen_wake   # 화면 끄기 중이면 걷고 진행 (단축키로 켰을 때)
  if [ "$IDX" != "$BULB_IDX" ]; then
    shutter_set -80; sleep 1.2
    st key jog jog1_ccw > /dev/null 2>&1; sleep 0.8
    [ "$(shutter_idx)" = "$BULB_IDX" ] || jog_shutter_to $BULB_IDX
    if [ "$(shutter_idx)" != "$BULB_IDX" ]; then fin; jlog "bulb: BULB 전환 실패 (idx $(shutter_idx))"; popup "BULB 로 못 바꿈<br>화면 끄기 중이면 먼저 걷으세요" 4; exit 0; fi
  fi
  sleep 0.5
  # 촬영 화면이 아니면 (재생, 메뉴: 라이브 뷰가 멈춰 있음) 시작하지 않는다
  if ! lv_moving; then fin; jlog "bulb: 촬영 화면 아님 (라이브 뷰 멈춤)"; popup "촬영 화면에서 시작하세요" 3; exit 0; fi
  N0=$(dcim_count)
  jlog "bulb start ${N}s (shutter $IDX -> $(shutter_idx), gpio)"
  # 키 감시는 누르기 전에 띄운다 (노출 중에 입력 장치를 새로 열면 드라이버가 GPIO 를 입력으로 되돌려 벌브가 바로 끝난다, 2026-10-26). 우리 반셔터/셔터 (125, 126) 는 무시
  NXWAKE_IGNORE=125,126 "$D/bin/nxwake" 300 $((N + 20)) < /dev/null > /dev/null 2>&1 & WPID=$!
  sleep 0.3
  hw_s1 press; sleep 2
  hw_s2 press; T0=$(now_cs); sleep 1
  # 노출이 시작되면 라이브 뷰 버퍼가 멈춘다 (실기: 셔터 뒤 0.5초 안에 마지막 프레임, 그 뒤 변화 없음). AF 가 늦게 끝나면 시작도 늦으므로 최대 3.5초까지 본다
  STARTED=0; _k=0
  while [ $_k -lt 5 ]; do lv_moving || { STARTED=1; break; }; _k=$((_k + 1)); done
  if [ $STARTED = 0 ]; then
    kill $WPID 2>/dev/null; hw_release_all; jlog "bulb: 초점 실패 (노출 시작 안 됨)"
    fin; popup "초점 실패: 노출이 시작되지 않음<br>반셔터로 초점을 맞춘 뒤 다시" 4; exit 0
  fi
  # 누르고 있는 동안: 아무 키나 누르면 (nxwake) 그때까지로 끝내고, 카메라가 먼저 끝내 파일이 생기면 (재생 키 등) 바로 놓는다
  END="끝"; _c=0
  while :; do
    EL=$(( $(now_cs) - T0 ))
    [ $EL -ge $(( N * 100 )) ] && break
    [ -d /proc/$WPID ] || { END="키로 중단 ($((EL / 100))초)"; break; }
    _c=$((_c + 1)); [ $((_c % 4)) = 0 ] && [ "$(dcim_count)" -gt "$N0" ] && { END="카메라가 먼저 끝냄"; break; }
    sleep 0.5
  done
  kill $WPID 2>/dev/null
  hw_s2 release; sleep 0.5; hw_s1 release
  case "$END" in 끝) wait_file $N0 $((N + 30)) && R="벌브 ${N}초 완료" || R="사진 없음" ;; *) wait_file $N0 $((EL / 100 + 30)) > /dev/null; R="벌브 $END" ;; esac
  fin; jlog "bulb done: $R"
  popup "$R" 3
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
