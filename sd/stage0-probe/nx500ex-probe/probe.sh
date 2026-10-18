#!/bin/sh
# nx500ex stage 0 probe
#
# factory mode(info.tg) 로 한 번 실행되어 카메라 정보를 SD 카드에 저장한다.
# 카메라 내장 저장소에는 아무것도 쓰지 않는다. 읽기와 SD 쓰기만 한다.
# 실행이 끝나면 info.tg 를 info.tg.done 으로 바꿔 다음 부팅은 정상 모드가 된다.

SD=/mnt/mmc
BASE=$SD/nx500ex-probe
OUT=$BASE/out-$(date +%Y%m%d-%H%M%S)

osd() { dfmstool -s "osd string $1 $2" 2>/dev/null; }

dfmsd -t &
sleep 3
osd 2 "nx500ex probe - do not power off"
osd 3 "collecting..."

mkdir -p "$OUT/prefman"

# 1. 기본 정보
{
  echo "== version.info"; cat /etc/version.info
  echo "== uname"; uname -a
  echo "== date"; date
  echo "== uptime"; cat /proc/uptime
} > "$OUT/system.txt" 2>&1

cat /proc/cpuinfo   > "$OUT/cpuinfo.txt"    2>&1
cat /proc/meminfo   > "$OUT/meminfo.txt"    2>&1
cat /proc/cmdline   > "$OUT/cmdline.txt"    2>&1
cat /proc/partitions > "$OUT/partitions.txt" 2>&1
mount               > "$OUT/mount.txt"      2>&1
df -h               > "$OUT/df.txt"         2>&1
ps                  > "$OUT/ps.txt"         2>&1
ps -ef             >> "$OUT/ps.txt"         2>&1
cat /proc/bus/input/devices > "$OUT/input-devices.txt" 2>&1
ls -la /dev/event* >> "$OUT/input-devices.txt" 2>&1

# 2. 기존 모드 흔적 확인 (bluetoothd 가 스크립트로 바뀌었는지 등)
{
  echo "== /usr/sbin/bluetoothd*"; ls -la /usr/sbin/bluetoothd* 2>&1
  echo "== bluetoothd head"; head -c 200 /usr/sbin/bluetoothd | strings 2>&1 | head -10
  echo "== /opt/usr"; ls -la /opt/usr 2>&1
  echo "== /opt/usr/nx-ks"; ls -la /opt/usr/nx-ks 2>&1 | head -20
  echo "== /opt/usr/nx-on-wake"; ls -la /opt/usr/nx-on-wake 2>&1
  echo "== /opt/usr/devel"; ls -la /opt/usr/devel 2>&1 | head -20
  echo "== nx-on-wake service"; ls -la /etc/systemd/system/ 2>&1 | grep -i wake
  echo "== /usr/local/bin"; ls -la /usr/local/bin 2>&1
} > "$OUT/existing-mods.txt" 2>&1

# 3. 도구 존재 여부
{
  for t in st prefman dfmstool busybox telnetd ftpd tcpsvd inetd httpd rtcwake systemctl python dropbear ssh; do
    printf '%-10s ' "$t"; which "$t" 2>/dev/null || echo "-"
  done
} > "$OUT/tools.txt" 2>&1

# 4. 서비스 목록
systemctl list-units --no-pager > "$OUT/systemd-units.txt" 2>&1

# 5. 카운터 (NX500: prefman 블록 3)
osd 3 "reading counters..."
val() { prefman get 3 "$1" l 2>/dev/null | grep value | cut -d" " -f4; }
SHUTTER=$(val 0x208)
POWERON=$(val 0x244)
FLASHIN=$(val 0x248)
FLASHEX=$(val 0x24c)
{
  echo "shutter=$SHUTTER"
  echo "poweron=$POWERON"
  echo "flash_internal=$FLASHIN"
  echo "flash_external=$FLASHEX"
} > "$OUT/counters.txt"

# 6. 일부 촬영 설정 읽기 (읽기만)
{
  for k in MONITOROUT DIALMODE ADJUSTSHUTTERTYPE AFMODE; do
    echo "== $k"; st cap capdtm getusr $k 2>&1
  done
} > "$OUT/capdtm.txt" 2>&1

# 7. 설정 전체 백업 (prefman 블록 0~10 을 SD 파일로 저장. 내장에는 쓰지 않음)
osd 3 "backing up settings..."
i=0
while [ $i -le 10 ]; do
  prefman save_file $i "$OUT/prefman/FullSave$i" > /dev/null 2>&1
  i=$((i+1))
done
ls -la "$OUT/prefman" > "$OUT/prefman-list.txt" 2>&1

sync; sync; sync

# 8. 다음 부팅부터는 정상 모드로
mv "$SD/info.tg" "$SD/info.tg.done" 2>/dev/null
sync; sync; sync

osd 3 "DONE. power off and remove card"
osd 4 "SHUTTER: $SHUTTER"
osd 5 "POWERON: $POWERON"
osd 6 "result: nx500ex-probe/out-*"
sleep 30
killall -KILL dfmsd
