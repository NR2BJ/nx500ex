#!/bin/sh
# 동작: 텔넷/FTP 상태와 IP 보기. 켜고 끄는 것은 메뉴의 "텔넷 / FTP" 체크박스만 한다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
IP=$(wifi_ip)
if [ -f /tmp/nx500ex-telnet.pid ] && [ -d /proc/$(cat /tmp/nx500ex-telnet.pid) ]; then S="텔넷/FTP 켜짐"; else S="텔넷/FTP 꺼짐"; fi
popup "$S  IP: ${IP:-WiFi 미연결}" 4
