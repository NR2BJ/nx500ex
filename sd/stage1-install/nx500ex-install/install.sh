#!/bin/sh
# nx500ex installer (factory mode 로 한 번 실행)
#
# 내장 변경은 두 가지뿐이다.
#   1. /usr/sbin/bluetoothd 를 /usr/sbin/bluetoothd.orig 로 이름만 바꾼다 (내용, 권한, 날짜 그대로).
#   2. /usr/sbin/bluetoothd 자리에 래퍼 스크립트를 둔다.
# 설치 전 상태는 SD 의 nx500ex-state/record.txt 에 기록되어 제거 시 검증과 복원에 쓰인다.
# 이미 설치되어 있으면 래퍼만 갱신하고, 다른 모드의 흔적이 있으면 아무것도 바꾸지 않는다.
#
# 테스트용 환경변수: NX500EX_ROOT (가짜 루트), NX500EX_SD (가짜 SD)

ROOT=${NX500EX_ROOT:-}
SD=${NX500EX_SD:-/mnt/mmc}
PKG=$SD/nx500ex-install
STATE=$SD/nx500ex-state
BT=$ROOT/usr/sbin/bluetoothd
ORIG=$ROOT/usr/sbin/bluetoothd.orig
NEW=$ROOT/usr/sbin/bluetoothd.nx500ex-new
SBIN=$ROOT/usr/sbin
EXPECT_SIZE=332440
MARK="nx500ex bluetoothd wrapper"

mkdir -p "$STATE"
LOG=$STATE/install-$(date +%Y%m%d-%H%M%S).log

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
osd() { dfmstool -s "osd string $1 $2" > /dev/null 2>&1; }
size_of() { wc -c < "$1" 2>/dev/null | tr -d ' '; }
sum_of() { cksum "$1" 2>/dev/null | cut -d' ' -f1-2; }
mtime_of() { stat -c %y "$1" 2>/dev/null; }
is_elf() { [ "$(head -c 4 "$1" 2>/dev/null | od -An -c | tr -d ' ')" = '177ELF' ]; }
is_ours() { grep -q "$MARK" "$1" 2>/dev/null; }

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

rw()  { mount -o remount,rw / 2>>"$LOG"; }
ro()  { sync; sync; mount -o remount,ro / 2>>"$LOG"; }

dfmsd -t > /dev/null 2>&1 &
sleep 3
osd 2 "nx500ex install - do not power off"
log "start"
log "version: $(tr '\n' ' ' < $ROOT/etc/version.info)"
ls -la --full-time $SBIN/bluetoothd* >> "$LOG" 2>&1
log "sbin mtime: $(mtime_of $SBIN)"

# 1. 기종과 펌웨어
if ! grep -qx NX500 $ROOT/etc/version.info || ! grep -qx 1.12 $ROOT/etc/version.info; then
  osd 4 "not NX500 1.12. nothing changed"
  done_and_exit "STOP. power off"
fi

# 2. 현재 상태 판정
if [ -e "$ORIG" ]; then
  if is_ours "$BT"; then
    MODE=update
  else
    log "bluetoothd.orig exists but bluetoothd is not our wrapper (other mod?)"
    osd 4 "other mod found. nothing changed"
    done_and_exit "STOP. power off"
  fi
else
  if ! is_elf "$BT" || [ "$(size_of $BT)" != "$EXPECT_SIZE" ]; then
    log "bluetoothd is not the original binary (size $(size_of $BT))"
    osd 4 "bluetoothd not original. nothing changed"
    done_and_exit "STOP. power off"
  fi
  MODE=fresh
fi
log "mode: $MODE"

# 3. 설치 전 상태 기록 (처음 설치할 때만)
if [ "$MODE" = fresh ]; then
  {
    echo "date=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "bt_size=$(size_of $BT)"
    echo "bt_cksum=$(sum_of $BT)"
    echo "bt_mtime=$(mtime_of $BT)"
    echo "sbin_mtime=$(mtime_of $SBIN)"
  } > "$STATE/record.txt"
  cat "$STATE/record.txt" >> "$LOG"
fi

# 4. 쓰기
osd 3 "writing..."
if ! rw; then
  osd 4 "remount rw failed. nothing changed"
  done_and_exit "STOP. power off"
fi

cp "$PKG/wrapper.sh" "$NEW" && chmod 755 "$NEW" && sync
if ! is_ours "$NEW"; then
  rm -f "$NEW"; ro
  osd 4 "copy failed. nothing changed"
  done_and_exit "STOP. power off"
fi

if [ "$MODE" = fresh ]; then
  mv "$BT" "$ORIG" && mv "$NEW" "$BT"
else
  mv "$NEW" "$BT"
fi
sync; sync

# 5. 검증. 실패하면 처음 설치 상태로 되돌린다.
OK=1
is_ours "$BT" || OK=0
is_elf "$ORIG" || OK=0
[ "$(size_of $ORIG)" = "$EXPECT_SIZE" ] || OK=0
if [ -f "$STATE/record.txt" ]; then
  [ "$(sum_of $ORIG)" = "$(sed -n 's/^bt_cksum=//p' $STATE/record.txt)" ] || OK=0
fi

if [ $OK = 1 ]; then
  ro
  ls -la --full-time $SBIN/bluetoothd* >> "$LOG" 2>&1
  osd 4 "INSTALL OK ($MODE)"
  osd 5 "turn Bluetooth ON in camera menu"
  done_and_exit "DONE. power off"
else
  log "verify failed, rolling back"
  if [ "$MODE" = fresh ] && is_elf "$ORIG"; then
    mv "$ORIG" "$BT"
  fi
  rm -f "$NEW"
  ro
  ls -la --full-time $SBIN/bluetoothd* >> "$LOG" 2>&1
  osd 4 "verify failed. rolled back. send log"
  done_and_exit "STOP. power off"
fi
