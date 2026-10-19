#!/bin/sh
# 필름 레시피 (FilmLab): 화면 마법사 사용자 1 과 화이트 밸런스를 레시피 값으로 바꾼다.
#   film.sh <레시피 이름>   film/recipes.txt 의 값으로 사용자 1 을 바꾸고 사용자 1 을 고른다. 레시피에 색온도가 있으면 WB 도 그 K 로
#   film.sh off             화면 마법사 종류와 WB 를 레시피 전으로
#   film.sh restore         위에 더해 사용자 1 의 값도 처음 바꾸기 전으로
# 방법: prefman 에 값을 쓰고 촬영 모드를 다시 들어간다 (st app mode, common.sh reapply_mode). 카메라 앱이 그때 prefman 을 다시 읽어
# 화면 마법사와 WB 를 촬영 쪽에 보낸다 (2026-10-19 실기: Fn 패널 없이 둘 다 적용). 값만 쓰면 앱이 메모리 값을 유지해 반영되지 않는다.
# 처음 바꿀 때 원래 값을 conf 에 남긴다: pw_custom1.bak (사용자 1 의 7가지 값), film_orig.bak (화면 마법사 종류, WB 종류, 색온도 K).
# scripts/auto/film_nowb.sh 가 있으면 (메뉴 체크박스 "화이트 밸런스 유지") 레시피가 WB 를 바꾸지 않는다.
# prefman 위치와 반영 확인 방법(varlist)은 NXWA (WApaperplane/NXWA-nx500_modding, AGPL-3.0) 의 FilmLab 에서 가져왔다.
# 레시피 값은 실제 필름 특성 조사로 nx500ex 가 정했다 (docs/research/2026-10-19-film-stock-profiles.md).
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
PW_TYPE=0xa3d4   # APPPREF_EFFECT_PW_TYPE: 해제 0, 표준 1 ... 클래식 9, 사용자 1~3 10~12
WB_TYPE=0xa390   # APPPREF_WB_TYPE: 자동 0 ... 색온도 10
WB_K=0xa394      # APPPREF_WB_K_VALUE
BAK="$D/conf/pw_custom1.bak"
ORIG="$D/conf/film_orig.bak"
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
wb_k() { st cap capdtm varlist 2>/dev/null | tr -d '\000 ' | grep -a 'WBCOLORTEMP' | cut -d'|' -f5; }
# 조건이 맞을 때까지 최대 3초 기다린다 (0.2초 간격)
wait_for() { _w=0; while [ $_w -lt 15 ]; do eval "$1" && return 0; sleep 0.2; _w=$((_w + 1)); done; return 1; }
# 원래 화면 마법사 종류, WB 종류, K 를 처음 한 번 남긴다
orig_save() { [ -s "$ORIG" ] || { mkdir -p "$D/conf"; echo "$(pget $PW_TYPE) $(pget $WB_TYPE) $(pget $WB_K)" > "$ORIG"; sync; jlog "film orig $(cat "$ORIG")"; }; }
# 원래 화면 마법사 종류와 WB 를 prefman 에 되돌린다 (모드 재진입은 부르는 쪽에서)
orig_put() {
  [ -s "$ORIG" ] || return 0
  set -- $(cat "$ORIG")
  pset $PW_TYPE "$1"
  [ -f "$D/scripts/auto/film_nowb.sh" ] || { pset $WB_TYPE "$2"; pset $WB_K "$3"; }
  rm -f "$ORIG"
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

case "$1" in
  off)
    [ -s "$ORIG" ] || { popup "레시피를 쓰고 있지 않음" 2; exit 0; }
    orig_put; sleep 1; reapply_mode; conf_set film_last ""
    jlog "film off"
    popup "필름 레시피 끔" 2
    ;;
  restore)
    [ -s "$BAK" ] || [ -s "$ORIG" ] || { popup "바꾼 적 없음" 2; exit 0; }
    [ -s "$BAK" ] && { c1_set $(cat "$BAK"); jlog "film restore custom1 $(cat "$BAK")"; rm -f "$BAK"; }
    orig_put; sleep 1; reapply_mode; conf_set film_last ""
    popup "사용자 1 원래대로" 2
    ;;
  *)
    L=$(grep "^$1|" "$D/scripts/film/recipes.txt" 2>/dev/null | head -1)
    [ -n "$L" ] || { popup "레시피 없음: $1" 2; exit 0; }
    IFS='|'; set -- $L; unset IFS
    NAME=$3; WB=${11}
    VALS="$4 $5 $6 $7 $8 $9 ${10}"
    [ -f "$D/scripts/auto/film_nowb.sh" ] && WB=
    [ -s "$BAK" ] || { mkdir -p "$D/conf"; c1_get > "$BAK"; sync; jlog "film backup custom1 $(cat "$BAK")"; }
    orig_save
    c1_set $VALS
    pset $PW_TYPE 10
    if [ -n "$WB" ]; then
      pset $WB_TYPE 10; pset $WB_K "$WB"
    elif [ ! -f "$D/scripts/auto/film_nowb.sh" ]; then
      # 색온도 없는 레시피: WB 는 레시피 전 값으로
      set -- $(cat "$ORIG"); pset $WB_TYPE "$2"; pset $WB_K "$3"
    fi
    jlog "film $NAME custom1 <- $VALS wb ${WB:-orig}"
    sleep 1   # 메뉴가 닫힐 때까지
    reapply_mode
    wait_for 'isp_match $VALS'; R=$?
    RW=0; [ -n "$WB" ] && { wait_for '[ "$(wb_k)" = "$WB" ]'; RW=$?; }
    jlog "film $NAME done in $(( ($(now_cs) - T_START) * 10 ))ms isp $(isp_get) k $(wb_k)"
    if [ $R = 0 ] && [ $RW = 0 ]; then
      conf_set film_last "$NAME"
      if [ -n "$WB" ]; then popup "필름: $NAME<br>WB ${WB}K" 2; else popup "필름: $NAME" 2; fi
    else
      popup "반영 확인 안 됨<br>다시 해 보세요" 3
    fi
    ;;
esac
