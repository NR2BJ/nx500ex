#!/bin/sh
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
for f in /tmp/nx500ex-telnet.pid /tmp/nx500ex-ftp.pid; do
  [ -f $f ] && kill $(cat $f) 2>/dev/null
  rm -f $f
done
killall -q telnetd 2>/dev/null
exit 0
