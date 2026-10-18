#!/bin/sh
# nx500ex 블루투스 감시: bluetoothd($1) 가 사라지면 모드를 멈춘다.
#   keyscan($2) 정지, 메뉴 닫기, 촬영 작업 중단, 켜 둔 기능(scripts/auto/*.sh)마다 off_ 스크립트 실행.
#   auto 폴더는 그대로 두므로 블루투스를 다시 켜면 다시 적용된다.
BTPID=$1; KPID=$2; LOG=$3
D=${LOG%/log/boot.log}
while [ -d /proc/$BTPID ] && [ -d /proc/$KPID ]; do sleep 2; done
if [ -d /proc/$KPID ]; then
  kill $KPID 2>/dev/null
  killall -q mod_gui 2>/dev/null
  # 촬영 작업 중단 (작업이 스스로 셔터, AF, 화면을 되돌린다), 화면 정보 숨김 해제
  [ -f /tmp/nx500ex-job.pid ] && kill $(cat /tmp/nx500ex-job.pid) 2>/dev/null
  [ -e /tmp/nx500ex-lcd-video ] && { st app bb lcd on; rm -f /tmp/nx500ex-lcd-video; } > /dev/null 2>&1
  for f in $D/scripts/auto/*.sh; do
    [ -f "$f" ] || continue
    off=$D/scripts/off_${f##*/}
    [ -f "$off" ] && sh "$off" > /dev/null 2>&1
  done
  echo "$(date '+%Y-%m-%d %H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime) bluetooth off: keyscan $KPID stopped, features off" >> $LOG
  sync
fi
rm -f /tmp/nx500ex-keyscan.pid /tmp/nx500ex-watch.pid
