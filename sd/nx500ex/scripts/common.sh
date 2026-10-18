# nx500ex 공통 함수. 각 스크립트가 . "$NX500EX/scripts/common.sh" 로 불러 쓴다.
D=${NX500EX:-/mnt/mmc/nx500ex}
PATH=$D/bin:$PATH
PRESETS=$D/presets
# 팝업은 띄워 두고 바로 돌아온다 (기다리면 keyscan 이 그동안 멈춘다)
popup() { "$D/bin/popup_timeout" " $1 " "${2:-2}" > /dev/null 2>&1 & }
# 확인 창. NX-KS 의 popup_ok 빌드는 첫 버튼(확인)이 255, 두 번째(취소)가 0 을 돌려준다 (상류 소스와 반대, 디스어셈블로 확인)
confirm() { "$D/bin/popup_ok" "$1" "${2:-확인}" "${3:-취소}" > /dev/null 2>&1; [ $? -eq 255 ]; }
# 프로필을 불러온 뒤 현재 다이얼 모드를 다시 적용해 화면에 반영한다 (NX-KS 방식)
reapply_mode() {
  set -- $(st cap capdtm getusr DIALMODE)
  case "$3" in
    DIALMODE_SMARTAUTO) st app mode auto ;;
    DIALMODE_APERTURE) st app mode a ;;
    DIALMODE_SHUTTERSPEED) st app mode s ;;
    DIALMODE_MANUAL) st app mode m ;;
    DIALMODE_SMARTPRO) st app mode smart-pro ;;
    *) st app mode p ;;
  esac > /dev/null 2>&1
}
# WiFi IP (연결 전이면 빈 값)
wifi_ip() { ip addr ls mlan0 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p'; }
# 터치: prefman 0xa690 (NX500). 1 = 켜짐
touch_get() { set -- $(prefman get 0 0x0000a690 b 2>/dev/null); echo "$6"; }
touch_set() { prefman set 0 0x0000a690 b "$1" > /dev/null 2>&1; }

# 진단 기록이 켜져 있으면 각 스크립트의 시작/끝 시각(uptime)을 log/timing.log 에 남긴다
if [ -e "$D/debug" ]; then
  _T0=$(cut -d' ' -f1 /proc/uptime)
  _NAME=${0##*/}
  trap 'echo "$_NAME start=$_T0 end=$(cut -d" " -f1 /proc/uptime)" >> "$D/log/timing.log"; sync' EXIT
fi
