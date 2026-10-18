#!/bin/sh
# nx500ex uninstaller (factory mode 로 한 번 실행)
#
# bluetoothd.orig 를 원래 이름으로 되돌리고 래퍼를 없앤다. 원본 파일은 설치 때 이름만 바뀌었으므로
# 내용, 권한, 소유자, 수정 날짜, inode 가 설치 전과 같다. /usr/sbin 폴더의 수정 날짜도 기록값으로 되돌린다.
# /opt/usr/nx500ex 가 있으면 지운다 (지금 설계에서는 만들지 않지만 나중을 대비).
# 우리 래퍼가 아닌 것은 건드리지 않는다.
#
# 테스트용 환경변수: NX500EX_ROOT, NX500EX_SD

ROOT=${NX500EX_ROOT:-}
SD=${NX500EX_SD:-/mnt/mmc}
STATE=$SD/nx500ex-state
BT=$ROOT/usr/sbin/bluetoothd
ORIG=$ROOT/usr/sbin/bluetoothd.orig
NEW=$ROOT/usr/sbin/bluetoothd.nx500ex-new
SBIN=$ROOT/usr/sbin
OPTDIR=$ROOT/opt/usr/nx500ex
EXPECT_SIZE=332440
MARK="nx500ex bluetoothd wrapper"

mkdir -p "$STATE"
LOG=$STATE/uninstall-$(date +%Y%m%d-%H%M%S).log

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
osd() { dfmstool -s "osd string $1 $2" > /dev/null 2>&1; }
size_of() { wc -c < "$1" 2>/dev/null | tr -d ' '; }
sum_of() { cksum "$1" 2>/dev/null | cut -d' ' -f1-2; }
mtime_of() { stat -c %y "$1" 2>/dev/null; }
is_elf() { [ "$(head -c 4 "$1" 2>/dev/null | od -An -c | tr -d ' ')" = '177ELF' ]; }
is_ours() { grep -q "$MARK" "$1" 2>/dev/null; }
rec() { [ -f "$STATE/record.txt" ] && sed -n "s/^$1=//p" "$STATE/record.txt"; }

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
rw() { mount -o remount,rw / 2>>"$LOG"; }
ro() { sync; sync; mount -o remount,ro / 2>>"$LOG"; }

dfmsd -t > /dev/null 2>&1 &
sleep 3
osd 2 "nx500ex uninstall - do not power off"
log "start"
ls -la --full-time $SBIN/bluetoothd* >> "$LOG" 2>&1
log "sbin mtime: $(mtime_of $SBIN)"
[ -f "$STATE/record.txt" ] && cat "$STATE/record.txt" >> "$LOG" || log "no record.txt (sbin mtime will not be restored)"

# 1. 이미 순정인가
if [ ! -e "$ORIG" ]; then
  if is_elf "$BT" && [ "$(size_of $BT)" = "$EXPECT_SIZE" ] && [ ! -d "$OPTDIR" ] && [ ! -e "$NEW" ]; then
    osd 4 "already original. nothing to do"
    done_and_exit "DONE. power off"
  fi
  if ! [ -e "$BT" ]; then
    osd 4 "bluetoothd missing and no backup"
    osd 5 "reflash firmware 1.12 to recover"
    done_and_exit "STOP. power off"
  fi
fi

# 2. 원본 확인
if [ -e "$ORIG" ]; then
  if ! is_elf "$ORIG" || [ "$(size_of $ORIG)" != "$EXPECT_SIZE" ]; then
    osd 4 "bluetoothd.orig is not original. nothing changed"
    done_and_exit "STOP. power off"
  fi
  REC_SUM=$(rec bt_cksum)
  if [ -n "$REC_SUM" ] && [ "$(sum_of $ORIG)" != "$REC_SUM" ]; then
    osd 4 "bluetoothd.orig checksum differs. nothing changed"
    done_and_exit "STOP. power off"
  fi
  # 현재 bluetoothd 는 우리 래퍼이거나, 설치 도중 끊겨 없는 상태여야 한다
  if [ -e "$BT" ] && ! is_ours "$BT"; then
    osd 4 "bluetoothd is not our wrapper. nothing changed"
    done_and_exit "STOP. power off"
  fi
fi

# 3. 되돌리기
osd 3 "restoring..."
if ! rw; then
  osd 4 "remount rw failed. nothing changed"
  done_and_exit "STOP. power off"
fi
[ -e "$ORIG" ] && mv "$ORIG" "$BT"
rm -f "$NEW"
rm -rf "$OPTDIR"
sync
SB_MT=$(rec sbin_mtime)
[ -n "$SB_MT" ] && touch -d "$SB_MT" "$SBIN" 2>>"$LOG"
ro

# 4. 검증 (항목별로 기록)
OK=1
chk() { if [ "$2" = 0 ]; then log "check $1: ok"; else log "check $1: FAIL"; OK=0; fi; }
# 수정 시각은 마이크로초까지 비교한다. 이 카메라의 touch 는 나노초 자리를 설정하지 못한다.
us() { echo "$1" | sed 's/\.\([0-9]\{6\}\)[0-9]*/.\1/'; }
is_elf "$BT"; chk "bluetoothd is ELF" $?
[ "$(size_of $BT)" = "$EXPECT_SIZE" ]; chk "bluetoothd size $EXPECT_SIZE" $?
[ ! -e "$ORIG" ]; chk "no bluetoothd.orig" $?
[ ! -e "$NEW" ]; chk "no temp file" $?
[ ! -d "$OPTDIR" ]; chk "no /opt/usr/nx500ex" $?
REC_SUM=$(rec bt_cksum)
if [ -n "$REC_SUM" ]; then [ "$(sum_of $BT)" = "$REC_SUM" ]; chk "bluetoothd cksum = record" $?; fi
REC_MT=$(rec bt_mtime)
if [ -n "$REC_MT" ]; then [ "$(mtime_of $BT)" = "$REC_MT" ]; chk "bluetoothd mtime = record" $?; fi
if [ -n "$SB_MT" ]; then
  [ "$(us "$(mtime_of $SBIN)")" = "$(us "$SB_MT")" ]; chk "sbin mtime = record (us)" $?
  [ "$(mtime_of $SBIN)" = "$SB_MT" ] || log "note: sbin mtime differs below 1us ($(mtime_of $SBIN) vs $SB_MT)"
fi

ls -la --full-time $SBIN/bluetoothd* >> "$LOG" 2>&1
log "sbin mtime after: $(mtime_of $SBIN)"
if [ $OK = 1 ]; then
  osd 4 "UNINSTALL OK. original restored"
  done_and_exit "DONE. power off"
else
  osd 4 "check failed. send log in nx500ex-state"
  done_and_exit "STOP. power off"
fi
