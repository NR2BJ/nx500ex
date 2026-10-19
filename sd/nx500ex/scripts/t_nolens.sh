#!/bin/sh
# 동작: 렌즈 없이 촬영 켜고 끄기 (메뉴 체크박스와 같음)
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
toggle nolens "렌즈 없이 촬영"
