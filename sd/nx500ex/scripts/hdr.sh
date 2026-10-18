#!/bin/sh
# HDR 5장: M 모드에서 셔터 속도만 바꿔 -2s, -s, 0, +s, +2s 다섯 장 (s = 메뉴 HDR 5장 > 간격, conf/hdr_ev).
# 셔터 속도 값(APPPREF_SHUTTER_SPEED_INDEX)은 1스톱 = 16 (실기 EXIF 확인: 1/30 기준 2 EV 간격이 1/500, 1/125, 1/30, 1/8, 1/2).
# 범위는 30초(-80) ~ 1/6000(200). 값은 log/jobs.log 에 남긴다.
# 드라이브는 그동안 단사로 바꿨다가 되돌린다.
# 셔터 값을 바꾼 뒤 화면 갱신(st app mode m)을 하면 눌러 둔 반셔터가 풀리는 것으로 보여(2026-10-19 실기: 첫 장 뒤 안 찍힘)
# 장마다 반셔터를 다시 누른다 (초점을 다시 잡음). 장마다 사진이 생겼는지 확인하고, 안 생기면(초점 실패) 중단한다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중. EV 두 번으로 중단" 3; exit 0; }
[ "$(dial)" = DIALMODE_MANUAL ] || { popup "M 모드에서 사용 (가운데 노출을 먼저 맞춘다)" 3; exit 0; }
E=$(conf_get hdr_ev 2 1 3)
IDX=$(shutter_idx)
case "$IDX" in ''|*[!0-9-]*) popup "셔터 값을 읽지 못함" 3; exit 0 ;; esac
# ISO 자동이면 카메라가 셔터에 맞춰 ISO 를 바꿔 밝기가 같아진다 (2026-10-19 실기: 1/160 ISO1250, 1/40 ISO320, 1/10 ISO100)
ISO=$(iso_now)
jlog "hdr check iso=$ISO silent=$(silent_on && echo on || echo off) idx=$IDX"
case "$ISO" in *AUTO*) false ;; *) true ;; esac || { popup "ISO 자동이면 HDR 이 안 됨. ISO 를 고정하고 사용" 4; exit 0; }
# 무음 셔터는 1/5 초보다 긴 노출이 막힌다. 가장 긴 장(IDX - 2 x 간격)이 그보다 길면 거부
if silent_on && [ $((IDX - 2 * 16 * E)) -lt $SILENT_MIN_IDX ]; then
  popup "무음 셔터는 1/5초보다 긴 노출 불가. 가운데 셔터를 빠르게 하거나 간격을 줄이세요" 4; exit 0
fi
popup "HDR 5장 ±$((2*E))EV 시작 (EV 두 번 = 중단)" 2
(
  fin() { keys_release; lcd_restore; shutter_set $IDX; drive_restore; rm -f $JOBPID; }
  trap 'fin; jlog "hdr stopped"; exit 0' TERM
  S=$((16 * E))
  i=0
  drive_save; drive_single
  jlog "hdr start idx=$IDX step=$S iso=$ISO"
  for e in -2 -1 0 1 2; do
    v=$((IDX - e * S))      # 값이 클수록 빠른 셔터(어두움). e=-2 가 가장 어두운 장
    [ $v -gt 200 ] && v=200
    [ $v -lt -80 ] && v=-80
    shutter_set $v
    sleep 0.3
    # 기다릴 시간: 8초 + 노출 시간(1초 이상일 때)
    w=8; if [ $v -le 0 ]; then e2=1; n=$((-v)); while [ $n -ge 16 ]; do e2=$((e2 * 2)); n=$((n - 16)); done; w=$((8 + e2)); fi
    n0=$(dcim_count)
    s1_hold; sleep 0.5; s2_click; key release s1
    if ! wait_file $n0 $w; then
      fin; jlog "hdr stopped: no photo at ev=$((e * E)) (focus failed?)"
      popup "사진 없음 (초점 실패?), 중단" 3; exit 0
    fi
    i=$((i + 1))
    jlog "hdr shot ev=$((e * E)) idx=$v"
    [ $i -eq 1 ] && lcd_dark
  done
  fin; jlog "hdr done"
  popup "HDR 완료" 2
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
