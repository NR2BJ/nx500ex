#!/bin/sh
# 메뉴 화면 띄우기: menu.sh <화면 이름> (gui_ini, gui_shoot ...)
# 하위 메뉴도 mod_gui 를 새로 띄운다. mod_gui 자체의 하위 메뉴 전환은 이전 화면이 비치고 눌리는 위치가 어긋났다 (2026-10-19 실기).
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
P=${1:-gui_ini}
# 앞의 mod_gui 가 완전히 닫힐 때까지 최대 2초 기다린다
i=0; while [ $i -lt 20 ] && grep -qx mod_gui /proc/[0-9]*/comm 2>/dev/null; do sleep 0.1; i=$((i+1)); done
echo "$P" > /tmp/nx500ex-menu.last
NX500EX_MENU=1 NX500EX_PAGE=$P exec "$D/bin/mod_gui" "$D/scripts/$P"
