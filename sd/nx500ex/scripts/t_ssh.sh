#!/bin/sh
# 동작 (키 할당용): SSH 켜고 끄기 (메뉴 체크박스와 같음)
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
toggle ssh "SSH"
