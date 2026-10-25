#!/bin/sh
# 팝업 표시 시험 (텔넷에서 실행): WiFi 켜고 끄는 앞뒤로 팝업이 보이는지 번호로 확인한다. 결과는 log/popup_test.txt
#   sh /mnt/mmc/nx500ex/scripts/popup_test.sh     (촬영 화면에서, WiFi 는 켜져 있든 꺼져 있든)
# 텔넷 셸에는 화면 환경 변수가 없으므로 boot.sh 와 같은 변수를 맞춘다.
D=${NX500EX:-/mnt/mmc/nx500ex}
export HIB=a EVAS_FONT_DPI=72 EINA_LOG_LEVELS=ecore_x:4,evas_main:1 GTK_IM_MODULE_FILE=/opt/etc/gtk-2.0/gtk.immodules
export LD_LIBRARY_PATH=:/usr/lib:/usr/lib/driver ECORE_IMF_MODULE=isf ECORE_INPUT_TIMEOUT_FIX=0 EINA_LOG_DLOG_ENABLE=1
export XMODIFIERS=@im=SCIM EINA_LOG_LEVEL=1 SCIM_MODULE_PATH=/opt/apps/scim/lib/scim-1.0 ECORE_INPUT_FIX=1 XDG_CACHE_HOME=/tmp/.cache
export EVAS_GL_NO_BLACKLIST=1 DISPLAY=:0 GTK_IM_MODULE=scim EINA_LOG_SYSLOG_ENABLE=0 ELM_PROFILE=mobile MULTISENSE_SND_PLAYER=tizen_snd_player
export HOME=/root USER=root LOGNAME=root NX500EX=$D PATH=$D/bin:$PATH
OUT=$D/log/popup_test.txt
# WiFi 를 껐다 켜면 텔넷이 끊기므로, 터미널과 떼어서 뒤에서 돈다
if [ "$NXBG" != 1 ]; then
  echo "뒤에서 시작합니다 (약 25 초). 텔넷이 끊기면 메뉴에서 WiFi 켜기를 다시 켠 뒤 log/popup_test.txt 를 보세요"
  if $D/bin/busybox setsid true 2>/dev/null; then NXBG=1 $D/bin/busybox setsid sh "$0" < /dev/null > /dev/null 2>&1 &
  else NXBG=1 sh "$0" < /dev/null > /dev/null 2>&1 & fi
  exit 0
fi
log() { echo "$(date '+%H:%M:%S') $*" | tee -a $OUT; }
pop() { log "팝업 $1"; $D/bin/nxpopup "시험 $1" 3; log "  nxpopup 끝 rc=$?"; }
DB="dbus-send --system --print-reply"
echo "### popup test $(date '+%Y-%m-%d %H:%M:%S')" >> $OUT
pop "1 (그냥)"; sleep 2
log "WiFi 끄기 (RemoveDriver)"; $DB --dest=net.netconfig /net/netconfig/wifi net.netconfig.wifi.RemoveDriver > /dev/null 2>&1
pop "2 (끈 직후)"; sleep 5
pop "3 (끈 뒤 5초)"; sleep 2
log "WiFi 켜기 (LoadDriver)"; $DB --dest=net.netconfig /net/netconfig/wifi net.netconfig.wifi.LoadDriver boolean:false > /dev/null 2>&1
pop "4 (켠 직후)"; sleep 5
pop "5 (켠 뒤 5초)"; sleep 2
log "뒤에서 띄우기 (스크립트가 끝난 뒤 뜨는 팝업)"; ( sleep 2; $D/bin/nxpopup "시험 6 (뒤에서)" 3 ) < /dev/null > /dev/null 2>&1 &
log "끝. 본 번호를 알려 주세요. WiFi 는 켜진 채 (연결은 안 된 상태) 로 남습니다: 메뉴에서 WiFi 켜기를 다시 켜면 붙습니다"
sync
