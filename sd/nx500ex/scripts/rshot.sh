#!/bin/sh
# 레시피 비교 촬영: 같은 장면을 기준(중립, 5500K) 한 장과 레시피마다 한 장씩 연속으로 찍는다.
#   rshot.sh list   film/compare.txt 에 적은 레시피만 (한 줄에 레시피 이름 하나, # 은 주석)
#   rshot.sh all    film/recipes.txt 의 모든 레시피
# 색표(tools/filmlab/calib_chart.png)를 찍으면 PC 에서 수치로 재고 (tools/filmlab/recipe_analyze.py), 실제 장면을 찍으면 나란히 놓고 눈으로 본다 (같은 도구가 비교 시트를 만든다).
# 노출이 장마다 같아야 비교가 되므로 M 모드에서. MF, JPEG (또는 RAW+JPEG). 촬영은 film/series.sh, log/jobs.log 에 "rshot <이름> <값> -> <파일>".
# 끝나면 사용자 1 값, 화면 마법사 종류, WB 를 처음대로. EV 두 번으로 중단.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중" 3; exit 0; }
[ "$(dial)" = DIALMODE_MANUAL ] || { popup "M 모드에서 사용" 3; exit 0; }
R="$D/scripts/film/recipes.txt"
case "$1" in
  all) NAMES=$(grep -v '^#' "$R" | cut -d'|' -f1) ;;
  *) NAMES=$(grep -v '^#' "$D/scripts/film/compare.txt" 2>/dev/null) ;;
esac
STEPS=/tmp/nx500ex-rshot.steps
echo "base 100 100 100 10 10 10 10 5500" > $STEPS
for n in $NAMES; do
  L=$(grep "^$n|" "$R" | head -1)
  [ -n "$L" ] || { jlog "rshot skip unknown $n"; continue; }
  IFS='|'; set -- $L; unset IFS
  echo "$1 $4 $5 $6 $7 $8 $9 ${10} ${11:-5500}" >> $STEPS
done
N=$(wc -l < $STEPS)
[ $N -gt 1 ] || { popup "비교할 레시피 없음<br>film/compare.txt 확인" 3; rm -f $STEPS; exit 0; }
popup "비교 촬영 ${N}장 (약 $((N * 6 / 60 + 1))분)<br>카메라를 움직이지 마세요 (EV 두 번=중단)" 3
sh "$D/scripts/film/series.sh" rshot $STEPS < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
