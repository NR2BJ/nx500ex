#!/bin/sh
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
st cap capdtm setusr ADJUSTSHUTTERTYPE 0x750000 > /dev/null 2>&1
stay
