#!/bin/sh
# Dropbear 를 NX500 용 정적 ARM 바이너리로 빌드한다 (Mac 에서 zig cc 로 교차 컴파일, Docker 나 펌웨어 rootfs 불필요).
#   sh tools/ssh/build.sh [dropbear 소스 폴더]
# 결과: sd/nx500ex/bin/dropbearmulti (dropbear, dbclient, dropbearkey, scp 를 한 파일로. 첫 인자로 프로그램 이름을 준다)
# 준비: brew install zig. 소스: https://matt.ucc.asn.au/dropbear/releases/dropbear-<판>.tar.bz2 (MIT)
# 대상: arm-linux-musleabi (ARMv7, soft-float ABI, 정적). 카메라의 glibc 와 무관하게 돈다.
# 옵션: tools/ssh/localoptions.h (모든 경로를 SD 안으로).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
SRC=${1:-$(ls -d "$HERE"/../../../dropbear-*/ 2>/dev/null | head -1)}
[ -d "$SRC" ] || { echo "dropbear 소스 폴더를 주세요: sh tools/ssh/build.sh /path/dropbear-2026.94"; exit 1; }
VER=$(basename "$SRC" | sed 's/dropbear-//; s,/$,,')
command -v zig > /dev/null || { echo "zig 가 없습니다: brew install zig"; exit 1; }
TARGET=arm-linux-musleabi
export CC="zig cc -target $TARGET -mcpu=generic+v7a"
export AR="zig ar" RANLIB="zig ranlib"
export CFLAGS="-Os -ffunction-sections -fdata-sections -DNX500EX_NO_PERM_CHECK"
export LDFLAGS="-static -Wl,--gc-sections -Wl,-s"
cp "$HERE/localoptions.h" "$SRC/localoptions.h"
cd "$SRC"
# authorized_keys 권한 검사 제거 (tools/ssh/nx500ex.patch). 이미 적용돼 있으면 넘어감
grep -q NX500EX_NO_PERM_CHECK src/svr-authpubkey.c || patch -p1 < "$HERE/nx500ex.patch"
[ -f Makefile ] && make clean > /dev/null 2>&1 || true
./configure --host=arm-linux --enable-static --disable-zlib --disable-syslog --disable-lastlog \
  --disable-utmp --disable-utmpx --disable-wtmp --disable-wtmpx --disable-pam --disable-shadow \
  --disable-harden > nx500ex-configure.log 2>&1 || { tail -n 30 nx500ex-configure.log; exit 1; }
make -j4 PROGRAMS="dropbear dbclient dropbearkey scp" MULTI=1 > nx500ex-make.log 2>&1 || { tail -n 40 nx500ex-make.log; exit 1; }
ls -la dropbearmulti
file dropbearmulti
cp dropbearmulti "$REPO/sd/nx500ex/bin/dropbearmulti"
echo "dropbear $VER -> sd/nx500ex/bin/dropbearmulti"
