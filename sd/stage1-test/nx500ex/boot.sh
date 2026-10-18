#!/bin/sh
# nx500ex boot.sh (진단판): 래퍼가 SD 마운트 후 부른다.
D=/mnt/mmc/nx500ex
mkdir -p $D/log
LOG=$D/log/boot.log
[ -f $LOG ] && [ $(wc -c < $LOG) -gt 200000 ] && mv $LOG $LOG.old
now() { echo "$(date '+%Y-%m-%d %H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime)"; }
echo "$(now) boot.sh start pid=$$ ppid=$PPID" >> $LOG
sed 's/^/  cgroup /' /proc/$$/cgroup >> $LOG 2>/dev/null

# 감시 시작 (이미 돌고 있으면 그대로)
sh $D/bin/mon.sh </dev/null >/dev/null 2>&1 &

# 동영상 녹화 중이면 끝날 때까지 기다린다 (최대 10분)
n=0
while st pmu show 2>/dev/null | grep hevc | grep -q ON && [ $n -lt 600 ]; do sleep 1; n=$((n+1)); done

export MODEL=$(grep -x 'NX[0-9]*' /etc/version.info)
export NX500EX=$D
cd /
echo "=== $(now) keyscan launch" >> /tmp/nx500ex-keyscan.out
# debug: 받은 키 이벤트를 모두 출력한다 (진단용)
nice -n 15 $D/bin/keyscan /dev/event0 /dev/event1 $D/scripts/ debug >> /tmp/nx500ex-keyscan.out 2>&1 &
KPID=$!
sleep 1
if [ -d /proc/$KPID ]; then
  echo "$(now) keyscan started pid=$KPID" >> $LOG
else
  echo "$(now) keyscan exited: $(tail -3 /tmp/nx500ex-keyscan.out | tr '\n' ' ' | cut -c1-200)" >> $LOG
fi
