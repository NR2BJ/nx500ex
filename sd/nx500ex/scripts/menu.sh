#!/bin/sh
# 메뉴 띄우기: menu.sh [화면 이름]  (gui_ini, gui_shoot ...). 메뉴 프로그램은 bin/nxmenu (tools/nxmenu)
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
exec "$D/bin/nxmenu" "$D/scripts" "${1:-gui_ini}"
