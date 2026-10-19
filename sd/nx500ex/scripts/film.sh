#!/bin/sh
# 필름 레시피 (FilmLab): 화면 마법사 사용자 1 에 레시피 값을 쓰고 화면 마법사 목록을 열어 반영한다.
#   film.sh <레시피 이름>   film/recipes.txt 의 값으로 사용자 1 을 바꾸고 사용자 1 을 고른다. 레시피에 색온도가 있으면 WB 도 그 K 로
#   film.sh off             화면 마법사를 해제로, WB 를 원래대로
#   film.sh restore         사용자 1 을 처음 바꾸기 전 값으로 (conf/pw_custom1.bak), WB 를 원래대로
# WB 는 prefman 에 써도 앱이 자기 값으로 덮어써서(실기) 화면 마법사처럼 키 주입으로 고른다:
# Fn -> WB 칸 -> 목록(자동 0 ... 색온도 10, 11칸, 커서 = 지금 촬영 쪽 WB) -> 색온도까지 오른쪽 -> 위(세부) -> 슬라이더 터치 -> 좌우로 100K 단위 맞춤 -> OK.
# 처음 WB 를 바꿀 때 원래 WB (종류, 색온도면 K) 를 conf/film_wb.bak 에 남기고, 색온도 없는 레시피, off, restore 가 되돌린다.
# scripts/auto/film_nowb.sh 가 있으면 (메뉴 체크박스 "화이트 밸런스 유지") 레시피가 WB 를 바꾸지 않는다.
# prefman 위치와 반영 확인 방법(varlist)은 NXWA (WApaperplane/NXWA-nx500_modding, AGPL-3.0) 의 FilmLab 에서 가져왔다.
# 레시피 값은 실제 필름 특성 조사로 nx500ex 가 정했다 (docs/research/2026-10-19-film-stock-profiles.md).
# prefman 에 값을 쓰는 것만으로는 화면과 사진에 반영되지 않고, 카메라 앱이 화면 마법사 목록을 열 때 반영한다 (2026-10-19 실기).
# 그래서 st key 로 Fn -> 화면 마법사 칸 터치 -> OK (목록) -> 오른쪽 n 번 -> OK 를 누른다.
# 목록 커서는 지금 종류(해제 0, 표준 1 ... 클래식 9, 사용자 1~3 10~12)에 있고 끝에서 처음으로 돈다.
# 값을 쓴 직후에는 카메라 앱이 바빠 Fn 이 먹히지 않아(실기: 방향키가 AF 위치를 옮김) 2초 기다린다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
PW_TYPE=0xa3d4
PW_N=13
PW_TOUCH_X=300   # Fn 패널의 화면 마법사 칸 (P/A/S/M, 실기 M 모드)
PW_TOUCH_Y=300
WB_N=11
WB_TOUCH_X=150   # Fn 패널의 WB 칸
WB_TOUCH_Y=330
# 색온도 세부 화면의 슬라이더 (실기 보정: x 208 = 2500K, x 515 = 10000K, 1픽셀 약 24.5K, y 380)
K_X0=208
K_Y=380
BAK="$D/conf/pw_custom1.bak"
WBBAK="$D/conf/film_wb.bak"
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
# 화면 마법사 목록에서 지금 위치 (해제 0, 표준 1 ... 클래식 9, 사용자 1~3 10~12).
# 목록에서 커서만 옮기면 촬영 쪽 값은 바로 바뀌고 prefman 은 OK 로 확정할 때 저장된다(WB 실기). 지금 적용된 촬영 쪽 값으로 읽고,
# 해제와 표준(둘 다 PW_STANDARD)만 prefman 으로 가린다
pw_cur() {
  _e=$(st cap capdtm getusr PW 2>/dev/null | tr -d '\000\r' | sed -n 's/.*(0x1400\([0-9a-f][0-9a-f]\)).*/\1/p')
  [ -n "$_e" ] || return 1
  _e=$((0x$_e))
  case $_e in
    0) _p=$(pget $PW_TYPE); [ "$_p" = 0 ] && echo 0 || echo 1 ;;
    12) echo 12 ;;
    *) echo $((_e + 1)) ;;
  esac
}
# Fn 패널을 열고 ($1, $2) 칸을 터치한 뒤 OK (그 칸의 목록이 열린다)
fn_open() { key click fn; sleep 1; st key touch click $1 $2 > /dev/null 2>&1; sleep 0.5; key click ok; sleep 1; }
right_n() { _k=$1; while [ $_k -gt 0 ]; do key click right; sleep 0.3; _k=$((_k - 1)); done; }
left_n() { _k=$1; while [ $_k -gt 0 ]; do key click left; sleep 0.3; _k=$((_k - 1)); done; }
# 목록에서 $1 -> $2 로 (전체 $3 칸). 오른쪽은 끝에서 처음으로 돈다(실기). 왼쪽은 돌지 않는 경우에만 (돎은 확인 안 함)
move_to() { _r=$(( ($2 - $1 + $3) % $3 )); if [ $2 -lt $1 ] && [ $(($1 - $2)) -lt $_r ]; then left_n $(($1 - $2)); else right_n $_r; fi; }
# 조건이 맞을 때까지 최대 2초 기다린다 (0.2초 간격)
wait_for() { _w=0; while [ $_w -lt 10 ]; do eval "$1" && return 0; sleep 0.2; _w=$((_w + 1)); done; return 1; }
# 화면 마법사 종류 $1 을 고른다
pw_select() {
  _cur=$(pw_cur)
  case "$_cur" in ''|*[!0-9]*) return 1 ;; esac
  fn_open $PW_TOUCH_X $PW_TOUCH_Y
  move_to $_cur $1 $PW_N
  key click ok
  _tgt=$1; wait_for '[ "$(pw_cur)" = "$_tgt" ]'; _ok=$?
  jlog "film select $1 (was $_cur) -> $(pw_cur)"
  return $_ok
}
# 지금 WB (촬영 쪽: 자동 0 ... 색온도 10) 와 반영된 색온도
wb_cur() { _w=$(st cap capdtm getusr WB 2>/dev/null | tr -d '\000\r' | sed -n 's/.*(0x6000\([0-9a-f]\)).*/\1/p'); [ -n "$_w" ] && echo $((0x$_w)); }
wb_k() { st cap capdtm varlist 2>/dev/null | tr -d '\000 ' | grep -a 'WBCOLORTEMP' | cut -d'|' -f5; }
# WB 종류 $1 을 고른다. 색온도(10)면 $2 = K
wb_select() {
  _cur=$(wb_cur)
  case "$_cur" in ''|*[!0-9]*) return 1 ;; esac
  fn_open $WB_TOUCH_X $WB_TOUCH_Y
  move_to $_cur $1 $WB_N
  if [ "$1" = 10 ] && [ -n "$2" ]; then
    key click up; sleep 1
    st key touch click $(( K_X0 + ($2 - 2500) * 10 / 245 )) $K_Y > /dev/null 2>&1; sleep 0.7
    _try=0
    while [ $_try -lt 3 ]; do
      _kk=$(wb_k); [ -n "$_kk" ] || break
      _d=$(( ($2 - _kk) / 100 ))
      [ $_d -eq 0 ] && break
      if [ $_d -gt 0 ]; then right_n $_d; else left_n $((-_d)); fi
      sleep 0.3; _try=$((_try + 1))
    done
  fi
  key click ok
  _tgt=$1; wait_for '[ "$(wb_cur)" = "$_tgt" ]'
  jlog "film wb $1 $2 (was $_cur) -> $(wb_cur) $(wb_k)K"
  [ "$(wb_cur)" = "$1" ] && { [ "$1" != 10 ] || [ -z "$2" ] || [ "$(wb_k)" = "$2" ]; }
}
# 원래 WB 로 (백업이 있을 때)
wb_restore() {
  [ -s "$WBBAK" ] || return 0
  set -- $(cat "$WBBAK")
  if [ "$(wb_cur)" = "$1" ] && { [ "$1" != 10 ] || [ "$(wb_k)" = "$2" ]; }; then rm -f "$WBBAK"; return 0; fi
  sleep 0.5
  if [ "$1" = 10 ]; then wb_select 10 "$2"; else wb_select "$1"; fi && rm -f "$WBBAK"
}
# 레시피의 색온도 $1 로 (처음이면 원래 WB 를 백업). 비어 있으면 원래대로
wb_apply() {
  [ -f "$D/scripts/auto/film_nowb.sh" ] && return 0
  [ -n "$1" ] || { wb_restore; return; }
  [ -s "$WBBAK" ] || { echo "$(wb_cur) $(wb_k)" > "$WBBAK"; sync; jlog "film backup wb $(cat "$WBBAK")"; }
  [ "$(wb_cur)" = 10 ] && [ "$(wb_k)" = "$1" ] && return 0   # 이미 그 색온도
  sleep 0.5
  wb_select 10 "$1"
}

