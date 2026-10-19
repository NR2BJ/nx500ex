#!/bin/sh
# 필름 레시피 (FilmLab): 화면 마법사 사용자 1 에 레시피 값을 쓰고 화면 마법사 목록을 열어 반영한다.
#   film.sh <레시피 이름>   film/recipes.txt 의 값으로 사용자 1 을 바꾸고 사용자 1 을 고른다
#   film.sh off             화면 마법사를 해제로
#   film.sh restore         사용자 1 을 처음 바꾸기 전 값으로 되돌린다 (conf/pw_custom1.bak)
# 레시피 값과 prefman 위치는 NXWA (WApaperplane/NXWA-nx500_modding, AGPL-3.0) 의 FilmLab 에서 가져왔다.
# prefman 에 값을 쓰는 것만으로는 화면과 사진에 반영되지 않고, 카메라 앱이 화면 마법사 목록을 열 때 반영한다 (2026-10-19 실기).
# 그래서 st key 로 Fn -> 화면 마법사 칸 터치 -> OK (목록) -> 오른쪽 n 번 -> OK 를 누른다.
# 목록 커서는 지금 종류(APPPREF_EFFECT_PW_TYPE: 해제 0, 표준 1 ... 클래식 9, 사용자 1~3 10~12)에 있고 끝에서 처음으로 돈다.
# 값을 쓴 직후에는 카메라 앱이 바빠 Fn 이 먹히지 않아(실기: 방향키가 AF 위치를 옮김) 2초 기다린다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
PW_TYPE=0xa3d4
PW_N=13
PW_TOUCH_X=300   # Fn 패널의 화면 마법사 칸 (P/A/S/M, 실기 M 모드)
PW_TOUCH_Y=300
BAK="$D/conf/pw_custom1.bak"
LOCK=/tmp/nx500ex-film.pid

pget() { prefman get 0 "$1" l 2>/dev/null | tr -d '\000\r' | sed -n 's/.*value = \([-0-9]*\).*/\1/p'; }
pset() { prefman set 0 "$1" l "$2" > /dev/null 2>&1; }
# 사용자 1 의 값 위치: 0xa3ec (STANDARD_R_COLOR) + 항목 x 52 + 사용자 1 (9번째) x 4. 항목 R G B 색조 채도 선명도 대비 = 0..6
c1() { printf 0x%05x $((0xa3ec + $1 * 52 + 9 * 4)); }
c1_get() { echo "$(pget $(c1 0)) $(pget $(c1 1)) $(pget $(c1 2)) $(pget $(c1 3)) $(pget $(c1 4)) $(pget $(c1 5)) $(pget $(c1 6))"; }
c1_set() { _i=0; for _v in "$@"; do pset $(c1 $_i) "$_v"; _i=$((_i + 1)); done; }
# 실제로 반영된 값 (촬영 쪽 변수): R G B 색조 채도 선명도 대비. 게인 = 상위 16비트 / 20.32, 나머지 = 10 + (부호 있는 상위 16비트 - 15) / 16
isp_get() {
  _r=; _g=; _b=; _h=; _s=; _p=; _c=
  for _l in $(st cap capdtm varlist 2>/dev/null | tr -d '\000 ' | grep -a 'VARIABLE_PW' | cut -d'|' -f2,4); do
    _n=${_l%%|*}; _x=${_l#*|}
    case "$_x" in 0x*) ;; *) continue ;; esac
    _v=$(( _x >> 16 ))
    case "$_n" in
      *COLOR_*) _v=$(( _v * 100 / 2032 )) ;;
      *) [ $_v -ge 32768 ] && _v=$((_v - 65536)); _v=$(( 10 + (_v - 15) / 16 )) ;;
    esac
    case "$_n" in
      *COLOR_R) _r=$_v ;; *COLOR_G) _g=$_v ;; *COLOR_B) _b=$_v ;; *PWHUE) _h=$_v ;;
      *SATURATION) _s=$_v ;; *SHARPNESS) _p=$_v ;; *CONTRAST) _c=$_v ;;
    esac
  done
  echo $_r $_g $_b $_h $_s $_p $_c
}
# 반영 확인: 게인은 2 이내, 나머지는 같아야 한다
isp_match() {
  set -- $(isp_get) $*
  [ $# -eq 14 ] || return 1
  for _k in 1 2 3; do eval "_a=\$$_k _b=\${$((_k + 7))}"; _d=$((_a - _b)); [ $_d -lt 0 ] && _d=$((-_d)); [ $_d -le 2 ] || return 1; done
  for _k in 4 5 6 7; do eval "_a=\$$_k _b=\${$((_k + 7))}"; [ "$_a" = "$_b" ] || return 1; done
}
# 화면 마법사 목록을 열고 종류 $1 을 고른다
pw_select() {
  _cur=$(pget $PW_TYPE)
  case "$_cur" in ''|*[!0-9]*) return 1 ;; esac
  _n=$(( ($1 - _cur + PW_N) % PW_N ))
  _t=$(touch_get)
  [ "$_t" = 0 ] && { touch_set 1; reapply_mode; sleep 1; }
  key click fn; sleep 1
  st key touch click $PW_TOUCH_X $PW_TOUCH_Y > /dev/null 2>&1; sleep 0.5
  key click ok; sleep 1
  while [ $_n -gt 0 ]; do key click right; sleep 0.3; _n=$((_n - 1)); done
  key click ok; sleep 1
  [ "$_t" = 0 ] && { touch_set 0; reapply_mode; }
  jlog "film select $1 (was $_cur) -> type $(pget $PW_TYPE)"
  [ "$(pget $PW_TYPE)" = "$1" ]
}

