#!/bin/sh
# 필름 레시피 보정 촬영: 같은 장면(모니터에 띄운 색표, tools/filmlab/calib_chart.png)을 화면 마법사 값 하나씩만 바꿔 연속으로 찍는다.
# 결과 JPEG 를 PC 에서 칸마다 재서 한 단계가 색을 얼마나, 어느 방향으로 바꾸는지 알아낸다 (tools/filmlab/calib_analyze.py).
# M 모드, MF, JPEG (또는 RAW+JPEG) 에서. WB 는 촬영 동안 색온도 5500K 로 고정하고, 끝나면 사용자 1 값, 화면 마법사 종류, WB 를 되돌린다.
# 촬영은 film/series.sh (장마다 "calib <이름> <값> -> <파일>" 을 log/jobs.log 에). EV 두 번으로 중단 (되돌림).
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중" 3; exit 0; }
[ "$(dial)" = DIALMODE_MANUAL ] || { popup "M 모드에서 사용" 3; exit 0; }
# 이름 R G B 색조 채도 선명도 대비 K
STEPS=/tmp/nx500ex-calib.steps
cat > $STEPS <<'EOF'
base 100 100 100 10 10 10 10 5500
sat5 100 100 100 10 5 10 10 5500
sat15 100 100 100 10 15 10 10 5500
con5 100 100 100 10 10 10 5 5500
con15 100 100 100 10 10 10 15 5500
r90 90 100 100 10 10 10 10 5500
r110 110 100 100 10 10 10 10 5500
g110 100 110 100 10 10 10 10 5500
b90 100 100 90 10 10 10 10 5500
b110 100 100 110 10 10 10 10 5500
hue8 100 100 100 8 10 10 10 5500
hue12 100 100 100 12 10 10 10 5500
mono 100 100 100 10 0 10 10 5500
mono_r120 120 100 100 10 0 10 10 5500
mono_r80 80 100 100 10 0 10 10 5500
mono_b120 100 100 120 10 0 10 10 5500
EOF
popup "보정 촬영 $(wc -l < $STEPS)장<br>카메라를 움직이지 마세요 (EV 두 번=중단)" 3
sh "$D/scripts/film/series.sh" calib $STEPS < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
