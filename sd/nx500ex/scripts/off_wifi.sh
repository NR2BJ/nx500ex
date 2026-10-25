#!/bin/sh
# 메뉴 체크박스 "WiFi 켜기" 해제, 블루투스 끔 (watch.sh): WiFi 를 끈다 (전원 켤 때의 순정 상태).
sh "${NX500EX:-/mnt/mmc/nx500ex}/scripts/wifi.sh" off
