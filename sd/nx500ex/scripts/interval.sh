#!/bin/sh
# 인터벌 촬영 (간단한 타임랩스): 정한 간격으로 정한 장수만큼 찍는다. 0장 = 중단할 때까지.
# 매 장 반셔터+셔터를 누르므로 지금 드라이브, 무음 셔터 설정을 따른다.
# 첫 장은 지금 AF 설정으로 찍고, 사진이 생기지 않으면(초점 실패) 중단한다. 성공하면 MF 로 고정하고 끝나면 AF 를 되돌린다.
# 렌즈의 AF/MF 스위치는 AF 에 둔다 (카메라 설정만으로 MF 전환).
# P/A/S 모드는 장마다 노출을 다시 재므로 밝기가 달라질 수 있다. 일정한 밝기가 필요하면 M 모드, ISO 고정.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중. EV 두 번으로 중단" 3; exit 0; }
G=$(ask "촬영 간격 (초, 2~3600):" "$(conf_get iv_sec 10)" 2 3600) || exit 0
conf_set iv_sec "$G"
C=$(ask "장수 (0 = 중단할 때까지):" "$(conf_get iv_count 0)" 0 99999) || exit 0
conf_set iv_count "$C"
if [ "$(dial)" = DIALMODE_MANUAL ]; then
  popup "인터벌 ${G}초 x ${C}장. 3초 뒤 시작 (EV 두 번 = 중단)" 3
else
  popup "M 모드가 아니라 장마다 노출이 바뀔 수 있음. 3초 뒤 시작" 3
fi
(
  trap 'lcd_restore; af_restore; rm -f $JOBPID; jlog "interval stopped after $k"; exit 0' TERM
  k=0
  sleep 3
  jlog "interval start every ${G}s count ${C} dial=$(dial)"
  T0=$(date +%s)
  ( sleep 1; lcd_dark ) &
  jlog "interval shot 1 t=0s"
  if ! first_shot 8; then
    lcd_restore; rm -f $JOBPID; jlog "interval stopped: no photo on first shot (focus failed?)"
    popup "첫 장 초점 실패로 중단" 3; exit 0
  fi
  k=1
  while [ "$C" -eq 0 ] || [ $k -lt "$C" ]; do
    # 시작 시각 기준으로 다음 촬영 시각을 정해 간격이 밀리지 않게 한다
    NEXT=$((T0 + k * G))
    while [ $(date +%s) -lt $NEXT ]; do sleep 0.2; done
    jlog "interval shot $((k+1)) t=$(( $(date +%s) - T0 ))s"
    shoot; k=$((k+1))
  done
  lcd_restore; af_restore; rm -f $JOBPID; jlog "interval done $k"
  popup "인터벌 완료 ${k}장" 3
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
