#!/bin/sh
# 웹 원격 (bin/nxweb, tools/nxweb) 시작. 메뉴 체크박스 "웹 원격" (켜 두면 전원 켤 때마다 auto 에서 시작).
# 브라우저에서 http://<카메라 IP>/ : 라이브 뷰, 키 조작, 사진 보기, 동작 실행. 인증 없음 (텔넷과 같은 수준).
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
sh "$D/scripts/off_web.sh"
"$D/bin/busybox" nice -n 10 "$D/bin/nxweb" -p 80 -r "$D/www" -s "$D/scripts" >> "$D/log/web.log" 2>&1 < /dev/null &
echo $! > /tmp/nx500ex-web.pid
sleep 1
if [ -d /proc/$(cat /tmp/nx500ex-web.pid) ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') web start ip=$(wifi_ip) pid=$(cat /tmp/nx500ex-web.pid)" >> "$D/log/boot.log"; sync
  case "$0" in */auto/*) ;; *) popup "웹 원격 켜짐<br>http://$(wifi_ip)/" 3 ;; esac
else
  echo "$(date '+%Y-%m-%d %H:%M:%S') web failed: $(tail -n 2 "$D/log/web.log" | tr '\n' ' ')" >> "$D/log/boot.log"; sync
  popup "웹 원격 시작 실패<br>log/web.log 확인" 4
fi
exit 0
