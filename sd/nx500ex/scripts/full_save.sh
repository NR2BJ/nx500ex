#!/bin/sh
# 설정 전체(prefman 블록 0~10)를 SD 에 백업
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
confirm "Back up all settings?" BACKUP || exit 0
mkdir -p "$PRESETS/full"
popup "Backing up..." 2
i=0; while [ $i -le 10 ]; do prefman save_file $i "$PRESETS/full/$i" > /dev/null 2>&1; i=$((i+1)); done
sync
popup "Backup done" 2
