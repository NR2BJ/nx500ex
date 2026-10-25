#!/bin/sh
# SSH 서버 끄기 (체크 해제, 블루투스 끔). 열려 있던 접속도 끊긴다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
[ -f /tmp/nx500ex-ssh.pid ] && kill $(cat /tmp/nx500ex-ssh.pid) 2>/dev/null
rm -f /tmp/nx500ex-ssh.pid
killall -q dropbearmulti 2>/dev/null
exit 0
