#!/bin/sh
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
prefman set 0 0x0000c2dd b 0 > /dev/null 2>&1
A=$(prefman get 0 0x0000c2dd b 2>&1 | tr -s '\r\n' '  ')
echo "$(date '+%Y-%m-%d %H:%M:%S') nolens off: after=[$A]" >> "$D/log/boot.log"; sync
