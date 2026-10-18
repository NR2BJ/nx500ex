#!/bin/sh
# nx500ex 블루투스 감시: bluetoothd($1) 가 사라지면 모드를 멈춘다.
#   keyscan($2) 정지, 메뉴 닫기, 켜 둔 기능(scripts/auto/*.sh)마다 off_ 스크립트 실행.
#   auto 폴더는 그대로 두므로 블루투스를 다시 켜면 다시 적용된다.
BTPID=$1; KPID=$2; LOG=$3
D=${LOG%/log/boot.log}
while [ -d /proc/$BTPID ] && [ -d /proc/$KPID ]; do sleep 2; done
if [ -d /proc/$KPID ]; then
  kill $KPID 2>/dev/null
  killall -q mod_gui 2>/dev/null
  for f in $D/scripts/auto/*.sh; do
    [ -f "$f" ] || continue
    off=$D/scripts/off_${f##*/}
    [ -f "$off" ] && sh "$off" > /dev/null 2>&1
  done
  echo "$(date '+%Y-%m-%d %H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime) bluetooth off: keyscan $KPID stopped, features off" >> $LOG
  sync
fi
rm -f /tmp/nx500ex-keyscan.pid /tmp/nx500ex-watch.pid
