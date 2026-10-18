#!/bin/sh
# nx500ex boot.sh: 블루투스가 켜질 때(전원 ON 포함) 내장 래퍼가 부른다.
# 블루투스 켜짐 = 모드 동작, 블루투스 꺼짐 = 모드 정지.
# SD 의 nx500ex/debug 파일이 있으면 진단 기록(mon.sh, keyscan debug)을 켠다.
D=/mnt/mmc/nx500ex
mkdir -p $D/log
LOG=$D/log/boot.log
[ -f $LOG ] && [ $(wc -c < $LOG) -gt 200000 ] && mv $LOG $LOG.old
now() { echo "$(date '+%Y-%m-%d %H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime)"; }
log() { echo "$(now) $*" >> $LOG; sync; }
log "boot.sh start"

DEBUG=""
if [ -e $D/debug ]; then
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
  if grep -q keyscan /proc/$k/cmdline 2>/dev/null; then
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

# 4. keyscan 시작 (scripts/auto/*.sh 를 번호 순으로 실행한 뒤 키 감시)
export MODEL=$(grep -x 'NX[0-9]*' /etc/version.info)
export NX500EX=$D
export PATH=$D/bin:$PATH
cd /
[ -n "$DEBUG" ] && echo "=== $(now) keyscan launch" >> /tmp/nx500ex-keyscan.out
$D/bin/keyscan /dev/event0 /dev/event1 $D/scripts/ $DEBUG >> /tmp/nx500ex-keyscan.out 2>&1 &
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