[ -f $LOCK ] && [ -d /proc/$(cat $LOCK) ] && exit 0
echo $$ > $LOCK
trap 'rm -f $LOCK' EXIT
job_running && { popup "촬영 작업 중" 2; exit 0; }
case "$(dial)" in
  DIALMODE_PROGRAM|DIALMODE_APERTURE|DIALMODE_SHUTTERSPEED|DIALMODE_MANUAL) ;;
  *) popup "P, A, S, M 모드에서 사용" 2; exit 0 ;;
esac
sleep 1   # 메뉴가 닫힐 때까지

case "$1" in
  off)
    if pw_select 0; then popup "필름 레시피 끔" 2; conf_set film_last ""
    else popup "화면 마법사를 바꾸지 못함<br>다시 해 보세요" 3; fi
    ;;
  restore)
    [ -s "$BAK" ] || { popup "바꾼 적 없음" 2; exit 0; }
    c1_set $(cat "$BAK")
    jlog "film restore custom1 $(cat "$BAK")"
    rm -f "$BAK"; conf_set film_last ""
    if [ "$(pget $PW_TYPE)" = 10 ]; then sleep 2; pw_select 10; fi
    popup "사용자 1 원래대로" 2
    ;;
  *)
    L=$(grep "^$1|" "$D/scripts/film/recipes.txt" 2>/dev/null | head -1)
    [ -n "$L" ] || { popup "레시피 없음: $1" 2; exit 0; }
    IFS='|'; set -- $L; unset IFS
    NAME=$3; shift 3
    VALS="$*"
    [ -s "$BAK" ] || { mkdir -p "$D/conf"; c1_get > "$BAK"; sync; jlog "film backup custom1 $(cat "$BAK")"; }
    c1_set $VALS
    jlog "film $NAME custom1 <- $VALS"
    sleep 2
    pw_select 10
    sleep 0.5
    if isp_match $VALS; then
      conf_set film_last "$NAME"
      popup "필름: $NAME" 2
    else
      jlog "film not applied: isp $(isp_get)"
      popup "반영 확인 안 됨<br>다시 해 보세요" 3
    fi
    ;;
esac
