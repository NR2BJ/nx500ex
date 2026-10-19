#!/bin/sh
# nxmenu, nxpopup, nxkeys 빌드: NX500 펌웨어 루트 파일 시스템(ROOT)의 glibc 2.13, EFL 1.7.99 와 링크한다.
# 필요: arm-linux-gnueabi-gcc (Ubuntu gcc-arm-linux-gnueabi), 펌웨어에서 추출한 루트 파일 시스템
# 사용: ROOT=/path/to/rootfs sh build.sh   ->  ../../sd/nx500ex/bin/nxmenu, nxpopup, nxkeys
set -e
cd "$(dirname "$0")"
: "${ROOT:?ROOT=펌웨어 루트 파일 시스템 경로}"
LIBS="$ROOT/usr/lib/libelementary.so.1 $ROOT/usr/lib/libevas.so.1 $ROOT/usr/lib/libecore.so.1 $ROOT/usr/lib/libecore_input.so.1 $ROOT/lib/libc.so.6"
HAVE=$(arm-linux-gnueabi-readelf -V "$ROOT/lib/libc.so.6" | grep -o 'Name: GLIBC_[0-9.]*' | sort -u)
for prog in nxmenu nxpopup nxkeys; do
  OUT=../../sd/nx500ex/bin/$prog
  arm-linux-gnueabi-gcc -march=armv7-a -mthumb -mfpu=vfp -mfloat-abi=softfp -O2 -Wall -Wno-format-truncation \
    -fno-stack-protector -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -U_TIME_BITS -U_FILE_OFFSET_BITS \
    -o "$OUT" $prog.c \
    -nodefaultlibs -Wl,--dynamic-linker=/lib/ld-linux.so.3 \
    -Wl,-rpath-link,"$ROOT/lib:$ROOT/usr/lib" $([ $prog = nxkeys ] && echo "$ROOT/lib/libc.so.6" || echo $LIBS) -lgcc
  arm-linux-gnueabi-strip "$OUT"
  # 카메라 glibc(2.13)에 없는 버전 심볼이 있으면 실패
  for v in $(arm-linux-gnueabi-readelf -V "$OUT" | grep -o 'GLIBC_[0-9.]*' | sort -u); do
    echo "$HAVE" | grep -qx "Name: $v" || { echo "error: camera libc has no $v" >&2; exit 1; }
  done
  ls -l "$OUT"
done
