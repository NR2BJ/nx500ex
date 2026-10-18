#!/bin/sh
# DOWN 프로필 불러오기. 두 벌이 같을 때만 불러온다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
if [ ! -f "$PRESETS/DOWN.1" ]; then popup "No DOWN profile" 2; exit 0; fi
if [ "$(cksum < "$PRESETS/DOWN.1")" != "$(cksum < "$PRESETS/DOWN.2")" ]; then popup "DOWN profile damaged" 3; exit 0; fi
popup "Loading DOWN" 1
prefman load_file 0 "$PRESETS/DOWN.1" > /dev/null 2>&1
reapply_mode
