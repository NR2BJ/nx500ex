#!/bin/sh
# nx500ex uninstaller v2 (factory mode 로 한 번 실행)
#
# 두 가지 설치 방식을 모두 되돌린다.
#   v2: /usr/etc/bluetooth/bt-stack-up.sh 래퍼  -> bt-stack-up.sh.orig 를 원래 이름으로
#   v1: /usr/sbin/bluetoothd 래퍼               -> bluetoothd.orig 를 원래 이름으로
# 원본은 설치 때 이름만 바뀌었으므로 내용, 권한, 소유자, 수정 날짜, inode 가 설치 전과 같다.
# 폴더 수정 시각은 record.txt 의 값으로 되돌린다 (이 카메라의 touch 는 마이크로초까지).
# 원본이 공식 펌웨어 1.12 의 값과 다르거나, 현재 파일이 우리 래퍼가 아니면 건드리지 않는다.
#
# 테스트용 환경변수: NX500EX_ROOT, NX500EX_SD

ROOT=${NX500EX_ROOT:-}
SD=${NX500EX_SD:-/mnt/mmc}
STATE=$SD/nx500ex-state
BTD=$ROOT/usr/sbin/bluetoothd
BTD_ORIG=$ROOT/usr/sbin/bluetoothd.orig
BTD_NEW=$ROOT/usr/sbin/bluetoothd.nx500ex-new
SBIN=$ROOT/usr/sbin
DIR=$ROOT/usr/etc/bluetooth
STK=$DIR/bt-stack-up.sh
STK_ORIG=$DIR/bt-stack-up.sh.orig
STK_NEW=$DIR/bt-stack-up.sh.nx500ex-new
OPTDIR=$ROOT/opt/usr/nx500ex
BTD_SUM="759569816 332440"
STK_SUM="1579358536 1205"
MARK="nx500ex bt-stack-up wrapper"
OLDMARK="nx500ex bluetoothd wrapper"

mkdir -p "$STATE"
LOG=$STATE/uninstall-$(date +%Y%m%d-%H%M%S).log

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; sync; }
osd() { dfmstool -s "osd string $1 $2" > /dev/null 2>&1; }
sum_of() { cksum "$1" 2>/dev/null | cut -d' ' -f1-2; }
mtime_of() { stat -c %y "$1" 2>/dev/null; }
has() { grep -q "$2" "$1" 2>/dev/null; }
rec() { [ -f "$STATE/record.txt" ] && sed -n "s/^$1=//p" "$STATE/record.txt"; }
us() { echo "$1" | sed 's/\.\([0-9]\{6\}\)[0-9]*/.\1/'; }

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
osd 2 "nx500ex uninstall v2 - do not power off"
log "start (v2)"
ls -la --full-time $BTD* $DIR/bt-stack-up* >> "$LOG" 2>&1
log "sbin mtime: $(mtime_of $SBIN)"
log "dir mtime: $(mtime_of $DIR)"
[ -f "$STATE/record.txt" ] && cat "$STATE/record.txt" >> "$LOG" || log "no record.txt (folder mtime will not be restored)"

# 1. 무엇을 되돌릴지 판정
DO_STK=0; DO_BTD=0
if [ -e "$STK_ORIG" ]; then
  [ "$(sum_of $STK_ORIG)" = "$STK_SUM" ] || stop "bt-stack-up.sh.orig not original"
  if [ -e "$STK" ] && ! has "$STK" "$MARK"; then stop "bt-stack-up.sh is not our wrapper"; fi
  DO_STK=1
elif has "$STK" "$MARK"; then
  stop "wrapper without bt-stack-up.sh.orig. reflash firmware 1.12"
fi
if [ -e "$BTD_ORIG" ]; then
  [ "$(sum_of $BTD_ORIG)" = "$BTD_SUM" ] || stop "bluetoothd.orig not original"
  if [ -e "$BTD" ] && ! has "$BTD" "$OLDMARK"; then stop "bluetoothd is not our wrapper"; fi
  DO_BTD=1
elif has "$BTD" "$OLDMARK"; then
  stop "wrapper without bluetoothd.orig. reflash firmware 1.12"
fi
[ -e "$STK" ] || [ "$DO_STK" = 1 ] || stop "bt-stack-up.sh missing. reflash firmware 1.12"
[ -e "$BTD" ] || [ "$DO_BTD" = 1 ] || stop "bluetoothd missing. reflash firmware 1.12"
log "restore: bt-stack-up=$DO_STK bluetoothd=$DO_BTD"

if [ $DO_STK = 0 ] && [ $DO_BTD = 0 ] && [ ! -e "$STK_NEW" ] && [ ! -e "$BTD_NEW" ] && [ ! -d "$OPTDIR" ]; then
  osd 4 "already original. nothing to do"
  done_and_exit "DONE. power off"
fi

# 2. 되돌리기
osd 3 "restoring..."
rw || stop "remount rw failed"
[ $DO_STK = 1 ] && mv "$STK_ORIG" "$STK"
[ $DO_BTD = 1 ] && mv "$BTD_ORIG" "$BTD"
rm -f "$STK_NEW" "$BTD_NEW"
rm -rf "$OPTDIR"
sync
T=$(rec dir_mtime);  [ $DO_STK = 1 ] && [ -n "$T" ] && touch -d "$T" "$DIR" 2>>"$LOG"
T=$(rec sbin_mtime); [ $DO_BTD = 1 ] && [ -n "$T" ] && touch -d "$T" "$SBIN" 2>>"$LOG"
ro

# 3. 검증 (항목별 기록)
OK=1
chk() { if [ "$2" = 0 ]; then log "check $1: ok"; else log "check $1: FAIL"; OK=0; fi; }
[ "$(sum_of $STK)" = "$STK_SUM" ]; chk "bt-stack-up.sh = firmware original" $?
[ "$(sum_of $BTD)" = "$BTD_SUM" ]; chk "bluetoothd = firmware original" $?
[ ! -e "$STK_ORIG" ] && [ ! -e "$BTD_ORIG" ]; chk "no .orig files" $?
[ ! -e "$STK_NEW" ] && [ ! -e "$BTD_NEW" ]; chk "no temp files" $?
[ ! -d "$OPTDIR" ]; chk "no /opt/usr/nx500ex" $?
T=$(rec stk_mtime); if [ $DO_STK = 1 ] && [ -n "$T" ]; then [ "$(mtime_of $STK)" = "$T" ]; chk "bt-stack-up.sh mtime = record" $?; fi
T=$(rec bt_mtime);  if [ $DO_BTD = 1 ] && [ -n "$T" ]; then [ "$(mtime_of $BTD)" = "$T" ]; chk "bluetoothd mtime = record" $?; fi
for pair in "dir_mtime:$DIR:$DO_STK" "sbin_mtime:$SBIN:$DO_BTD"; do
  k=${pair%%:*}; rest=${pair#*:}; d=${rest%:*}; f=${rest##*:}
  T=$(rec $k)
  if [ "$f" = 1 ] && [ -n "$T" ]; then
    [ "$(us "$(mtime_of $d)")" = "$(us "$T")" ]; chk "$k = record (us)" $?
    [ "$(mtime_of $d)" = "$T" ] || log "note: $k differs below 1us ($(mtime_of $d) vs $T)"
  fi
done

ls -la --full-time $BTD* $DIR/bt-stack-up* >> "$LOG" 2>&1
if [ $OK = 1 ]; then
  osd 4 "UNINSTALL OK. original restored"
  done_and_exit "DONE. power off"
else
  osd 4 "check failed. send log in nx500ex-state"
  done_and_exit "STOP. power off"
fi
