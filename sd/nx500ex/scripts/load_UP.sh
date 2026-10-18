#!/bin/sh
# UP 프로필 불러오기. 두 벌이 같을 때만 불러온다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
if [ ! -f "$PRESETS/UP.1" ]; then popup "UP 프로필 없음" 2; exit 0; fi
if [ "$(cksum < "$PRESETS/UP.1")" != "$(cksum < "$PRESETS/UP.2")" ]; then popup "UP 프로필 손상" 3; exit 0; fi
popup "UP 프로필 불러오는 중" 1
prefman load_file 0 "$PRESETS/UP.1" > /dev/null 2>&1
reapply_mode
