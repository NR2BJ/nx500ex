#!/bin/sh
# nx500ex boot.sh: 블루투스가 켜질 때(전원 ON 포함) 래퍼가 부른다.
# 규칙: 블루투스 켜짐 = 모드 동작, 블루투스 꺼짐 = 모드 정지.
#   - 시작할 때 이전 keyscan 과 감시가 남아 있으면 정리하고 새로 시작한다.
#   - 블루투스 데몬(bluetoothd)이 사라지면 keyscan 을 멈춘다 (2초 간격 확인).
D=/mnt/mmc/nx500ex
mkdir -p $D/log
LOG=$D/log/boot.log
[ -f $LOG ] && [ $(wc -c < $LOG) -gt 200000 ] && mv $LOG $LOG.old
now() { echo "$(date '+%Y-%m-%d %H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime)"; }
log() { echo "$(now) $*" >> $LOG; sync; }
log "boot.sh start pid=$$"

# 진단 감시 (진단판 전용)
sh $D/bin/mon.sh </dev/null >/dev/null 2>&1 &

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

# 2. 블루투스 데몬 찾기 (래퍼가 원본 스크립트를 먼저 실행했으므로 이미 떠 있어야 한다)
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
log "bluetoothd pid=$BTPID"

# 3. 동영상 녹화 중이면 끝날 때까지 기다린다 (최대 10분)
n=0
while st pmu show 2>/dev/null | grep hevc | grep -q ON && [ $n -lt 600 ]; do sleep 1; n=$((n+1)); done

# 4. keyscan 시작
export MODEL=$(grep -x 'NX[0-9]*' /etc/version.info)
export NX500EX=$D
cd /
echo "=== $(now) keyscan launch" >> /tmp/nx500ex-keyscan.out
nice -n 15 $D/bin/keyscan /dev/event0 /dev/event1 $D/scripts/ debug >> /tmp/nx500ex-keyscan.out 2>&1 &
KPID=$!
sleep 1
if [ -d /proc/$KPID ]; then
  echo $KPID > /tmp/nx500ex-keyscan.pid
  log "keyscan started pid=$KPID"
else
  log "keyscan exited: $(tail -3 /tmp/nx500ex-keyscan.out | tr '\n' ' ' | cut -c1-200)"
  exit 0
fi

# 5. 블루투스 감시: 데몬이 사라지면 keyscan 을 멈춘다
sh $D/bin/watch.sh $BTPID $KPID $LOG </dev/null >/dev/null 2>&1 &
echo $! > /tmp/nx500ex-watch.pid
