#!/bin/sh
# 텔넷(23), FTP(21, SD 카드 루트) 시작. 인증 없음. 본인 기기만 있는 네트워크(폰 핫스팟 등)에서만 쓸 것.
# WiFi 가 연결돼 있으면 IP 를 띄운다. 연결 전이면 조용히 서버만 띄운다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
sh "$D/scripts/off_telnet.sh"
"$D/bin/telnetd" > /dev/null 2>&1 &
echo $! > /tmp/nx500ex-telnet.pid
"$D/bin/busybox" tcpsvd -u root -E 0.0.0.0 21 "$D/bin/busybox" ftpd -w /opt/storage/sdcard > /dev/null 2>&1 &
echo $! > /tmp/nx500ex-ftp.pid
IP=$(ip addr ls mlan0 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p')
[ -n "$IP" ] && popup "텔넷/FTP: $IP" 4
exit 0
