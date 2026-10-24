#!/bin/sh
# 블루투스를 끌 때 (watch.sh): LUT 를 원래 표로 되돌린다. auto/lut_reapply.sh 는 남아 다시 켜면 재적용된다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
A="$D/conf/lut_orig_a.bin"; B="$D/conf/lut_orig_b.bin"
[ -s "$A" ] && [ -s "$B" ] || exit 0
nxmem w 0x810c3500 "$A" > /dev/null 2>&1 && nxmem w 0x81123d00 "$B" > /dev/null 2>&1 && jlog "lut off (bluetooth off)"
key push s1; sleep 0.4; key release s1
