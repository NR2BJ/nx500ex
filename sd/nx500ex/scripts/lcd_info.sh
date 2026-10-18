#!/bin/sh
# 화면 정보 숨김 전환: 라이브뷰만 보이기 <-> 원래대로 (st app bb lcd video/on). 터치는 그대로 동작한다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
if [ -e /tmp/nx500ex-lcd-video ]; then
  lcd_restore
else
  touch /tmp/nx500ex-lcd-video
  # 메뉴가 닫힌 뒤 적용
  ( sleep 1; st app bb lcd video ) > /dev/null 2>&1 &
fi
