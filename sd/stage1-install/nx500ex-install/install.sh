#!/bin/sh
# nx500ex installer v2 (factory mode 로 한 번 실행)
#
# 내장 변경은 두 가지뿐이다.
#   1. /usr/etc/bluetooth/bt-stack-up.sh 를 bt-stack-up.sh.orig 로 이름만 바꾼다 (내용, 권한, 날짜 그대로).
#   2. 같은 자리에 래퍼를 둔다. 래퍼는 원본을 먼저 실행하고 SD 의 nx500ex/boot.sh 를 띄운다.
# bluetoothd 는 건드리지 않는다. 블루투스 수명 관리(끌 때 killall bluetoothd)가 순정과 같다.
# 순정 판정 기준은 공식 펌웨어 1.12 에서 확인한 값이다 (docs/research/2026-10-19-firmware-bt-analysis.md).
#
# 테스트용 환경변수: NX500EX_ROOT (가짜 루트), NX500EX_SD (가짜 SD)

ROOT=${NX500EX_ROOT:-}
SD=${NX500EX_SD:-/mnt/mmc}
PKG=$SD/nx500ex-install
STATE=$SD/nx500ex-state
BTD=$ROOT/usr/sbin/bluetoothd
BTD_ORIG=$ROOT/usr/sbin/bluetoothd.orig
DIR=$ROOT/usr/etc/bluetooth
STK=$DIR/bt-stack-up.sh
STK_ORIG=$DIR/bt-stack-up.sh.orig
NEW=$DIR/bt-stack-up.sh.nx500ex-new
BTD_SIZE=332440
STK_SUM="1579358536 1205"
MARK="nx500ex bt-stack-up wrapper"
OLDMARK="nx500ex bluetoothd wrapper"

mkdir -p "$STATE"
LOG=$STATE/install-$(date +%Y%m%d-%H%M%S).log

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; sync; }
osd() { dfmstool -s "osd string $1 $2" > /dev/null 2>&1; }
size_of() { wc -c < "$1" 2>/dev/null | tr -d ' '; }
sum_of() { cksum "$1" 2>/dev/null | cut -d' ' -f1-2; }
mtime_of() { stat -c %y "$1" 2>/dev/null; }
is_elf() { [ "$(head -c 4 "$1" 2>/dev/null | od -An -c | tr -d ' ')" = '177ELF' ]; }
has() { grep -q "$2" "$1" 2>/dev/null; }

done_and_exit() {
  sync; sync
  mv "$SD/info.tg" "$SD/info.tg.done" 2>/dev/null
  sync; sync
  osd 3 "$1"
  log "END: $1"
  sleep 30
  killall -KILL dfmsd > /dev/null 2>&1
  exit 0
}
stop() { log "STOP: $1"; osd 4 "$1"; done_and_exit "STOP. nothing changed. power off"; }
rw() { mount -o remount,rw / 2>>"$LOG"; }
ro() { sync; sync; mount -o remount,ro / 2>>"$LOG"; }

dfmsd -t > /dev/null 2>&1 &
sleep 3
osd 2 "nx500ex install v2 - do not power off"
log "start (v2, bt-stack-up hook)"
log "version: $(tr '\n' ' ' < $ROOT/etc/version.info)"
ls -la --full-time $BTD* $DIR/bt-stack-up* >> "$LOG" 2>&1
log "dir mtime: $(mtime_of $DIR)"

# 1. 기종과 펌웨어
grep -qx NX500 $ROOT/etc/version.info && grep -qx 1.12 $ROOT/etc/version.info || stop "not NX500 1.12"

# 2. bluetoothd 는 순정이어야 한다 (이전 방식 설치나 다른 모드가 있으면 중단)
if [ -e "$BTD_ORIG" ] || has "$BTD" "$OLDMARK"; then
  stop "old install or other mod on bluetoothd. run uninstall first"
fi
is_elf "$BTD" && [ "$(size_of $BTD)" = "$BTD_SIZE" ] || stop "bluetoothd not original"

# 3. bt-stack-up.sh 상태
if [ -e "$STK_ORIG" ]; then
  has "$STK" "$MARK" || stop "bt-stack-up.sh.orig exists but wrapper is not ours"
  MODE=update
else
  has "$STK" "$MARK" && stop "wrapper without .orig (broken state). run uninstall"
  [ "$(sum_of $STK)" = "$STK_SUM" ] || stop "bt-stack-up.sh not original ($(sum_of $STK))"
  MODE=fresh
fi
log "mode: $MODE"

# 4. 설치 전 상태 기록 (처음 설치할 때만)
if [ "$MODE" = fresh ]; then
  {
    echo "version=2"
    echo "date=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "stk_cksum=$(sum_of $STK)"
    echo "stk_mtime=$(mtime_of $STK)"
    echo "dir_mtime=$(mtime_of $DIR)"
  } > "$STATE/record.txt"
  cat "$STATE/record.txt" >> "$LOG"
fi

# 5. 쓰기
osd 3 "writing..."
rw || stop "remount rw failed"
cp "$PKG/wrapper.sh" "$NEW" && chmod 755 "$NEW" && sync
if ! has "$NEW" "$MARK"; then rm -f "$NEW"; ro; stop "copy failed"; fi
if [ "$MODE" = fresh ]; then
  mv "$STK" "$STK_ORIG" && mv "$NEW" "$STK"
else
  mv "$NEW" "$STK"
fi
sync; sync

# 6. 검증. 실패하면 처음 설치 상태로 되돌린다.
OK=1
chk() { if [ "$2" = 0 ]; then log "check $1: ok"; else log "check $1: FAIL"; OK=0; fi; }
has "$STK" "$MARK"; chk "wrapper in place" $?
[ "$(sum_of $STK_ORIG)" = "$STK_SUM" ]; chk "bt-stack-up.sh.orig = firmware original" $?
is_elf "$BTD" && [ "$(size_of $BTD)" = "$BTD_SIZE" ]; chk "bluetoothd untouched" $?

if [ $OK = 1 ]; then
  ro
  ls -la --full-time $DIR/bt-stack-up* >> "$LOG" 2>&1
  osd 4 "INSTALL OK ($MODE)"
  osd 5 "turn Bluetooth ON in camera menu"
  done_and_exit "DONE. power off"
else
  log "verify failed, rolling back"
  [ "$MODE" = fresh ] && [ "$(sum_of $STK_ORIG)" = "$STK_SUM" ] && mv "$STK_ORIG" "$STK"
  rm -f "$NEW"
  ro
  ls -la --full-time $DIR/bt-stack-up* >> "$LOG" 2>&1
  osd 4 "verify failed. rolled back. send log"
  done_and_exit "STOP. power off"
fi
