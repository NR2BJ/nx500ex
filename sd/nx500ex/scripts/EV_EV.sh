#!/bin/sh
# EV 두 번: 촬영 작업(벌브, 인터벌, HDR, 스태킹) 중이면 중단. 아니면 메뉴 열기 (열려 있으면 닫기)
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
if job_running; then job_stop; popup "작업 중단" 2; exit 0; fi
killall -q mod_gui && exit 0
# 화면 정보 숨김 상태면 메뉴도 안 보이므로 먼저 되돌린다
[ -e /tmp/nx500ex-lcd-video ] && lcd_restore
# 메뉴는 터치로 조작하므로 터치가 꺼져 있으면 켠다
[ "$(touch_get)" = 0 ] && touch_set 1 && reapply_mode
# 메뉴에서 실행되는 스크립트가 알 수 있도록 표시 (telnet.sh 의 팝업 등)
NX500EX_MENU=1 "$D/bin/mod_gui" "$D/scripts/gui_ini" > /dev/null 2>&1 &
