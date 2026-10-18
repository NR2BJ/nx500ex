#!/bin/sh
# 설정 전체 복원. 끝나면 전원을 끈다 (NX-KS 와 같음)
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
i=0; while [ $i -le 10 ]; do [ -f "$PRESETS/full/$i" ] || { popup "No backup found" 3; exit 0; }; i=$((i+1)); done
confirm "Restore all settings? Camera will power off" RESTORE || exit 0
i=0; while [ $i -le 10 ]; do prefman load_file $i "$PRESETS/full/$i" > /dev/null 2>&1; i=$((i+1)); done
prefman save > /dev/null 2>&1
sync
popup "Restored. Powering off" 2
sleep 2
st key click pwoff
