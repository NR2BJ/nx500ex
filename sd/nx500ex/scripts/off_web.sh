#!/bin/sh
# 웹 원격 끄기
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
[ -f /tmp/nx500ex-web.pid ] && kill $(cat /tmp/nx500ex-web.pid) 2>/dev/null
rm -f /tmp/nx500ex-web.pid
killall -q nxweb 2>/dev/null
exit 0
