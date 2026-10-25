#!/bin/sh
# WiFi 켜기 (시험판): 전원을 켜면 꺼져 있는 WiFi 를 카메라 WiFi 화면 없이 켜고 저장된 네트워크에 붙인다.
# 카메라는 ConnMan (connmand) 과 Tizen net-config 가 네트워크를 관리한다 (2026-10-25 조사, log/wifi_probe_*.txt).
# 순서 (각 단계 결과를 log/wifi.log 에):
#   1. mlan0 이 없으면 드라이버 적재 시도: net-config D-Bus LoadDriver, 안 되면 /usr/bin/wlan.sh start
#   2. ConnMan WiFi 기술 켜기 (Technology.SetProperty Powered true)
#   3. 최대 25초 동안 IP 를 기다림. 안 붙으면 즐겨찾기 (Favorite) 서비스에 Service.Connect 를 차례로
#   4. 결과 팝업
# 읽기 외의 동작은 D-Bus 속성 설정과 연결 요청뿐이다. 되돌리려면 카메라 WiFi 설정에서 끄거나 전원을 다시 켠다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
LOG="$D/log/wifi.log"
wl() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; sync; }
DBUS="dbus-send --system --print-reply --dest"
has_if() { [ -d /sys/class/net/mlan0 ]; }
ip_now() { wifi_ip; }
wl "wifi_on start: if=$(has_if && echo yes || echo no) ip=$(ip_now) modules=$(cut -d' ' -f1 /proc/modules | tr '\n' ' ')"
if ! has_if; then
  wl "step1 LoadDriver via net-config"
  R=$($DBUS=net.netconfig /net/netconfig/wifi net.netconfig.wifi.LoadDriver 2>&1 | tail -3 | tr '\n' ' '); wl "  net.netconfig.wifi.LoadDriver -> $R"
  sleep 3
  if ! has_if; then
    R=$(sh /usr/bin/wlan.sh start 2>&1 | tail -3 | tr '\n' ' '); wl "  wlan.sh start -> $R"
    sleep 3
  fi
fi
wl "step2 connman Powered=true (if=$(has_if && echo yes || echo no))"
R=$($DBUS=net.connman /net/connman/technology/wifi net.connman.Technology.SetProperty string:Powered variant:boolean:true 2>&1 | tail -2 | tr '\n' ' '); wl "  SetProperty Powered -> $R"
n=0
while [ $n -lt 25 ] && [ -z "$(ip_now)" ]; do sleep 1; n=$((n+1)); done
if [ -z "$(ip_now)" ]; then
  wl "step3 no ip after ${n}s, scan + connect favorites"
  $DBUS=net.connman /net/connman/technology/wifi net.connman.Technology.Scan > /dev/null 2>&1; sleep 4
  SVCS=$($DBUS=net.connman / net.connman.Manager.GetServices 2>/dev/null | grep -o '/net/connman/service/wifi_[^"]*')
  for s in $SVCS; do
    [ -n "$(ip_now)" ] && break
    FAV=$($DBUS=net.connman "$s" net.connman.Service.GetProperties 2>/dev/null | grep -A1 '"Favorite"' | grep -o 'boolean [a-z]*')
    wl "  service $s favorite=$FAV"
    case "$FAV" in *true) R=$($DBUS=net.connman "$s" net.connman.Service.Connect 2>&1 | tail -2 | tr '\n' ' '); wl "  Connect -> $R"; m=0; while [ $m -lt 15 ] && [ -z "$(ip_now)" ]; do sleep 1; m=$((m+1)); done ;; esac
  done
fi
IP=$(ip_now)
wl "wifi_on end: if=$(has_if && echo yes || echo no) ip=${IP:-none}"
if [ -n "$IP" ]; then popup "WiFi 켜짐  IP: $IP" 4; else popup "WiFi 연결 안 됨<br>log/wifi.log 확인" 4; fi
