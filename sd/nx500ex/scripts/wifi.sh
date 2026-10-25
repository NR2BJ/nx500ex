#!/bin/sh
# WiFi: 카메라 WiFi 화면 없이 켜고 끄고 저장된 네트워크를 고른다.
#   wifi.sh            켜기 (메뉴 체크박스 "WiFi 켜기": 켜 두면 전원을 켤 때마다 auto 에서 다시 켬)
#   wifi.sh on         켜기. 전원을 켜면 WiFi 는 꺼져 있고 드라이버도 안 올라가 있다
#   wifi.sh off        끄기 (off_wifi.sh 가 부름: 체크 해제, 블루투스 끔)
#   wifi.sh list       저장된 네트워크로 scripts/gui_wifi.NX500 화면을 만든다 (메뉴 "WiFi 네트워크 >" 의 "목록 새로 고침")
#   wifi.sh connect <ConnMan 서비스 경로>   그 네트워크에 연결 (목록 화면의 버튼)
#   wifi.sh status     IP 와 연결된 이름 팝업
# 원리 (2026-10-25 조사, log/wifi_probe_*.txt, netconfig.log): 카메라는 Tizen net-config 와 ConnMan 이 WiFi 를 관리한다.
#   켜기 = D-Bus net.netconfig.wifi.LoadDriver (wpa_supplicant 시작, 드라이버 적재, ConnMan Powered) -> ConnMan 이 저장된 네트워크에 자동 연결.
#   끄기 = net.netconfig.wifi.RemoveDriver. 연결 바꾸기 = net.connman.Service.Connect.
#   wlan.sh 로 드라이버만 올리면 wpa_supplicant 가 없어 연결이 안 된다 (시험판에서 확인).
# 한 번 붙으면 촬영 화면에서도 유지된다. 텔넷/FTP 는 WiFi 와 무관하게 떠 있으므로 붙는 순간부터 접속된다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
LOG="$D/log/wifi.log"
wl() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; sync; }
DB="dbus-send --system --print-reply"
powered() { $DB --dest=net.connman /net/connman/technology/wifi net.connman.Technology.GetProperties 2>/dev/null | grep -A1 '"Powered"' | grep -q 'boolean true'; }
# 서비스 목록: 경로|이름|상태|즐겨찾기 (ConnMan GetServices 출력을 블록별로 묶음)
services() {
  $DB --dest=net.connman / net.connman.Manager.GetServices 2>/dev/null | tr -d '\000' | awk '
    /object path "\/net\/connman\/service\// { if (p != "") print p "|" n "|" s "|" f; match($0, /\/net\/connman\/service\/[^"]*/); p = substr($0, RSTART, RLENGTH); n = ""; s = ""; f = ""; key = ""; next }
    /string "Name"[ ]*$/ { key = "Name"; next }
    /string "State"[ ]*$/ { key = "State"; next }
    /string "Favorite"[ ]*$/ { key = "Favorite"; next }
    /variant/ && key == "Name" { match($0, /string "[^"]*"/); n = substr($0, RSTART + 8, RLENGTH - 9); key = "" }
    /variant/ && key == "State" { match($0, /string "[^"]*"/); s = substr($0, RSTART + 8, RLENGTH - 9); key = "" }
    /variant/ && key == "Favorite" { f = ($0 ~ /true/) ? "yes" : "no"; key = "" }
    /^[ ]*string "/ && key != "" { key = "" }
    END { if (p != "") print p "|" n "|" s "|" f }'
}
connected_name() { services | awk -F'|' '$3 == "online" || $3 == "ready" { print $2; exit }'; }
wait_ip() { _n=0; while [ $_n -lt ${1:-20} ] && [ -z "$(wifi_ip)" ]; do sleep 1; _n=$((_n + 1)); done; [ -n "$(wifi_ip)" ]; }

first_favorite() { services | awk -F'|' '$4 == "yes" && $2 != "" { print $1; exit }'; }
name_of() { services | awk -F'|' -v p="$1" '$1 == p { print $2 }'; }

wifi_on() {
  if [ -n "$(wifi_ip)" ]; then wl "on: already connected $(wifi_ip)"; return 0; fi
  if ! powered || [ ! -d /sys/class/net/mlan0 ]; then
    R=$($DB --dest=net.netconfig /net/netconfig/wifi net.netconfig.wifi.LoadDriver boolean:false 2>&1 | tail -1)
    case "$R" in *UnknownMethod*|*Invalid*) R=$($DB --dest=net.netconfig /net/netconfig/wifi net.netconfig.wifi.LoadDriver 2>&1 | tail -1) ;; esac
    wl "on: LoadDriver -> $R"
    _n=0; while [ $_n -lt 10 ] && ! powered; do sleep 1; _n=$((_n + 1)); done
  else
    wl "on: already powered"
  fi
  # 켜진 것만으로는 저장된 네트워크에 안 붙었다 (2026-10-25 실기: LoadDriver 성공 뒤 25 초 동안 IP 없음, 직접 Connect 는 1 초 만에 연결).
  # 검색을 한 번 시키고 자동 연결을 잠깐 기다린 뒤, 안 붙으면 첫 즐겨찾기 (ConnMan 이 마지막에 쓴 것을 앞에 둔다) 에 직접 연결한다.
  R=$($DB --dest=net.connman /net/connman/technology/wifi net.connman.Technology.Scan 2>&1 | tail -1); wl "on: Scan -> $R"
  wait_ip 5 && return 0
  P=$(first_favorite)
  if [ -n "$P" ]; then
    wl "on: Connect $(name_of "$P") ($P)"
    R=$($DB --dest=net.connman "$P" net.connman.Service.Connect 2>&1 | tail -1); wl "  Connect -> $R"
    wait_ip 15 && return 0
  else
    wl "on: no favorite service"
  fi
  wl "on: services: $(services | tr '\n' ' ')"
  return 1
}

