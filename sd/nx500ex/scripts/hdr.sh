#!/bin/sh
# HDR 5장: M 모드에서 셔터 속도만 바꿔 -2s, -s, 0, +s, +2s 다섯 장 (s = 입력한 EV 간격).
# 셔터 속도 값(APPPREF_SHUTTER_SPEED_INDEX, prefman 0 0xa340)은 1스톱 = 16 으로 추정 (NX-KS 1HDR.sh 의 값 65~200 이 1/15~1/6000).
# 실제 셔터 속도는 사진 EXIF 로 확인할 것. 값은 log/jobs.log 에 남긴다. 찍는 동안 MF 로 두고 끝나면 AF 와 셔터를 되돌린다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중. EV 두 번으로 중단" 3; exit 0; }
[ "$(dial)" = DIALMODE_MANUAL ] || { popup "M 모드에서 사용 (가운데 노출을 먼저 맞춘다)" 3; exit 0; }
E=$(ask "HDR 간격 (EV, 1~3):" "$(conf_get hdr_ev 2)" 1 3) || exit 0
conf_set hdr_ev "$E"
IDX=$(shutter_idx)
case "$IDX" in ''|*[!0-9-]*) popup "셔터 값을 읽지 못함" 3; exit 0 ;; esac
popup "HDR 5장 ±$((2*E))EV 시작 (EV 두 번 = 중단)" 2
(
  fin() { prefman set 0 0xa340 l $IDX > /dev/null 2>&1; sta app mode m; af_restore; rm -f $JOBPID; }
  trap 'fin; jlog "hdr stopped"; exit 0' TERM
  af_save; af_manual
  S=$((16 * E))
  jlog "hdr start idx=$IDX step=$S"
  for e in -2 -1 0 1 2; do
    v=$((IDX - e * S))      # 값이 클수록 빠른 셔터(어두움). e=-2 가 가장 어두운 장
    [ $v -gt 200 ] && v=200
    [ $v -lt 0 ] && v=0
    prefman set 0 0xa340 l $v > /dev/null 2>&1
    sta app mode m
    sleep 0.3
    shoot
    jlog "hdr shot ev=$((e * E)) idx=$v up=$(cut -d' ' -f1 /proc/uptime)"
    # 노출과 저장이 끝나기 전에 다음 셔터 값을 바꾸지 않도록 잠깐 기다린다
    sleep 1
  done
  fin; jlog "hdr done"
  popup "HDR 완료" 2
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
