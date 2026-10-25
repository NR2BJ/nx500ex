#!/bin/sh
# 화면 끄기: 화면 전체를 검은 창 (bin/blackout, NX-KS) 으로 덮고 아무 키나 눌릴 때까지 기다렸다가 걷는다 (bin/nxwake, tools/nxwake).
# AMOLED 라 검은 화소는 꺼진 것과 같아 번인과 열이 줄어든다. (st app bb lcd off 는 효과 없음, 2026-10-18 실기)
# 메뉴 더 보기의 "화면 끄기" 버튼과 키 설정의 동작 (screen_off). 반셔터, 메뉴, 십자 등 어떤 키든 누르면 걷힌다.
# 카메라 자체 절전 (자동 전원 끄기) 은 그대로 돈다. 안전: 최대 4 시간 뒤에는 키가 없어도 걷는다. 이미 덮는 중이면 걷는 쪽으로 동작.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
PID=/tmp/nx500ex-screenoff.pid
restore() { [ -f /tmp/nx500ex-blackout.pid ] && kill $(cat /tmp/nx500ex-blackout.pid) 2>/dev/null; rm -f /tmp/nx500ex-blackout.pid $PID; }
if [ -f $PID ] && [ -d /proc/$(cat $PID) ]; then
  kill $(cat $PID) 2>/dev/null; restore; exit 0
fi
echo $$ > $PID
sleep 0.3
"$D/bin/blackout" < /dev/null > /dev/null 2>&1 &
echo $! > /tmp/nx500ex-blackout.pid
echo "$(date '+%Y-%m-%d %H:%M:%S') screen off" >> "$D/log/jobs.log"
"$D/bin/nxwake" 500 14400
R=$?
restore
echo "$(date '+%Y-%m-%d %H:%M:%S') screen on (wake rc=$R)" >> "$D/log/jobs.log"; sync
exit 0
