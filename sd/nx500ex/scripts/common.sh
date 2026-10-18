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

# ---- 촬영 작업 (벌브, 인터벌, HDR, 포커스 스태킹) ----
# 한 번에 하나만 돈다. EV 두 번으로 중단 (EV_EV.sh), 블루투스를 꺼도 중단 (watch.sh).
JOBPID=/tmp/nx500ex-job.pid
job_running() { [ -f $JOBPID ] && [ -d /proc/$(cat $JOBPID) ]; }
job_stop() { job_running && kill $(cat $JOBPID) 2>/dev/null; rm -f $JOBPID; }
jlog() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$D/log/jobs.log"; sync; }
# st 명령을 빠르게 보낸다. stapp 은 st 를 새로 띄우지 않고 메시지 큐로 보낸다 (실패하면 stapp 이 st 로 대신 실행)
sta() { "$D/bin/stapp" "$*" > /dev/null 2>&1; }
# 반셔터, 셔터를 누르고 뗀다 (지금 AF, 드라이브 설정을 따른다)
shoot() { sta key push s1; sleep 0.3; sta key push s2; sleep 0.1; sta key release s2; sta key release s1; }
# 셔터 속도 값 (APPPREF_SHUTTER_SPEED_INDEX). HDR, 벌브 기록용
shutter_idx() { prefman get 0 0xa340 l 2>/dev/null | sed -n 's/.*value = \([0-9-]*\).*/\1/p'; }
dial() { set -- $(st cap capdtm getusr DIALMODE 2>/dev/null); echo "$3"; }
# 작업 중 화면 끄기 (메뉴 체크박스 = auto/screen_dark.sh 가 있으면)
lcd_dark() { [ -f "$D/scripts/auto/screen_dark.sh" ] || return 0; st app bb lcd off > /dev/null 2>&1; jlog "lcd off rc=$?"; }
lcd_restore() { st app bb lcd on > /dev/null 2>&1; rm -f /tmp/nx500ex-lcd-video; }
# AF 모드 저장, MF 로 전환, 복원 (focus_stack 바이너리와 같은 방식)
af_save() { st cap capdtm getusr AFMODE 2>/dev/null | sed -n 's/.*(\(0x[0-9a-fA-F]*\)).*/\1/p' > /tmp/nx500ex-af.saved; }
af_manual() { st app nx capture af-mode manual > /dev/null 2>&1; }
af_restore() { [ -s /tmp/nx500ex-af.saved ] && st cap capdtm setusr AFMODE $(cat /tmp/nx500ex-af.saved) > /dev/null 2>&1; rm -f /tmp/nx500ex-af.saved; }
# 숫자 입력. ask "질문" 기본값 최소 최대 → 값 출력, 취소나 잘못된 값이면 실패
ask() {
  _v=$("$D/bin/popup_entry" "$1" 확인 취소 "$2" number 2>/dev/null) || return 1
  case "$_v" in ''|*[!0-9]*) popup "숫자가 아님" 2; return 1 ;; esac
  if [ "$_v" -lt "$3" ] || [ "$_v" -gt "$4" ]; then popup "$3~$4 사이로 입력" 2; return 1; fi
  echo "$_v"
}
conf_get() { _c=$(cat "$D/conf/$1" 2>/dev/null); echo "${_c:-$2}"; }
conf_set() { mkdir -p "$D/conf"; echo "$2" > "$D/conf/$1"; sync; }
