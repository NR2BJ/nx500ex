# nx500ex 공통 함수. 각 스크립트가 . "$NX500EX/scripts/common.sh" 로 불러 쓴다.
D=${NX500EX:-/mnt/mmc/nx500ex}
PATH=$D/bin:$PATH
PRESETS=$D/presets
# 팝업은 줄바꿈 없이 그려지고 창 너비가 글 길이를 따른다. 화면(720)보다 길면 보이지 않으므로 한 줄은 한글 20자 안팎으로 쓰고,
# 더 필요하면 <br> 로 줄을 나눈다. 팝업은 bin/nxpopup (tools/nxmenu): 불투명 바탕, 줄 수만큼 높이.
# (popup_timeout 은 반투명 바탕이 첫 줄만 덮고 카메라 화면이 겹쳐 보였다. 2026-10-19 실기)
# 팝업은 띄워 두고 바로 돌아온다 (기다리면 keyscan 이 그동안 멈춘다)
popup() { "$D/bin/nxpopup" "$1" "${2:-2}" > /dev/null 2>&1 & }
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
if [ -e "$D/scripts/auto/debug.sh" ]; then
  _T0=$(cut -d' ' -f1 /proc/uptime)
  _NAME=${0##*/}
  trap 'echo "$_NAME start=$_T0 end=$(cut -d" " -f1 /proc/uptime)" >> "$D/log/timing.log"; sync' EXIT
fi

# ---- 촬영 작업 (벌브, 인터벌, HDR, 포커스 스태킹) ----
# 한 번에 하나만 돈다. EV 두 번으로 중단 (EV_EV.sh), 블루투스를 꺼도 중단 (watch.sh).
JOBPID=/tmp/nx500ex-job.pid
job_running() { [ -f $JOBPID ] && [ -d /proc/$(cat $JOBPID) ]; }
job_stop() { job_running && kill $(cat $JOBPID) 2>/dev/null; rm -f $JOBPID; }
jlog() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$D/log/jobs.log"; sync; }
# st 명령을 빠르게 보낸다. stapp 은 st 를 새로 띄우지 않고 메시지 큐로 보낸다 (실패하면 stapp 이 st 로 대신 실행)
sta() { "$D/bin/stapp" "$*" > /dev/null 2>&1; }
# 키 입력은 st 로 보낸다 (응답을 기다려 순서와 누락이 확실하다. stapp 은 벌브 해제가 빠지는 일이 있었다)
key() { st key "$@" > /dev/null 2>&1; }
# 반셔터, 셔터를 누르고 뗀다 (지금 AF, 드라이브 설정을 따른다)
shoot() { key push s1; key push s2; key release s2; key release s1; }
# 반셔터를 누른 채 두기. AF-S 는 그동안 초점을 다시 잡지 않는다 (사람이 반셔터를 누른 채 셔터만 여러 번 누르는 것과 같다)
s1_hold() { key push s1; }
s2_click() { key push s2; key release s2; }
keys_release() { key release s2; key release s1; }
# /proc/uptime 의 1/100 초 단위 시각
now_cs() { read _u _r < /proc/uptime; echo "${_u%.*}${_u#*.}"; }
# 셔터 속도 값 (APPPREF_SHUTTER_SPEED_INDEX). HDR, 벌브 기록용
# 1스톱 = 16, 1초 = 0, 1/30 = 80, 1/2 = 16 (실기 EXIF 로 확인). 1초보다 긴 값은 음수이고 16비트 2의 보수로 저장된다 (BULB = 65440 = -96)
shutter_idx() { _s=$(prefman get 0 0xa340 l 2>/dev/null | sed -n 's/.*value = \([0-9-]*\).*/\1/p'); [ -n "$_s" ] && [ "$_s" -gt 32767 ] && _s=$((_s - 65536)); echo "$_s"; }
shutter_set() { _s=$1; [ "$_s" -lt 0 ] && _s=$((_s + 65536)); prefman set 0 0xa340 l $_s > /dev/null 2>&1; st app mode m > /dev/null 2>&1; }
BULB_IDX=-96
# 무음 셔터: 실제 노출이 약 0.2 초에서 멈춘다. 1/5 까지는 맞고, 1/4 는 약 0.2 스톱 모자라고, 그보다 느리면 모두 약 0.2 초,
# 수 초 이상은 사진이 깨진다 (2026-10-19 RAW 실측, ISO 100 F22 1/10 ~ 2초 14장). 1/5 (셔터 값 37) 보다 느리면 거부
SILENT_MIN_IDX=37
silent_on() { [ -f "$D/scripts/auto/silent.sh" ]; }
iso_now() { st cap capdtm getusr ISO 2>/dev/null | tr -d '\000\r' | sed -n 's/.*is \([A-Z_0-9]*\).*/\1/p'; }
dial() { set -- $(st cap capdtm getusr DIALMODE 2>/dev/null); echo "$3"; }
# 작업 중 화면 끄기 (메뉴 체크박스 = auto/screen_dark.sh 가 있으면).
# 화면 전체를 검은 창(blackout, NX-KS)으로 덮는다. AMOLED 라 검은 화소는 꺼진 것과 같다.
# (st app bb lcd off 는 실기에서 rc=0 이지만 변화 없었음)
lcd_dark() {
  [ -f "$D/scripts/auto/screen_dark.sh" ] || return 0
  "$D/bin/blackout" < /dev/null > /dev/null 2>&1 &
  echo $! > /tmp/nx500ex-blackout.pid; jlog "blackout on"
}
lcd_restore() { [ -f /tmp/nx500ex-blackout.pid ] && kill $(cat /tmp/nx500ex-blackout.pid) 2>/dev/null; rm -f /tmp/nx500ex-blackout.pid; }
# 드라이브: 작업 동안 단사로 바꾸고 끝나면 되돌린다.
# 연사 상태에서 셔터를 누르는 동안(st 한 번에 0.3~1초) 2~4장씩 찍히고, 카메라가 그것을 연사 묶음으로 보여 주고,
# 무음 셔터도 적용되지 않았다 (2026-10-19 실기).
# 드라이브 설정은 prefman 0 0xa5b8 (APPPREF_DRIVE_P, P/A/S/M 공통으로 보임) 에 있다.
# st app drive 와 capdtm setusr 로는 연사 저속(DRIVE_CONTILOW)이 돌아오지 않았다 (2026-10-19 실기). 설정 값을 직접 되돌리고 화면을 갱신한다
drive_now() { st cap capdtm getusr DRIVE 2>/dev/null | tr -d '\000\r' | sed -n 's/.*is \([A-Z_]*\).*/\1/p'; }
drive_save() {
  prefman get 0 0xa5b8 l 2>/dev/null | sed -n 's/.*value = \([0-9]*\).*/\1/p' > /tmp/nx500ex-drive.saved
  jlog "drive was $(drive_now) pref=$(cat /tmp/nx500ex-drive.saved)"
}
drive_single() { st app drive single > /dev/null 2>&1; }
drive_restore() {
  [ -s /tmp/nx500ex-drive.saved ] || return 0
  _d=$(cat /tmp/nx500ex-drive.saved); rm -f /tmp/nx500ex-drive.saved
  # 원래 단사였으면 되돌릴 것이 없다 (화면 갱신은 AF 위치를 가운데로 되돌리는 것으로 보여 필요할 때만)
  [ "$_d" = 0 ] && return 0
  prefman set 0 0xa5b8 l "$_d" > /dev/null 2>&1
  reapply_mode
  jlog "drive restore pref=$_d -> $(drive_now)"
}
# 메모리 카드의 사진 파일 수 (첫 장이 실제로 찍혔는지 확인용)
dcim_count() { find /mnt/mmc/DCIM -type f 2>/dev/null | wc -l; }
# 새 파일이 생길 때까지 최대 $2 초 기다린다 ($1 = 기다리기 전 파일 수)
wait_file() {
  _end=$(( $(now_cs) + ${2:-8} * 100 ))
  while [ $(now_cs) -lt $_end ]; do
    sleep 0.3
    [ "$(dcim_count)" -gt "$1" ] && return 0
  done
  return 1
}
# 첫 장: 반셔터를 누른 채(s1_hold 뒤) 셔터를 누르고, 새 파일이 생기는지 최대 $1 초 기다린다.
# AF-S 는 초점을 못 잡으면 셔터가 눌리지 않아 파일이 생기지 않는다.
# 렌즈 AF/MF 스위치가 AF 면 카메라 설정으로 MF 전환이 막혀 있어서(2026-10-19 실기) MF 전환 대신 반셔터를 계속 누르고 있는다.
first_shot() {
  _n=$(dcim_count); s2_click
  wait_file $_n "${1:-8}"
}
# 숫자 설정은 메뉴(nxmenu 의 num 항목)가 conf/<이름> 에 쓴다. 스크립트는 읽기만 한다
# conf_get 이름 기본값 [최소 최대]
conf_get() {
  _c=$(cat "$D/conf/$1" 2>/dev/null)
  case "$_c" in ''|*[!0-9]*) _c=$2 ;; esac
  [ -n "$3" ] && { [ "$_c" -lt "$3" ] || [ "$_c" -gt "$4" ]; } && _c=$2
  echo "$_c"
}
conf_set() { mkdir -p "$D/conf"; echo "$2" > "$D/conf/$1"; sync; }
