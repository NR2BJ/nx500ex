#!/bin/sh
# EV+WiFi: 텔넷/FTP 켜기 (이번 전원 동안만. 계속 켜 두려면 메뉴의 체크박스)
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
sh "$D/scripts/telnet.sh"
ip addr ls mlan0 2>/dev/null | grep -q 'inet ' || popup "Telnet/FTP ON. Connect WiFi first" 3
