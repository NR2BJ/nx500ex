#!/bin/sh
# HDR 5장: M 모드에서 셔터 속도만 바꿔 -2s, -s, 0, +s, +2s 다섯 장 (s = 입력한 EV 간격).
# 셔터 속도 값(APPPREF_SHUTTER_SPEED_INDEX)은 1스톱 = 16 (실기 EXIF 확인: 1/30 기준 2 EV 간격이 1/500, 1/125, 1/30, 1/8, 1/2).
# 범위는 30초(-80) ~ 1/6000(200). 값은 log/jobs.log 에 남긴다.
# 첫 장은 지금 AF 설정으로 찍고 사진이 생기지 않으면(초점 실패) 중단, 생기면 MF 로 고정. 끝나면 AF 와 셔터를 되돌린다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중. EV 두 번으로 중단" 3; exit 0; }
[ "$(dial)" = DIALMODE_MANUAL ] || { popup "M 모드에서 사용 (가운데 노출을 먼저 맞춘다)" 3; exit 0; }
E=$(ask "HDR 간격 (EV, 1~3):" "$(conf_get hdr_ev 2)" 1 3) || exit 0
conf_set hdr_ev "$E"
IDX=$(shutter_idx)
case "$IDX" in ''|*[!0-9-]*) popup "셔터 값을 읽지 못함" 3; exit 0 ;; esac
popup "HDR 5장 ±$((2*E))EV 시작 (EV 두 번 = 중단)" 2
(
  fin() { shutter_set $IDX; af_restore; rm -f $JOBPID; }
  trap 'fin; jlog "hdr stopped"; exit 0' TERM
  S=$((16 * E))
  first=1
  jlog "hdr start idx=$IDX step=$S"
  for e in -2 -1 0 1 2; do
    v=$((IDX - e * S))      # 값이 클수록 빠른 셔터(어두움). e=-2 가 가장 어두운 장
    [ $v -gt 200 ] && v=200
    [ $v -lt -80 ] && v=-80
    shutter_set $v
    sleep 0.3
    if [ $first = 1 ]; then
      # 첫 장은 지금 AF 설정으로. 사진이 생기지 않으면(초점 실패) 중단, 생기면 MF 로 고정
      first=0
      if ! first_shot 8; then fin; jlog "hdr stopped: no photo on first shot (focus failed?)"; popup "첫 장 초점 실패로 중단" 3; exit 0; fi
      jlog "hdr shot ev=$((e * E)) idx=$v up=$(cut -d' ' -f1 /proc/uptime)"
      continue
    fi
    shoot
    jlog "hdr shot ev=$((e * E)) idx=$v up=$(cut -d' ' -f1 /proc/uptime)"
    # 노출과 저장이 끝나기 전에 다음 셔터 값을 바꾸지 않도록 기다린다 (1초 이상 노출은 1초 + 노출 시간)
    if [ $v -le 0 ]; then
      e2=1; n=$((-v)); while [ $n -ge 16 ]; do e2=$((e2 * 2)); n=$((n - 16)); done
      sleep $((e2 + 1))
    elif [ $v -lt 16 ]; then sleep 2
    else sleep 1
    fi
  done
  fin; jlog "hdr done"
  popup "HDR 완료" 2
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
