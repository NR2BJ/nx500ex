#!/bin/sh
# nx500ex bluetoothd wrapper
# SD 의 /mnt/mmc/nx500ex/boot.sh 가 있으면 백그라운드로 실행하고, 원본 bluetoothd 는 항상 실행한다.
(
  i=0
  while [ $i -lt 30 ] && [ ! -f /mnt/mmc/nx500ex/boot.sh ]; do sleep 1; i=$((i+1)); done
  [ -f /mnt/mmc/nx500ex/boot.sh ] && [ ! -e /mnt/mmc/nx500ex/DISABLE ] && sh /mnt/mmc/nx500ex/boot.sh
) </dev/null >/dev/null 2>&1 &
exec /usr/sbin/bluetoothd.orig "$@"
