#!/bin/sh
# nxwake 빌드 (zig, 정적 ARM). 결과: sd/nx500ex/bin/nxwake
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
zig cc -target arm-linux-musleabi -mcpu=generic+v7a -Os -static -Wall -s -o "$HERE/../../sd/nx500ex/bin/nxwake" "$HERE/nxwake.c"
ls -la "$HERE/../../sd/nx500ex/bin/nxwake"
