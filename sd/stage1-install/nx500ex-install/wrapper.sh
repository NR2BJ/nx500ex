#!/bin/sh
# nx500ex bt-stack-up wrapper
# 원본 bt-stack-up.sh 를 먼저 그대로 실행하고, SD 에 nx500ex/boot.sh 가 있으면 백그라운드로 띄운다.
/bin/sh /usr/etc/bluetooth/bt-stack-up.sh.orig "$@"
RC=$?
(
  i=0
  while [ $i -lt 30 ] && [ ! -f /mnt/mmc/nx500ex/boot.sh ]; do sleep 1; i=$((i+1)); done
  [ -f /mnt/mmc/nx500ex/boot.sh ] && [ ! -e /mnt/mmc/nx500ex/DISABLE ] && sh /mnt/mmc/nx500ex/boot.sh
) </dev/null >/dev/null 2>&1 &
exit $RC
