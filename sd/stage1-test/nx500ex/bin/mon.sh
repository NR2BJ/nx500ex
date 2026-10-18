#!/bin/sh
# 진단용 감시: 1초마다 keyscan, bluetoothd, SD 상태를 확인하고 바뀐 순간만 기록한다.
# RAM(/tmp) 에 먼저 쓰고, SD 가 마운트돼 있으면 새로 생긴 줄만 SD 로 덧붙인 뒤 sync 한다.
T=/tmp/nx500ex-mon.log
S=/mnt/mmc/nx500ex/log/mon.log
K=/tmp/nx500ex-keyscan.out
SK=/mnt/mmc/nx500ex/log/keyscan.out

# 중복 실행 방지 (pid 재사용 대비로 comm 도 확인)
if [ -f /tmp/nx500ex-mon.pid ]; then
  op=$(cat /tmp/nx500ex-mon.pid)
  grep -q mon.sh /proc/$op/cmdline 2>/dev/null && exit 0
fi
echo $$ > /tmp/nx500ex-mon.pid
touch $T $K

state() {
  out=""
  for d in /proc/[0-9]*; do
    c=$(cat $d/comm 2>/dev/null)
    case "$c" in
      keyscan|bluetoothd*)
        st=$(sed -n 's/^State:[[:space:]]*\([A-Z]\).*/\1/p' $d/status 2>/dev/null)
        wc=$(cat $d/wchan 2>/dev/null)
        out="$out $c:${d#/proc/}:$st:$wc";;
    esac
  done
  if grep -q ' /opt/storage/sdcard ' /proc/mounts; then out="$out sd:on"; else out="$out sd:off"; fi
  echo "$out"
}

# 파일 $1 의 줄 중 아직 SD($2)로 보내지 않은 것만 덧붙인다. 보낸 줄 수는 $3 에 저장.
push() {
  sent=$(cat $3 2>/dev/null); sent=${sent:-0}
  total=$(wc -l < $1)
  if [ "$total" -gt "$sent" ]; then
    tail -n +$((sent+1)) $1 | head -n $((total-sent)) >> $2 && echo $total > $3
  fi
}

prev=""
n=0
while :; do
  cur=$(state)
  n=$((n+1))
  if [ "$cur" != "$prev" ] || [ $((n % 30)) -eq 0 ]; then
    echo "$(date '+%H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime)$cur" >> $T
    prev=$cur
  fi
  if grep -q ' /opt/storage/sdcard ' /proc/mounts; then
    push $T $S /tmp/nx500ex-mon.sent
    push $K $SK /tmp/nx500ex-keyscan.sent
    sync
  fi
  sleep 1
done
