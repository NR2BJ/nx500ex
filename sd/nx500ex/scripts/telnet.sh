#!/bin/sh
# 텔넷(23), FTP(21, SD 카드 루트) 시작. 인증 없음. 본인 기기만 있는 네트워크(폰 핫스팟 등)에서만 쓸 것.
# 서버는 WiFi 연결과 상관없이 먼저 떠 있고, WiFi 가 연결되면 그때부터 접속된다.
# 메뉴에서 켤 때만 팝업을 띄운다 (전원 켤 때 자동 실행에서는 조용히).
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
sh "$D/scripts/off_telnet.sh"
"$D/bin/telnetd" > /dev/null 2>&1 &
echo $! > /tmp/nx500ex-telnet.pid
"$D/bin/busybox" tcpsvd -u root -E 0.0.0.0 21 "$D/bin/busybox" ftpd -w /opt/storage/sdcard > /dev/null 2>&1 &
echo $! > /tmp/nx500ex-ftp.pid
IP=$(wifi_ip)
echo "$(date '+%Y-%m-%d %H:%M:%S') telnet start ip=${IP:-none} telnetd=$(cat /tmp/nx500ex-telnet.pid) ftp=$(cat /tmp/nx500ex-ftp.pid)" >> "$D/log/boot.log"; sync
if [ -n "$NX500EX_MENU" ]; then
  if [ -n "$IP" ]; then popup "텔넷/FTP 켜짐: $IP" 4; else popup "텔넷/FTP 켜짐. WiFi 연결 뒤 EV+WiFi 로 주소 확인" 4; fi
fi
exit 0
