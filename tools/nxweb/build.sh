#!/bin/sh
# nxweb 를 NX500 용 정적 ARM 바이너리로 빌드 (zig cc, Docker 나 펌웨어 rootfs 불필요). 결과: sd/nx500ex/bin/nxweb
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
command -v zig > /dev/null || { echo "zig 가 없습니다: brew install zig"; exit 1; }
zig cc -target arm-linux-musleabi -mcpu=generic+v7a -Os -static -Wall -Wextra -Wno-unused-parameter -s \
  -o "$HERE/../../sd/nx500ex/bin/nxweb" "$HERE/nxweb.c"
ls -la "$HERE/../../sd/nx500ex/bin/nxweb"
file "$HERE/../../sd/nx500ex/bin/nxweb"