[ -f $LOCK ] && [ -d /proc/$(cat $LOCK) ] && exit 0
echo $$ > $LOCK
trap 'rm -f $LOCK' EXIT
job_running && { popup "촬영 작업 중" 2; exit 0; }
case "$(dial)" in
  DIALMODE_PROGRAM|DIALMODE_APERTURE|DIALMODE_SHUTTERSPEED|DIALMODE_MANUAL) ;;
  *) popup "P, A, S, M 모드에서 사용" 2; exit 0 ;;
esac
T_START=$(now_cs)
# 터치가 꺼져 있으면 키 주입 동안만 켠다
T0=$(touch_get)
[ "$T0" = 0 ] && { touch_set 1; reapply_mode; sleep 1; }
trap 'rm -f $LOCK; [ "$T0" = 0 ] && { touch_set 0; reapply_mode; }' EXIT

case "$1" in
  off)
    sleep 1   # 메뉴가 닫힐 때까지
    pw_select 0; R=$?
    wb_restore
    if [ $R = 0 ]; then popup "필름 레시피 끔" 2; conf_set film_last ""
    else popup "화면 마법사를 바꾸지 못함<br>다시 해 보세요" 3; fi
    ;;
  restore)
    [ -s "$BAK" ] || { popup "바꾼 적 없음" 2; exit 0; }
    sleep 1   # 메뉴가 닫힐 때까지
    c1_set $(cat "$BAK")
    jlog "film restore custom1 $(cat "$BAK")"
    rm -f "$BAK"; conf_set film_last ""
    if [ "$(pw_cur)" = 10 ]; then sleep 2; pw_select 10; fi
    wb_restore
    popup "사용자 1 원래대로" 2
    ;;
  *)
    L=$(grep "^$1|" "$D/scripts/film/recipes.txt" 2>/dev/null | head -1)
    [ -n "$L" ] || { popup "레시피 없음: $1" 2; exit 0; }
    IFS='|'; set -- $L; unset IFS
    NAME=$3; WB=${11}
    VALS="$4 $5 $6 $7 $8 $9 ${10}"
    [ -s "$BAK" ] || { mkdir -p "$D/conf"; c1_get > "$BAK"; sync; jlog "film backup custom1 $(cat "$BAK")"; }
    c1_set $VALS
    jlog "film $NAME custom1 <- $VALS"
    sleep 2   # 메뉴가 닫히고, 값을 쓴 직후 앱이 바쁜 동안 (바로 키를 보내면 Fn 이 먹히지 않았다)
    pw_select 10
    wait_for 'isp_match $VALS'; R=$?
    [ $R = 0 ] || jlog "film not applied: isp $(isp_get)"
    wb_apply "$WB"; RW=$?
    jlog "film $NAME done in $(( ($(now_cs) - T_START) / 10 ))00ms"
    if [ $R = 0 ] && [ $RW = 0 ]; then
      conf_set film_last "$NAME"
      if [ -n "$WB" ] && [ ! -f "$D/scripts/auto/film_nowb.sh" ]; then popup "필름: $NAME<br>WB ${WB}K" 2; else popup "필름: $NAME" 2; fi
    elif [ $R = 0 ]; then
      popup "필름: $NAME<br>WB 를 바꾸지 못함" 3
    else
      popup "반영 확인 안 됨<br>다시 해 보세요" 3
    fi
    ;;
esac
