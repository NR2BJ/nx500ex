#!/bin/sh
# nx500ex boot.sh: 래퍼가 SD 마운트 후 부른다. keyscan 을 SD 의 scripts 폴더 대상으로 시작한다.
D=/mnt/mmc/nx500ex
mkdir -p $D/log
LOG=$D/log/boot.log
[ -f $LOG ] && [ $(wc -c < $LOG) -gt 100000 ] && mv $LOG $LOG.old
now() { echo "$(date '+%Y-%m-%d %H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime)"; }
echo "$(now) boot.sh start pid=$$ ppid=$PPID" >> $LOG
# 진단: 이 스크립트가 속한 cgroup (블루투스 서비스에 묶여 있는지)
sed 's/^/  cgroup /' /proc/$$/cgroup >> $LOG 2>/dev/null

# 동영상 녹화 중이면 끝날 때까지 기다린다 (최대 10분)
n=0
while st pmu show 2>/dev/null | grep hevc | grep -q ON && [ $n -lt 600 ]; do sleep 1; n=$((n+1)); done

export MODEL=$(grep -x 'NX[0-9]*' /etc/version.info)
export NX500EX=$D
cd /
nice -n 15 $D/bin/keyscan /dev/event0 /dev/event1 $D/scripts/ > /tmp/nx500ex-keyscan.out 2>&1 &
KPID=$!
sleep 1
if kill -0 $KPID 2>/dev/null; then
  echo "$(now) keyscan started pid=$KPID" >> $LOG
else
  echo "$(now) keyscan exited: $(tr '\n' ' ' < /tmp/nx500ex-keyscan.out | cut -c1-200)" >> $LOG
fi
