#!/bin/sh
# LUT 검증 촬영: 같은 장면(모니터의 색표, tools/film/calib_chart.png)을 lut/cal.txt 의 검증 표마다 한 장씩 찍는다.
# 첫 장(cal_id, 항등)이 기준이고, 나머지는 색상 회전, 채도, 채널 감마 같은 순수 룩이다 (순정 표 합성 없음).
# PC 의 tools/lut/lut_verify.py 가 기준 사진에서 각 룩의 결과를 여러 색 공간 모델로 예측해 실제 사진과 비교해
# 카메라의 YCbCr 변환과 격자 모델을 확정한다.
# M 모드, MF, JPEG (또는 RAW+JPEG). 흰 칸이 날아가지 않게 (Y 200 이하, 순정 표의 밝은 곳 채도 억제가 안 끼게) 노출을 조금 어둡게.
# 장마다 "lutcal <id> -> <파일>" 을 log/jobs.log 에. 끝나면 쓰던 LUT (없으면 원래 표) 로 되돌린다. EV 두 번으로 중단.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중" 3; exit 0; }
[ "$(dial)" = DIALMODE_MANUAL ] || { popup "M 모드에서 사용" 3; exit 0; }
ADDR_A=0x810c3500; SIZE_A=0x603c4
ADDR_B=0x81123d00; SIZE_B=0x69dc4
ORIG_A="$D/conf/lut_orig_a.bin"; ORIG_B="$D/conf/lut_orig_b.bin"
IDS=$(grep -v '^#' "$D/lut/cal.txt" 2>/dev/null | cut -d'|' -f1)
[ -n "$IDS" ] || { popup "lut/cal.txt 없음" 3; exit 0; }
N=$(echo $IDS | wc -w)
popup "LUT 검증 촬영 ${N}장<br>카메라를 움직이지 마세요 (EV 두 번=중단)" 3

run() {
  LIST=/tmp/nx500ex-lutcal.list
  size_ok() { [ -s "$1" ] && [ "$(wc -c < "$1" | tr -d " ")" = "$2" ]; }
  write2() { nxmem w $ADDR_A "$1" > /dev/null 2>&1 && nxmem w $ADDR_B "$2" > /dev/null 2>&1; lut_reload; }
  if ! size_ok "$ORIG_A" $((SIZE_A)) || ! size_ok "$ORIG_B" $((SIZE_B)); then
    mkdir -p "$D/conf"; nxmem r $ADDR_A $SIZE_A "$ORIG_A" > /dev/null 2>&1; nxmem r $ADDR_B $SIZE_B "$ORIG_B" > /dev/null 2>&1; sync
  fi
  LAST=$(cat "$D/conf/lut_last" 2>/dev/null)
  fin() {
    if [ -n "$LAST" ] && [ -f "$D/lut/${LAST}_a.bin" ]; then write2 "$D/lut/${LAST}_a.bin" "$D/lut/${LAST}_b.bin"; else write2 "$ORIG_A" "$ORIG_B"; fi
    group_done; rm -f $LIST $JOBPID
  }
  trap 'trap "" TERM; fin; jlog "lutcal stopped"; exit 0' TERM
  jlog "lutcal start last=${LAST:-none}"
  group_mark
  sleep 2
  k=0
  for id in $IDS; do
    FA="$D/lut/${id}_a.bin"; FB="$D/lut/${id}_b.bin"
    size_ok "$FA" $((SIZE_A)) && size_ok "$FB" $((SIZE_B)) || { jlog "lutcal skip $id (no file)"; continue; }
    write2 "$FA" "$FB"
    sleep 1.5
    find /mnt/mmc/DCIM -type f -iname '*.JPG' 2>/dev/null | sort > $LIST
    n0=$(dcim_count)
    shoot
    if ! wait_file $n0 8; then
      jlog "lutcal stopped: no photo at $id"; fin; popup "사진 없음, 중단<br>MF, JPEG 인지 확인" 3; exit 0
    fi
    sleep 1
    f=$(find /mnt/mmc/DCIM -type f -iname '*.JPG' 2>/dev/null | sort | grep -vxF -f $LIST | tail -1)
    k=$((k + 1))
    jlog "lutcal $id -> ${f##*/}"
  done
  fin
  jlog "lutcal done $k"
  popup "검증 촬영 완료 ${k}장" 3
}
run < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
