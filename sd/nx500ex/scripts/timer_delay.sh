#!/bin/sh
# 메뉴 Timer Delay: 셀프타이머 시간(초) 입력. 2~60
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
CUR=$(cat "$D/conf/timer_delay" 2>/dev/null); CUR=${CUR:-5}
V=$("$D/bin/popup_entry" "Self-timer seconds (2-60):" SET CANCEL "$CUR" number 2>/dev/null) || exit 0
case "$V" in ''|*[!0-9]*) popup "Not a number" 2; exit 0 ;; esac
if [ "$V" -lt 2 ] || [ "$V" -gt 60 ]; then popup "Use 2-60" 2; exit 0; fi
mkdir -p "$D/conf"; echo "$V" > "$D/conf/timer_delay"; sync
popup "Self-timer: ${V}s" 2
