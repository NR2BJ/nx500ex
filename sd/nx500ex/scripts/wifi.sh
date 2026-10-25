#!/bin/sh
# WiFi: 카메라 WiFi 화면 없이 켜고 끄고 저장된 네트워크를 고른다. 붙어 있는 동안은 뒤에서 감시해 끊기면 알리고 다시 붙인다.
#   wifi.sh            켜기 (메뉴 체크박스 "WiFi 켜기": 켜 두면 전원을 켤 때마다 auto 에서 다시 켬)
#   wifi.sh on         켜기. 전원을 켜면 WiFi 는 꺼져 있고 드라이버도 안 올라가 있다
#   wifi.sh off        끄기 (off_wifi.sh 가 부름: 체크 해제, 블루투스 끔)
#   wifi.sh list       저장된 네트워크로 scripts/gui_wifi.NX500 화면을 만든다 (메뉴 "WiFi 네트워크 >" 의 "목록 새로 고침")
#   wifi.sh connect <서비스 id 또는 경로>   그 네트워크에 연결 (목록 화면의 버튼). 안 보이면 검색을 한 번 더 한다
#   wifi.sh status     IP 와 연결된 이름 팝업
#   wifi.sh watch      (내부) 연결 감시. on 과 connect 가 성공하면 뒤에서 띄운다
# 원리 (2026-10-25 조사, log/wifi_probe_*.txt, netconfig.log): 카메라는 Tizen net-config 와 ConnMan 이 WiFi 를 관리한다.
#   켜기 = D-Bus net.netconfig.wifi.LoadDriver boolean:false (wpa_supplicant 시작, 드라이버 적재, ConnMan Powered).
#   끄기 = net.netconfig.wifi.RemoveDriver. 연결 = net.connman.Service.Connect.
#   실기 (2026-10-26): 켜고 검색까지 해도 ConnMan 이 저장된 네트워크에 스스로 붙지 않는다. 직접 Connect 는 1 초 만에 붙는다.
#   wlan.sh 로 드라이버만 올리면 wpa_supplicant 가 없어 연결이 안 된다 (시험판에서 확인).
# 연결 순서: 검색에 보이는 (신호 세기 > 0) 저장된 네트워크 중 ConnMan 순서 (마지막에 쓴 것이 앞) 대로 시도, 안 되면 다음.
#   conf/wifi_order.txt 에 이름을 한 줄씩 적어 두면 그 순서를 먼저 따른다 (없으면 ConnMan 순서).
# 저장된 네트워크는 /opt/var/lib/connman/<서비스 id>/settings (Name=, Passphrase=) 에 있다. ConnMan 의 GetServices 는 지금 검색에 보이는 것만
#   돌려주므로 (안 보이는 즐겨찾기는 빠짐, 2026-10-26 probe 5), 목록 화면은 저장 폴더에서 만들고 보이는지 표시만 한다.
# 체크박스에서 실행되면 메뉴가 열린 채라 팝업이 메뉴 뒤에 뜬다 (nxmenu 의 checkbox 는 메뉴를 닫지 않음). 메뉴가 닫힌 뒤 팝업을 띄운다 (menu_popup).
# 한 번 붙으면 촬영 화면에서도 유지된다. 텔넷/FTP 는 WiFi 와 무관하게 떠 있으므로 붙는 순간부터 접속된다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
LOG="$D/log/wifi.log"
[ -f "$LOG" ] && [ "$(wc -c < "$LOG" | tr -d ' ')" -gt 200000 ] && mv "$LOG" "$LOG.old"
wl() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; sync; }
DB="dbus-send --system --print-reply"
WPID=/tmp/nx500ex-wifi.pid
GUI="$D/scripts/gui_wifi.NX500"
powered() { $DB --dest=net.connman /net/connman/technology/wifi net.connman.Technology.GetProperties 2>/dev/null | grep -A1 '"Powered"' | grep -q 'boolean true'; }
driver_up() { [ -d /sys/class/net/mlan0 ]; }
# 서비스 목록: 경로|이름|상태|즐겨찾기|세기 (ConnMan GetServices 출력을 블록별로 묶음. dict 키 줄은 끝까지 일치시켜 Nameservers 와 구분)
services() {
  $DB --dest=net.connman / net.connman.Manager.GetServices 2>/dev/null | tr -d '\000' | awk '
    /object path "\/net\/connman\/service\// { if (p != "") print p "|" n "|" s "|" f "|" g; match($0, /\/net\/connman\/service\/[^"]*/); p = substr($0, RSTART, RLENGTH); n = ""; s = ""; f = ""; g = 0; key = ""; next }
    /string "Name"[ ]*$/ { key = "Name"; next }
    /string "State"[ ]*$/ { key = "State"; next }
    /string "Favorite"[ ]*$/ { key = "Favorite"; next }
    /string "Strength"[ ]*$/ { key = "Strength"; next }
    /variant/ && key == "Name" { match($0, /string "[^"]*"/); n = substr($0, RSTART + 8, RLENGTH - 9); key = "" }
    /variant/ && key == "State" { match($0, /string "[^"]*"/); s = substr($0, RSTART + 8, RLENGTH - 9); key = "" }
    /variant/ && key == "Favorite" { f = ($0 ~ /true/) ? "yes" : "no"; key = "" }
    /variant/ && key == "Strength" { match($0, /[0-9]+[ ]*$/); g = substr($0, RSTART, RLENGTH) + 0; key = "" }
    /^[ ]*string "/ && key != "" { key = "" }
    END { if (p != "") print p "|" n "|" s "|" f "|" g }'
}
STORE=/opt/var/lib/connman
# 저장된 네트워크: id|이름 (저장 폴더의 settings 에서)
saved() { for f in $STORE/wifi_*/settings; do [ -f "$f" ] || continue; _id=${f%/settings}; _id=${_id##*/}; _nm=$(sed -n 's/^Name=//p' "$f" | head -1); [ -n "$_nm" ] && echo "$_id|$_nm"; done; }
saved_name() { sed -n 's/^Name=//p' "$STORE/$1/settings" 2>/dev/null | head -1; }
# 메뉴 (nxmenu) 가 열려 있으면 닫힐 때까지 (최대 60 초) 기다렸다가 팝업
menu_open() { [ -f /tmp/nx500ex-menu.pid ] && [ -d /proc/$(cat /tmp/nx500ex-menu.pid 2>/dev/null) ]; }
menu_popup() { _n=0; while menu_open && [ $_n -lt 60 ]; do sleep 1; _n=$((_n + 1)); done; popup "$@"; }
connected_name() { services | awk -F'|' '$3 == "online" || $3 == "ready" { print $2; exit }'; }
name_of() { services | awk -F'|' -v p="$1" '$1 == p { print $2 }'; }
wait_ip() { _n=0; while [ $_n -lt ${1:-20} ] && [ -z "$(wifi_ip)" ]; do sleep 1; _n=$((_n + 1)); done; [ -n "$(wifi_ip)" ]; }
# 연결 후보 (경로 목록): 보이는 즐겨찾기를 conf/wifi_order.txt 순서, 그다음 ConnMan 순서로. 하나도 안 보이면 즐겨찾기 전부.
candidates() {
  _s=$(services | awk -F'|' '$4 == "yes" && $2 != ""')
  _v=$(echo "$_s" | awk -F'|' '$5 > 0')
  [ -n "$_v" ] || _v=$_s
  if [ -f "$D/conf/wifi_order.txt" ]; then
    while read -r _name; do [ -n "$_name" ] && echo "$_v" | awk -F'|' -v n="$_name" '$2 == n { print $1 }'; done < "$D/conf/wifi_order.txt"
  fi
  echo "$_v" | cut -d'|' -f1
}
# 후보에 차례로 연결. 성공하면 0
try_connect() {
  _done=""
  for _p in $(candidates | awk '!seen[$0]++'); do
    _nm=$(name_of "$_p")
    wl "connect: $_nm ($_p)"
    _r=$($DB --dest=net.connman "$_p" net.connman.Service.Connect 2>&1 | tail -1); wl "  Connect -> $_r"
    wait_ip ${1:-12} && return 0
  done
  return 1
}
# 저장된 네트워크 화면을 다시 만든다 (팝업 없음). N 에 개수. * = 연결됨, (안 보임) = 지금 검색에 없음
make_list() {
  _sv=$(services)
  { echo "# 자동 생성 (wifi.sh). 저장된 네트워크 (/opt/var/lib/connman). * = 연결됨, (안 보임) = 지금 검색에 없음"
    echo "back|gui_more"
    echo "button|목록 새로 고침|wifi.sh list"
    saved | while IFS='|' read -r _id _nm; do
      _st=$(echo "$_sv" | awk -F'|' -v p="/net/connman/service/$_id" '$1 == p { print $3 }')
      case "$_st" in online|ready) echo "button|* $_nm|wifi.sh connect $_id" ;; "") echo "button|$_nm (안 보임)|wifi.sh connect $_id" ;; *) echo "button|$_nm|wifi.sh connect $_id" ;; esac
    done | head -6
    echo "button|WiFi 끄기|wifi.sh off"
  } > "$GUI"; sync
  N=$(grep -c "wifi.sh connect" "$GUI")
  wl "list: $N saved, $(echo "$_sv" | awk -F'|' '$4 == "yes"' | wc -l | tr -d ' ') visible favorites"
}
watch_start() {
  watch_stop
  sh "$D/scripts/wifi.sh" watch < /dev/null > /dev/null 2>&1 &
}
watch_stop() {
  if [ -f $WPID ]; then kill $(cat $WPID) 2>/dev/null; rm -f $WPID; fi
}

