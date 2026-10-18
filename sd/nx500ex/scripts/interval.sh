#!/bin/sh
# 인터벌 촬영 (간단한 타임랩스): 정한 간격으로 정한 장수만큼 찍는다. 0장 = 중단할 때까지.
# 간격, 장수는 메뉴 인터벌 촬영 > (conf/iv_sec, conf/iv_count).
# 반셔터를 누른 채 두고 셔터만 누른다: 첫 장에서 초점(과 P/A/S 의 노출)이 잡히면 끝날 때까지 다시 잡지 않는다.
# 첫 장이 초점 실패로 찍히지 않으면 중단한다. 촬영이 밀리면 몰아서 찍지 않고 그 시점부터 다시 간격을 센다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중. EV 두 번으로 중단" 3; exit 0; }
G=$(conf_get iv_sec 10 2 3600)
C=$(conf_get iv_count 0 0 9999)
if [ "$(dial)" = DIALMODE_MANUAL ]; then
  popup "인터벌 ${G}초 x ${C}장. 3초 뒤 시작 (EV 두 번 = 중단)" 3
else
  popup "M 모드가 아니면 첫 장의 노출로 고정됨. 3초 뒤 시작" 3
fi
(
  trap 'keys_release; lcd_restore; rm -f $JOBPID; jlog "interval stopped after $k"; exit 0' TERM
  k=0
  sleep 3
  jlog "interval start every ${G}s count ${C} dial=$(dial)"
  s1_hold; sleep 1
  if ! first_shot 8; then
    keys_release; rm -f $JOBPID; jlog "interval stopped: no photo on first shot (focus failed?)"
    popup "첫 장 초점 실패로 중단" 3; exit 0
  fi
  k=1
  T0=$(now_cs)
  jlog "interval shot 1"
  lcd_dark
  while [ "$C" -eq 0 ] || [ $k -lt "$C" ]; do
    NEXT=$((T0 + k * G * 100))
    while [ $(now_cs) -lt $NEXT ]; do sleep 0.1; done
    NOW=$(now_cs)
    # 1초 넘게 밀렸으면 이번 장부터 기준을 다시 잡는다
    [ $NOW -gt $((NEXT + 100)) ] && { jlog "interval late $(( (NOW - NEXT) / 100 ))s, rebase"; T0=$((NOW - k * G * 100)); }
    s2_click; k=$((k + 1))
    jlog "interval shot $k t=$(printf '%d.%02d' $(( (NOW - T0) / 100 )) $(( (NOW - T0) % 100 )))s"
  done
  keys_release; lcd_restore; rm -f $JOBPID; jlog "interval done $k"
  popup "인터벌 완료 ${k}장" 3
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
