#!/bin/sh
# 렌즈가 인식되지 않아도 셔터 허용 (어댑터 렌즈, 접점 불량). APPPREF_B_ENABLE_NO_LENS_RELEASE (1바이트)
# 2026-10-19 실기: 체크해도 동작하지 않음. 값이 실제로 바뀌는지 log/boot.log 에 남긴다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
B=$(prefman get 0 0x0000c2dd b 2>&1 | tr -s '\r\n' '  ')
prefman set 0 0x0000c2dd b 1 > /dev/null 2>&1
A=$(prefman get 0 0x0000c2dd b 2>&1 | tr -s '\r\n' '  ')
echo "$(date '+%Y-%m-%d %H:%M:%S') nolens on: before=[$B] after=[$A]" >> "$D/log/boot.log"; sync
stay
