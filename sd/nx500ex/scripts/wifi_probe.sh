#!/bin/sh
# WiFi 조사: 카메라가 WiFi 를 어떻게 켜고 연결하는지 알아내기 위한 읽기 전용 수집. 결과는 log/wifi_probe_<번호>.txt 에.
#   sh /mnt/mmc/nx500ex/scripts/wifi_probe.sh 1    (전원 켠 직후, WiFi 꺼진 상태에서)
#   sh /mnt/mmc/nx500ex/scripts/wifi_probe.sh 2    (카메라 WiFi 기능 화면에 들어가 핫스팟에 연결된 상태에서, 그 화면에 머문 채)
#   sh /mnt/mmc/nx500ex/scripts/wifi_probe.sh 3    (WiFi 화면에서 나와 촬영 화면으로 돌아온 직후)
# 아무것도 바꾸지 않는다. ConnMan (connmand) 이 돌고 있어 그 상태 파일과 D-Bus 도구가 있는지가 핵심.
D=${NX500EX:-/mnt/mmc/nx500ex}
mkdir -p "$D/log"
OUT="$D/log/wifi_probe_${1:-x}.txt"
exec > "$OUT" 2>&1
echo "### wifi probe ${1:-x} $(date '+%Y-%m-%d %H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime)"
sec() { echo; echo "===== $*"; }
sec "ip addr"; ip addr 2>&1
sec "ip route"; ip route 2>&1
sec "resolv.conf"; cat /etc/resolv.conf 2>&1
sec "프로세스 (네트워크 관련)"; ps 2>/dev/null | grep -i -E "connman|wpa|dhcp|mlan|wlan|hostapd|dbus|net|wifi" | grep -v grep
sec "커널 모듈"; cat /proc/modules 2>&1 | head -40
sec "/sys/class/net"; ls -l /sys/class/net/ 2>&1; for n in /sys/class/net/*; do echo "$n operstate=$(cat $n/operstate 2>/dev/null) flags=$(cat $n/flags 2>/dev/null)"; done
sec "도구 유무"; for b in connmanctl dbus-send dbus-monitor wpa_cli wpa_supplicant iw iwconfig iwlist ifconfig udhcpc dhclient wlan.sh wifi.sh; do p=$(which $b 2>/dev/null); [ -n "$p" ] && echo "있음 $b -> $p" || echo "없음 $b"; done
sec "connman 상태 파일"; ls -la /var/lib/connman/ 2>&1; for f in /var/lib/connman/settings /var/lib/connman/*/settings; do [ -f "$f" ] && { echo "--- $f"; sed 's/\(Passphrase=\).*/\1(숨김)/' "$f"; }; done
sec "connman 설정"; ls -la /etc/connman/ 2>&1; cat /etc/connman/main.conf 2>&1 | head -60
sec "wpa_supplicant 설정 후보"; ls -la /etc/wpa_supplicant/ /opt/etc/wpa_supplicant/ /opt/etc/wifi/ /opt/usr/share/wifi/ 2>&1; find / -xdev -name "wpa_supplicant*.conf" 2>/dev/null | head; find / -xdev -name "*.conf" -path "*wifi*" 2>/dev/null | head
sec "wlan.sh 류 스크립트"; find / -xdev -name "wlan*" -o -xdev -name "wifi*" 2>/dev/null | grep -v -E "^/proc|^/sys" | head -40
sec "ap_setting (카메라 앱의 WiFi 요청 통로)"; ls -la /tmp/var/run/memory/ap_setting/ 2>&1; for f in /tmp/var/run/memory/ap_setting/*; do [ -f "$f" ] && echo "$f: $(od -An -tx1 -N 32 "$f" 2>/dev/null | tr -s ' ')"; done
sec "capdtm WIFIMODE"; st cap capdtm getusr WIFIMODE 2>&1 | tr -d '\000'
sec "prefman WiFi 관련 (이름에 WIFI 가 든 것, 값은 번호만)"; prefman list 2>/dev/null | grep -i wifi | head -30
sec "dbus 서비스 목록"; ls -la /usr/share/dbus-1/system-services/ 2>&1 | head -30; ls /var/run/dbus/ 2>&1
sec "D-Bus 로 connman 기술 상태 (읽기만)"; dbus-send --system --print-reply --dest=net.connman /net/connman/technology/wifi net.connman.Technology.GetProperties 2>&1 | head -30
sec "D-Bus 로 connman 서비스 목록 (읽기만)"; dbus-send --system --print-reply --dest=net.connman / net.connman.Manager.GetServices 2>&1 | grep -E "object path|Name|State|Favorite|AutoConnect|Strength" | head -40
sec "wlan.sh 내용"; cat /usr/bin/wlan.sh 2>&1 | head -120
sec "net-config (Tizen 네트워크 설정 데몬) D-Bus 인터페이스"; for o in /net/netconfig/wifi /net/netconfig/network /net/netconfig/statistics; do echo "--- $o"; dbus-send --system --print-reply --dest=net.netconfig $o org.freedesktop.DBus.Introspectable.Introspect 2>&1 | grep -E "interface name|method name|property name|arg " | head -120; done
sec "connman Manager 인터페이스"; dbus-send --system --print-reply --dest=net.connman / org.freedesktop.DBus.Introspectable.Introspect 2>&1 | grep -E "method name" | head -40
sec "connman 기술 목록"; dbus-send --system --print-reply --dest=net.connman / net.connman.Manager.GetTechnologies 2>&1 | head -60
sec "connman 서비스 전체 (값 포함)"; dbus-send --system --print-reply --dest=net.connman / net.connman.Manager.GetServices 2>&1 | grep -v -E "^\s*(byte|int32|uint16) " | head -600
sec "connman 저장 위치 찾기 (settings 파일)"; find / -xdev \( -name settings -o -name "*.config" \) -path "*connman*" 2>/dev/null | head; find /opt /var /tmp -xdev -type d -name connman 2>/dev/null | head; ls -la /opt/var/lib/connman/ /opt/etc/connman/ 2>&1 | head -30; for f in /opt/var/lib/connman/*/settings; do [ -f "$f" ] && { echo "--- $f"; sed "s/\(Passphrase=\).*/\1(숨김)/" "$f"; }; done
sec "nxpopup 프로세스 (남아 있는 것)"; ps 2>/dev/null | grep -E "nxpopup|popup_" | grep -v grep
sec "프로세스 (busybox ps, 인자 포함)"; "$D/bin/busybox" ps -o pid,args 2>/dev/null | grep -i -E "connman|net-config|wpa|dhcp|wlan|hostapd|dbus|wifi" | grep -v grep
sec "로그 꼬리: connman.log"; tail -n 60 /var/log/connman.log 2>&1
sec "로그 꼬리: netconfig.log"; tail -n 80 /var/log/netconfig.log 2>&1
sec "로그 꼬리: wlanplug_log"; tail -n 40 /var/log/wlanplug_log 2>&1
sec "syslog, dlog 중 wifi 줄 (최근)"; ls /var/log/ 2>&1; tail -n 2000 /var/log/messages 2>/dev/null | grep -i -E "wifi|wlan|mlan|connman|wpa" | tail -40
sync
echo "### end"
