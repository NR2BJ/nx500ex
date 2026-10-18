#!/bin/sh
# 포커스 스태킹: 지금 초점 위치를 먼 끝으로 저장 (AF 렌즈만. 수동 렌즈는 카메라가 초점을 움직일 수 없다)
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
set -- $(st cap iq af pos 2>/dev/null)
case "$3" in ''|*[!0-9-]*) popup "초점 위치를 읽지 못함 (AF 렌즈 필요)" 3; exit 0 ;; esac
echo "$3" > /tmp/nx500ex-fs.far
popup "먼 끝: $3" 2