wifi_on() {
  if [ -n "$(wifi_ip)" ]; then wl "on: already connected $(wifi_ip)"; return 0; fi
  if ! powered || ! driver_up; then
    R=$($DB --dest=net.netconfig /net/netconfig/wifi net.netconfig.wifi.LoadDriver boolean:false 2>&1 | tail -1)
    wl "on: LoadDriver -> $R"
    _n=0; while [ $_n -lt 10 ] && ! powered; do sleep 1; _n=$((_n + 1)); done
  else
    wl "on: already powered"
  fi
  R=$($DB --dest=net.connman /net/connman/technology/wifi net.connman.Technology.Scan 2>&1 | tail -1); wl "on: Scan -> $R"
  wait_ip 1 && return 0
  try_connect 12 && return 0
  wl "on: services: $(services | tr '\n' ' ')"
  return 1
}

case "${1:-on}" in
  on)
    # 전원 켤 때 (scripts/auto/wifi.sh 로 실행) 는 nxkeys 가 auto 스크립트를 기다리므로 뒤에서 돌린다
    case "$0" in */auto/*) [ "$NXWIFI_BG" = 1 ] || { NXWIFI_BG=1 sh "$0" on < /dev/null > /dev/null 2>&1 & exit 0; } ;; esac
    wl "on start (if=$(driver_up && echo yes || echo no) from=$0)"
    if wifi_on; then
      wl "on done ip=$(wifi_ip) name=$(connected_name)"; watch_start; make_list
      case "$0" in */auto/*) sleep 3 ;; esac   # 전원 켤 때는 카메라 화면이 다 뜬 뒤에
      menu_popup "WiFi 켜짐: $(connected_name)<br>IP $(wifi_ip)" 4
    else wl "on failed (no ip)"; make_list; menu_popup "WiFi 연결 안 됨<br>WiFi 네트워크 > 에서 고르세요" 4; fi
    ;;
  off)
    watch_stop
    R=$($DB --dest=net.netconfig /net/netconfig/wifi net.netconfig.wifi.RemoveDriver 2>&1 | tail -1)
    wl "off: RemoveDriver -> $R"
    sed -i 's/^button|\* /button|/' "$GUI" 2>/dev/null; sync
    menu_popup "WiFi 끔" 2
    ;;
  status)
    IP=$(wifi_ip)
    [ -n "$IP" ] && popup "WiFi: $(connected_name)<br>IP $IP" 4 || popup "WiFi 연결 안 됨" 3
    ;;
  list)
    # 꺼져 있으면 먼저 켠다 (목록을 읽으려면 ConnMan 이 켜져 있어야 함). 검색을 한 번 해서 보이는지 표시
    powered || { wl "list: powering on"; wifi_on > /dev/null; }
    $DB --dest=net.connman /net/connman/technology/wifi net.connman.Technology.Scan > /dev/null 2>&1
    make_list
    popup "저장된 네트워크 ${N}개<br>WiFi 네트워크 > 를 다시 여세요" 3
    ;;
  connect)
    [ -n "$2" ] || { popup "네트워크 없음" 2; exit 1; }
    ID=${2#/net/connman/service/}; P=/net/connman/service/$ID
    NAME=$(saved_name "$ID"); [ -n "$NAME" ] || NAME=$(name_of "$P")
    powered || wifi_on > /dev/null
    if ! services | grep -q "^$P|"; then
      $DB --dest=net.connman /net/connman/technology/wifi net.connman.Technology.Scan > /dev/null 2>&1; sleep 2
      services | grep -q "^$P|" || { wl "connect (menu) $NAME not visible"; make_list; popup "안 보임: $NAME<br>그 네트워크가 켜져 있는지 확인" 4; exit 1; }
    fi
    wl "connect (menu) $NAME ($ID)"
    R=$($DB --dest=net.connman "$P" net.connman.Service.Connect 2>&1 | tail -1); wl "  Connect -> $R"
    if wait_ip 20 && [ "$(connected_name)" = "$NAME" ]; then watch_start; make_list; popup "WiFi: $NAME<br>IP $(wifi_ip)" 4
    else make_list; popup "연결 안 됨: $NAME<br>log/wifi.log 확인" 4; fi
    ;;
  watch)
    # 5 초마다 IP 확인. 끊기면 알리고 15 초 간격으로 다시 붙인다. 드라이버가 내려가면 (순정 설정이나 우리 off 로 껐음) 감시를 끝낸다.
    echo $$ > $WPID
    had=1; lastname=$(connected_name)
    while :; do
      sleep 5
      driver_up || { wl "watch: driver gone, stop"; popup "WiFi 꺼짐" 2; break; }
      if [ -n "$(wifi_ip)" ]; then
        if [ "$had" = 0 ]; then had=1; lastname=$(connected_name); wl "watch: reconnected $(wifi_ip) $lastname"; popup "WiFi 다시 연결: $lastname<br>IP $(wifi_ip)" 3; make_list; fi
      else
        if [ "$had" = 1 ]; then had=0; wl "watch: lost ($lastname)"; popup "WiFi 끊김: $lastname<br>다시 연결 시도 중" 3; fi
        $DB --dest=net.connman /net/connman/technology/wifi net.connman.Technology.Scan > /dev/null 2>&1
        try_connect 8 || sleep 10
      fi
    done
    rm -f $WPID
    ;;
  *) popup "wifi.sh on|off|list|connect|status" 3 ;;
esac
