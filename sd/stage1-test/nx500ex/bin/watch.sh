#!/bin/sh
# nx500ex 블루투스 감시: bluetoothd($1) 가 사라지면 keyscan($2) 을 멈춘다.
BTPID=$1; KPID=$2; LOG=$3
while [ -d /proc/$BTPID ] && [ -d /proc/$KPID ]; do sleep 2; done
if [ -d /proc/$KPID ]; then
  kill $KPID 2>/dev/null
  echo "$(date '+%Y-%m-%d %H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime) bluetooth off: keyscan $KPID stopped" >> $LOG
  sync
fi
rm -f /tmp/nx500ex-keyscan.pid /tmp/nx500ex-watch.pid
