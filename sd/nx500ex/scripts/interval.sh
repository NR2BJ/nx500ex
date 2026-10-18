#!/bin/sh
# 인터벌 촬영 (간단한 타임랩스): 정한 간격으로 정한 장수만큼 찍는다. 0장 = 중단할 때까지.
# 매 장 반셔터+셔터를 누르므로 지금 AF, 드라이브, 무음 셔터 설정을 따른다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중. EV 두 번으로 중단" 3; exit 0; }
G=$(ask "촬영 간격 (초, 2~3600):" "$(conf_get iv_sec 10)" 2 3600) || exit 0
conf_set iv_sec "$G"
C=$(ask "장수 (0 = 중단할 때까지):" "$(conf_get iv_count 0)" 0 99999) || exit 0
conf_set iv_count "$C"
popup "인터벌 ${G}초 x ${C}장. 3초 뒤 시작 (EV 두 번 = 중단)" 3
(
  trap 'lcd_restore; rm -f $JOBPID; jlog "interval stopped after $k"; exit 0' TERM
  k=0
  sleep 3
  lcd_dark
  jlog "interval start every ${G}s count ${C}"
  T0=$(date +%s)
  while [ "$C" -eq 0 ] || [ $k -lt "$C" ]; do
    shoot; k=$((k+1))
    # 시작 시각 기준으로 다음 촬영 시각을 정해 간격이 밀리지 않게 한다
    NEXT=$((T0 + k * G))
    while [ $(date +%s) -lt $NEXT ]; do sleep 1; done
  done
  lcd_restore; rm -f $JOBPID; jlog "interval done $k"
  popup "인터벌 완료 ${k}장" 3
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