case "${1:-on}" in
  on)
    # 전원 켤 때 (scripts/auto/wifi.sh 로 실행) 는 nxkeys 가 auto 스크립트를 기다리므로 뒤에서 돌린다 (연결 대기 최대 25 초)
    case "$0" in */auto/*) [ "$NXWIFI_BG" = 1 ] || { NXWIFI_BG=1 sh "$0" on < /dev/null > /dev/null 2>&1 & exit 0; } ;; esac
    wl "on start (if=$([ -d /sys/class/net/mlan0 ] && echo yes || echo no) from=$0)"
    if wifi_on; then wl "on done ip=$(wifi_ip) name=$(connected_name)"; popup "WiFi 켜짐: $(connected_name)<br>IP $(wifi_ip)" 4
    else wl "on failed (no ip)"; popup "WiFi 연결 안 됨<br>WiFi 네트워크 > 에서 고르세요" 4; fi
    ;;
  off)
    R=$($DB --dest=net.netconfig /net/netconfig/wifi net.netconfig.wifi.RemoveDriver 2>&1 | tail -1)
    wl "off: RemoveDriver -> $R"
    popup "WiFi 끔" 2
    ;;
  status)
    IP=$(wifi_ip)
    [ -n "$IP" ] && popup "WiFi: $(connected_name)<br>IP $IP" 4 || popup "WiFi 연결 안 됨" 3
    ;;
  list)
    # 저장된 네트워크 (즐겨찾기) 를 화면으로. 꺼져 있으면 먼저 켠다 (목록을 읽으려면 ConnMan 이 켜져 있어야 함)
    powered || { wl "list: powering on"; wifi_on > /dev/null; }
    F="$D/scripts/gui_wifi.NX500"
    { echo "# 자동 생성 (wifi.sh list). 저장된 네트워크. 상태: online/ready = 연결됨"
      echo "back|gui_more"
      echo "button|목록 새로 고침|wifi.sh list"
      services | awk -F'|' '$4 == "yes" && $2 != "" { mark = ($3 == "online" || $3 == "ready") ? "* " : ""; print "button|" mark $2 "|wifi.sh connect " $1 }' | head -6
      echo "button|WiFi 끄기|wifi.sh off"
    } > "$F"; sync
    N=$(grep -c "wifi.sh connect" "$F")
    wl "list: $N favorites"
    popup "저장된 네트워크 ${N}개<br>WiFi 네트워크 > 를 다시 여세요" 3
    ;;
  connect)
    [ -n "$2" ] || { popup "네트워크 경로 없음" 2; exit 1; }
    powered || wifi_on > /dev/null
    NAME=$(name_of "$2")
    wl "connect $NAME ($2)"
    R=$($DB --dest=net.connman "$2" net.connman.Service.Connect 2>&1 | tail -1); wl "  Connect -> $R"
    if wait_ip 20 && [ "$(connected_name)" = "$NAME" ]; then popup "WiFi: $NAME<br>IP $(wifi_ip)" 4; sh "$D/scripts/wifi.sh" list > /dev/null 2>&1
    else popup "연결 안 됨: $NAME<br>log/wifi.log 확인" 4; fi
    ;;
  *) popup "wifi.sh on|off|list|connect|status" 3 ;;
esac
