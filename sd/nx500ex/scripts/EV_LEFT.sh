#!/bin/sh
# EV+왼쪽: AF-S/단사 와 AF-C/고속연사 전환
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
if [ -e /tmp/nx500ex-af-c ]; then
  rm -f /tmp/nx500ex-af-c
  st app nx capture af-mode single > /dev/null 2>&1; st app drive single > /dev/null 2>&1
  popup "AF-S / Single" 1
else
  touch /tmp/nx500ex-af-c
  st app nx capture af-mode caf > /dev/null 2>&1; st app drive conti_h > /dev/null 2>&1
  popup "AF-C / Cont. High" 1
fi
