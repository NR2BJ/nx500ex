#!/bin/sh
# 설정 전체(prefman 블록 0~10)를 SD 에 백업
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
confirm "설정 전체를 백업할까요?" 백업 || exit 0
mkdir -p "$PRESETS/full"
popup "백업 중" 2 &
i=0; while [ $i -le 10 ]; do prefman save_file $i "$PRESETS/full/$i" > /dev/null 2>&1; i=$((i+1)); done
sync
popup "백업 완료" 2
