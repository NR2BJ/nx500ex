#!/bin/sh
# 메뉴 "타이머 시간": 셀프타이머 시간(초) 입력. 2~60
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
CUR=$(cat "$D/conf/timer_delay" 2>/dev/null); CUR=${CUR:-5}
V=$(ask "셀프타이머 시간 (2~60초):" "$CUR" 2 60) || { stay; exit 0; }
conf_set timer_delay "$V"
stay
