#!/bin/sh
# EV 두 번: 촬영 작업(벌브, 인터벌, HDR, 스태킹) 중이면 중단. 아니면 메뉴 열기 (열려 있으면 닫기)
# 메뉴는 마지막으로 보던 화면으로 열린다 (이번 전원 동안)
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
if job_running; then job_stop; popup "작업 중단" 2; exit 0; fi
killall -q mod_gui && exit 0
# 메뉴는 터치로 조작하므로 터치가 꺼져 있으면 켠다
[ "$(touch_get)" = 0 ] && touch_set 1 && reapply_mode
P=$(cat /tmp/nx500ex-menu.last 2>/dev/null)
sh "$D/scripts/menu.sh" "${P:-gui_ini}" < /dev/null > /dev/null 2>&1 &
