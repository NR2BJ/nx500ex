#!/bin/sh
# 설정을 한 장씩 바꿔 가며 연속으로 찍는다 (calib.sh 보정 촬영, rshot.sh 레시피 비교 촬영이 뒤에서 실행한다).
#   series.sh <태그> <목록 파일>   목록 한 줄: 이름 R G B 색조 채도 선명도 대비 K   (K 는 색온도, auto 는 자동 WB)
# 장마다 사용자 1 값과 WB 를 쓰고 촬영 모드를 다시 들어가 반영을 확인한 뒤 찍는다.
# 장마다 "<태그> <이름> <값 8개> -> <파일>" 을 log/jobs.log 에 남긴다 (PC 분석: tools/film/calib_analyze.py, recipe_analyze.py).
# 끝나거나 중단되면 (EV 두 번) 사용자 1 값, 화면 마법사 종류, WB 를 처음대로 되돌린다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
. "$D/scripts/film/pw.sh"
TAG=$1; STEPS=$2
LIST=/tmp/nx500ex-series.list
O_C1=$(c1_get); O_PW=$(pget $PW_TYPE); O_WBT=$(pget $WB_TYPE); O_K=$(pget $WB_K)
fin() { c1_set $O_C1; pset $PW_TYPE $O_PW; pset $WB_TYPE $O_WBT; pset $WB_K $O_K; reapply_mode; group_done; rm -f $LIST "$STEPS" $JOBPID; }
trap 'trap "" TERM; fin; jlog "$TAG stopped"; exit 0' TERM
jlog "$TAG start orig custom1 $O_C1 pw $O_PW wb $O_WBT $O_K"
group_mark
sleep 3
k=0
while read name r g b h s p c wb; do
  [ -n "$name" ] || continue
  c1_set $r $g $b $h $s $p $c; pset $PW_TYPE 10
  if [ "$wb" = auto ]; then pset $WB_TYPE 0; else pset $WB_TYPE 10; pset $WB_K $wb; fi
  reapply_mode
  wait_for "isp_match $r $g $b $h $s $p $c" || jlog "$TAG $name not applied: isp $(isp_get)"
  [ "$wb" = auto ] || wait_for '[ "$(wb_k)" = "$wb" ]' || jlog "$TAG $name wb not applied: $(wb_k)"
  sleep 0.5
  find /mnt/mmc/DCIM -type f -iname '*.JPG' 2>/dev/null | sort > $LIST
  n0=$(dcim_count)
  shoot
  if ! wait_file $n0 8; then
    jlog "$TAG stopped: no photo at $name"; fin; popup "사진 없음, 중단<br>MF, JPEG 인지 확인" 3; exit 0
  fi
  sleep 1
  f=$(find /mnt/mmc/DCIM -type f -iname '*.JPG' 2>/dev/null | sort | grep -vxF -f $LIST | tail -1)
  k=$((k + 1))
  jlog "$TAG $name $r $g $b $h $s $p $c $wb -> ${f##*/}"
done < "$STEPS"
fin
jlog "$TAG done $k"
popup "촬영 완료 ${k}장" 3
