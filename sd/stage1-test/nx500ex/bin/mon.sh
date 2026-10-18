#!/bin/sh
# 진단용 감시: 1초마다 keyscan, bluetoothd, SD 상태를 확인하고 바뀐 순간만 기록한다.
# 기록은 RAM(/tmp) 에 먼저 쓰고, SD 가 마운트돼 있으면 SD 로도 복사한다.
# SD 에서 실행되므로 전원 OFF 때 함께 종료될 수 있다. 다음 boot.sh 가 /tmp 기록을 SD 로 옮긴다.
T=/tmp/nx500ex-mon.log
S=/mnt/mmc/nx500ex/log/mon.log
K=/tmp/nx500ex-keyscan.out
SK=/mnt/mmc/nx500ex/log/keyscan.out

# 중복 실행 방지
if [ -f /tmp/nx500ex-mon.pid ] && [ -d /proc/$(cat /tmp/nx500ex-mon.pid) ]; then exit 0; fi
echo $$ > /tmp/nx500ex-mon.pid

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

prev=""
n=0
while :; do
  cur=$(state)
  n=$((n+1))
  if [ "$cur" != "$prev" ] || [ $((n % 30)) -eq 0 ]; then
    echo "$(date '+%H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime)$cur" >> $T
    prev=$cur
  fi
  if [ $((n % 3)) -eq 0 ] && grep -q ' /opt/storage/sdcard ' /proc/mounts; then
    cp $T $S 2>/dev/null
    cp $K $SK 2>/dev/null
  fi
  sleep 1
done
