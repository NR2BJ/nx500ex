#!/bin/sh
# 메뉴 "타이머 시간": 셀프타이머 시간(초) 입력. 2~60
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
CUR=$(cat "$D/conf/timer_delay" 2>/dev/null); CUR=${CUR:-5}
V=$("$D/bin/popup_entry" "셀프타이머 시간 (2~60초):" 설정 취소 "$CUR" number 2>/dev/null) || exit 0
case "$V" in ''|*[!0-9]*) popup "숫자가 아님" 2; exit 0 ;; esac
if [ "$V" -lt 2 ] || [ "$V" -gt 60 ]; then popup "2~60 사이로 입력" 2; exit 0; fi
mkdir -p "$D/conf"; echo "$V" > "$D/conf/timer_delay"; sync
popup "셀프타이머: ${V}초" 2
