#!/bin/sh
# 메뉴의 "내 버튼": SD 의 nx500ex/user/button.sh 를 실행
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
if [ -f "$D/user/button.sh" ]; then sh "$D/user/button.sh"; else popup "user/button.sh 없음" 2; fi
