#!/bin/sh
# 시각 맞추기: 인터넷 시계 (NTP) 로 카메라 시계를 맞추고 RTC 에 써 둔다 (전원을 꺼도 유지). 사진 EXIF 시각이 정확해진다.
#   time.sh         메뉴 버튼이나 키 동작: 결과 팝업
#   time.sh quiet   WiFi 가 붙을 때 wifi.sh 가 뒤에서 부름: 2 초 이상 틀렸을 때만 팝업
# 서버: conf/ntp.txt 에 한 줄 적으면 그것, 없으면 kr.pool.ntp.org. busybox ntpd -n -q (한 번 맞추고 끝), busybox hwclock -w (RTC).
# 실기 (2026-10-26): 카메라 시계가 27.6 초 빨랐고 4 번 응답 뒤 맞춰짐 (약 10 초). 카메라 시간대는 /etc/localtime (KST) 로 표시되므로 UTC 로 맞추면 된다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
B="$D/bin/busybox"
SERVER=$(head -n 1 "$D/conf/ntp.txt" 2>/dev/null | tr -d ' \r'); [ -n "$SERVER" ] || SERVER=kr.pool.ntp.org
wl() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$D/log/wifi.log"; sync; }
[ -n "$(wifi_ip)" ] || { [ "$1" = quiet ] || popup "WiFi 가 안 붙어 있음" 2; exit 1; }
OUT=$("$B" timeout -t 30 "$B" ntpd -n -q -d -p "$SERVER" 2>&1); RC=$?
# 크게 틀렸으면 "setting time to ... (offset +N s)" 로 맞추고, 조금 틀렸으면 (0.13 초 미만) 그 줄 없이 서서히 맞추고 끝난다.
# 부호는 + 또는 - (2026-10-26 실기: 1 년 틀리게 했을 때 +31531628 초를 못 읽어 실패로 적은 적 있음)
OFF=$(echo "$OUT" | sed -n 's/.*setting time to .*(offset \([-+]*[0-9.]*\)s).*/\1/p' | tail -n 1)
[ -n "$OFF" ] || OFF=$(echo "$OUT" | sed -n 's/.*reply from .* offset:\([-+]*[0-9.]*\) .*/\1/p' | tail -n 1)
if [ -z "$OFF" ] || [ "$RC" != 0 ]; then
  wl "time: failed rc=$RC ($SERVER): $(echo "$OUT" | tail -n 1)"
  [ "$1" = quiet ] || popup "시각 맞추기 실패<br>$SERVER 에 닿지 않음" 3
  exit 1
fi
OFF=${OFF#+}
"$B" hwclock -w 2>/dev/null
wl "time: set, offset ${OFF}s via $SERVER, rtc written"
# 소수 둘째 자리까지, 부호 유지
SHOW=$(printf '%s' "$OFF" | sed 's/^\(-*[0-9]*\.[0-9][0-9]\).*/\1/')
case "$SHOW" in -*) ;; *) SHOW="+$SHOW" ;; esac
BIG=$(echo "$OFF" | awk '{ v = $1 < 0 ? -$1 : $1; print (v >= 2) ? 1 : 0 }')
if [ "$1" != quiet ] || [ "$BIG" = 1 ]; then popup "시각 맞춤: ${SHOW}초 고침<br>$(date '+%Y-%m-%d %H:%M:%S')" 3; fi
exit 0
