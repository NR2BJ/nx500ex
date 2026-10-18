#!/bin/sh
# 현재 설정을 DOWN 프로필로 저장 (EV+DOWN 로 불러온다). 손상 확인용으로 두 벌 저장한다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
confirm "Save DOWN profile?" SAVE || exit 0
mkdir -p "$PRESETS"
prefman save_file 0 "$PRESETS/DOWN.1" && prefman save_file 0 "$PRESETS/DOWN.2"
sync
popup "DOWN saved" 2
