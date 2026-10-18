#!/bin/sh
# 메뉴의 "사용자 체크박스" 켬 (그리고 켤 때마다 자동 실행): nx500ex/user/checkbox.sh
D=${NX500EX:-/mnt/mmc/nx500ex}
[ -f "$D/user/checkbox.sh" ] && sh "$D/user/checkbox.sh"
