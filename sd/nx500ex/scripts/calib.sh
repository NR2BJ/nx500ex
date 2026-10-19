#!/bin/sh
# 필름 레시피 보정 촬영: 같은 장면(모니터에 띄운 색표, tools/filmlab/calib_chart.png)을 화면 마법사 값 하나씩만 바꿔 연속으로 찍는다.
# 결과 JPEG 를 PC 에서 칸마다 재서 한 단계가 색을 얼마나, 어느 방향으로 바꾸는지 알아낸다 (tools/filmlab/calib_analyze.py).
# M 모드, MF, JPEG (또는 RAW+JPEG) 에서. WB 는 촬영 동안 색온도 5500K 로 고정하고, 끝나면 사용자 1 값, 화면 마법사 종류, WB 를 되돌린다.
# 장마다 "calib <이름> <값> -> <파일>" 을 log/jobs.log 에 남긴다. EV 두 번으로 중단 (되돌림).
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
. "$D/scripts/film/pw.sh"
job_running && { popup "다른 작업 중" 3; exit 0; }
[ "$(dial)" = DIALMODE_MANUAL ] || { popup "M 모드에서 사용" 3; exit 0; }
# 이름:R G B 색조 채도 선명도 대비 (tone_*: 채도를 조금 남기고 게인으로 색을 입히는 토닝이 되는지)
STEPS="base:100,100,100,10,10,10,10
sat5:100,100,100,10,5,10,10
sat15:100,100,100,10,15,10,10
con5:100,100,100,10,10,10,5
con15:100,100,100,10,10,10,15
r90:90,100,100,10,10,10,10
r110:110,100,100,10,10,10,10
g110:100,110,100,10,10,10,10
b90:100,100,90,10,10,10,10
b110:100,100,110,10,10,10,10
hue8:100,100,100,8,10,10,10
hue12:100,100,100,12,10,10,10
mono:100,100,100,10,0,10,10
mono_r120:120,100,100,10,0,10,10
mono_r80:80,100,100,10,0,10,10
mono_b120:100,100,120,10,0,10,10
tone_s2:110,100,85,10,2,10,10
tone_s4:110,100,85,10,4,10,10"
N=$(echo "$STEPS" | wc -l)
popup "보정 촬영 ${N}장<br>카메라를 움직이지 마세요 (EV 두 번=중단)" 3
(
  O_C1=$(c1_get); O_PW=$(pget $PW_TYPE); O_WBT=$(pget $WB_TYPE); O_K=$(pget $WB_K)
  fin() { c1_set $O_C1; pset $PW_TYPE $O_PW; pset $WB_TYPE $O_WBT; pset $WB_K $O_K; reapply_mode; rm -f $JOBPID; }
  trap 'trap "" TERM; fin; jlog "calib stopped"; exit 0' TERM
  jlog "calib start orig custom1 $O_C1 pw $O_PW wb $O_WBT $O_K"
  sleep 3
  pset $WB_TYPE 10; pset $WB_K 5500
  LIST=/tmp/nx500ex-calib.list
  k=0
  for s in $STEPS; do
    name=${s%%:*}; vals=$(echo "${s#*:}" | tr ',' ' ')
    c1_set $vals; pset $PW_TYPE 10
    reapply_mode
    wait_for 'isp_match $vals' || jlog "calib $name not applied: isp $(isp_get)"
    sleep 0.5
    find /mnt/mmc/DCIM -type f -iname '*.JPG' 2>/dev/null | sort > $LIST
    n0=$(dcim_count)
    shoot
    if ! wait_file $n0 8; then
      jlog "calib stopped: no photo at $name"; fin; popup "사진 없음, 중단<br>MF, JPEG 인지 확인" 3; exit 0
    fi
    sleep 1
    f=$(find /mnt/mmc/DCIM -type f -iname '*.JPG' 2>/dev/null | sort | grep -vxF -f $LIST | tail -1)
    k=$((k + 1))
    jlog "calib $name $vals -> ${f##*/}"
  done
  rm -f $LIST
  fin
  jlog "calib done $k"
  popup "보정 촬영 완료 ${k}장" 3
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
