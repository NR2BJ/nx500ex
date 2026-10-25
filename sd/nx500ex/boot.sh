#!/bin/sh
# nx500ex boot.sh: 블루투스가 켜질 때(전원 ON 포함) 내장 래퍼가 부른다.
# 블루투스 켜짐 = 모드 동작, 블루투스 꺼짐 = 모드 정지.
# 메뉴의 진단 기록이 켜져 있으면(scripts/auto/debug.sh) 진단 기록(mon.sh, keyscan debug)을 켠다.
D=/mnt/mmc/nx500ex
mkdir -p $D/log
LOG=$D/log/boot.log
[ -f $LOG ] && [ $(wc -c < $LOG) -gt 200000 ] && mv $LOG $LOG.old
now() { echo "$(date '+%Y-%m-%d %H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime)"; }
log() { echo "$(now) $*" >> $LOG; sync; }
log "boot.sh start"

DEBUG=""
rm -f $D/debug   # 예전 방식의 표시 파일 정리
# 예전 판의 고정 키 조합 파일 정리 (키 할당은 메뉴의 키 설정, conf/keymap 으로 옮김. EV_EV.sh 만 고정)
for f in EV_LEFT EV_RIGHT EV_UP EV_DOWN EV_MOBILE; do rm -f $D/scripts/$f.sh; done
if [ -e $D/scripts/auto/debug.sh ]; then
  DEBUG=debug
  sh $D/bin/mon.sh </dev/null >/dev/null 2>&1 &
fi

# 1. 이전 실행 정리 (블루투스를 빠르게 껐다 켠 경우)
if [ -f /tmp/nx500ex-watch.pid ]; then
  w=$(cat /tmp/nx500ex-watch.pid)
  grep -q watch.sh /proc/$w/cmdline 2>/dev/null && kill $w 2>/dev/null
  rm -f /tmp/nx500ex-watch.pid
fi
if [ -f /tmp/nx500ex-keyscan.pid ]; then
  k=$(cat /tmp/nx500ex-keyscan.pid)
  if grep -q -e keyscan -e nxkeys /proc/$k/cmdline 2>/dev/null; then
    kill $k 2>/dev/null
    n=0; while [ -d /proc/$k ] && [ $n -lt 20 ]; do sleep 0.1; n=$((n+1)); done
    log "previous keyscan $k stopped"
  fi
  rm -f /tmp/nx500ex-keyscan.pid
fi

# 2. 블루투스 데몬 찾기
BTPID=""
n=0
while [ -z "$BTPID" ] && [ $n -lt 10 ]; do
  for d in /proc/[0-9]*; do
    [ "$(cat $d/comm 2>/dev/null)" = bluetoothd ] && BTPID=${d#/proc/} && break
  done
  [ -z "$BTPID" ] && sleep 1
  n=$((n+1))
done
if [ -z "$BTPID" ]; then log "bluetoothd not found, not starting"; exit 0; fi

# 3. 동영상 녹화 중이면 끝날 때까지 기다린다 (최대 10분)
n=0
while st pmu show 2>/dev/null | grep hevc | grep -q ON && [ $n -lt 600 ]; do sleep 1; n=$((n+1)); done

# 3a. 켜 둔 기능의 사본 갱신: 체크박스는 scripts/X.sh 를 scripts/auto/X.sh 로 복사해 두므로, 스크립트를 고쳐도 사본은 옛것으로 남는다
#     (2026-10-26 실기: wifi.sh 를 고친 뒤 첫 전원에서 옛 사본이 돌아 연결이 안 됐음). 전원 켤 때마다 원본으로 덮는다.
for f in $D/scripts/auto/*.sh; do
  [ -f "$f" ] && [ -f "$D/scripts/${f##*/}" ] && cp "$D/scripts/${f##*/}" "$f"
done
sync

# 3b. 사용자 LUT 메뉴 (lut/user 를 훑어 scripts/gui_lut_user*.NX500 생성)
sh $D/scripts/lut_menu.sh >> $LOG 2>&1

# 4. 키 감지 시작 (bin/nxkeys, tools/nxmenu/nxkeys.c. scripts/auto/*.sh 를 번호 순으로 실행한 뒤 키 감시)
# 메뉴, 팝업(EFL 프로그램)이 카메라 앱과 같은 환경에서 뜨도록 NX-KS init.sh 와 같은 변수를 맞춘다
export HIB=a
export EVAS_FONT_DPI=72
export EINA_LOG_LEVELS=ecore_x:4,evas_main:1
export GTK_IM_MODULE_FILE=/opt/etc/gtk-2.0/gtk.immodules
export LD_LIBRARY_PATH=:/usr/lib:/usr/lib/driver
export ECORE_IMF_MODULE=isf
export ECORE_INPUT_TIMEOUT_FIX=0
export EINA_LOG_DLOG_ENABLE=1
export XMODIFIERS=@im=SCIM
export EINA_LOG_LEVEL=1
export SCIM_MODULE_PATH=/opt/apps/scim/lib/scim-1.0
export ECORE_INPUT_FIX=1
export XDG_CACHE_HOME=/tmp/.cache
export EVAS_GL_NO_BLACKLIST=1
export DISPLAY=:0
export GTK_IM_MODULE=scim
export EINA_LOG_SYSLOG_ENABLE=0
export ELM_PROFILE=mobile
export MULTISENSE_SND_PLAYER=tizen_snd_player
export HOME=/root USER=root LOGNAME=root
export MODEL=$(grep -x 'NX[0-9]*' /etc/version.info)
export NX500EX=$D
export PATH=$D/bin:$PATH
cd /
[ -n "$DEBUG" ] && echo "=== $(now) keyscan launch" >> /tmp/nx500ex-keyscan.out
$D/bin/nxkeys /dev/event0 /dev/event1 $D/scripts $DEBUG >> /tmp/nx500ex-keyscan.out 2>&1 &
KPID=$!
sleep 1
if [ -d /proc/$KPID ]; then
  echo $KPID > /tmp/nx500ex-keyscan.pid
  log "keyscan started pid=$KPID bt=$BTPID $DEBUG"
else
  log "keyscan exited: $(tail -3 /tmp/nx500ex-keyscan.out | tr '\n' ' ' | cut -c1-200)"
  exit 0
fi

# 5. 블루투스 감시: 데몬이 사라지면 keyscan 을 멈춘다
sh $D/bin/watch.sh $BTPID $KPID $LOG </dev/null >/dev/null 2>&1 &
echo $! > /tmp/nx500ex-watch.pid
