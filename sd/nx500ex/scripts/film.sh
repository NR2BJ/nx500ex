#!/bin/sh
# 필름 레시피: 화면 마법사 사용자 1 과 화이트 밸런스를 레시피 값으로 바꾼다.
#   film.sh <레시피 이름>   film/recipes.txt 의 값으로 사용자 1 을 바꾸고 사용자 1 을 고른다. WB 칸이 K 면 색온도, auto 면 자동
#   film.sh off             사용자 1 의 값, 화면 마법사 종류, WB 를 모두 레시피 전으로 (restore 도 같음)
# 방법: prefman 에 값을 쓰고 촬영 모드를 다시 들어간다 (st app mode, common.sh reapply_mode). 카메라 앱이 그때 prefman 을 다시 읽어
# 화면 마법사와 WB 를 촬영 쪽에 보낸다 (2026-10-19 실기: Fn 패널 없이 둘 다 적용). 값만 쓰면 앱이 메모리 값을 유지해 반영되지 않는다.
# 처음 바꿀 때 원래 값을 conf 에 남긴다: pw_custom1.bak (사용자 1 의 7가지 값), film_orig.bak (화면 마법사 종류, WB 종류, 색온도 K).
# scripts/auto/film_nowb.sh 가 있으면 (메뉴 체크박스 "화이트 밸런스 유지") 레시피가 WB 를 바꾸지 않는다.
# 레시피 값은 실제 필름 특성 조사로 nx500ex 가 정했다 (docs/research/2026-10-19-film-stock-profiles.md).
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
. "$D/scripts/film/pw.sh"
BAK="$D/conf/pw_custom1.bak"
ORIG="$D/conf/film_orig.bak"
LOCK=/tmp/nx500ex-film.pid

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
  off|restore)
    # 레시피 전으로: 사용자 1 의 값 (원래 종류가 사용자 1 이었을 수 있어 값까지 되돌린다), 화면 마법사 종류, WB
    [ -s "$BAK" ] || [ -s "$ORIG" ] || { popup "레시피를 쓰고 있지 않음" 2; exit 0; }
    [ -s "$BAK" ] && { c1_set $(cat "$BAK"); jlog "film restore custom1 $(cat "$BAK")"; rm -f "$BAK"; }
    orig_put; sleep 1; reapply_mode; conf_set film_last ""
    jlog "film off"
    popup "필름 레시피 끔" 2
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
    if [ "$WB" = auto ]; then
      pset $WB_TYPE 0
    elif [ -n "$WB" ]; then
      pset $WB_TYPE 10; pset $WB_K "$WB"
    elif [ ! -f "$D/scripts/auto/film_nowb.sh" ]; then
      # 색온도 없는 레시피: WB 는 레시피 전 값으로
      set -- $(cat "$ORIG"); pset $WB_TYPE "$2"; pset $WB_K "$3"
    fi
    jlog "film $NAME custom1 <- $VALS wb ${WB:-orig}"
    sleep 1   # 메뉴가 닫힐 때까지
    reapply_mode
    wait_for 'isp_match $VALS'; R=$?
    RW=0
    case "$WB" in
      auto) wait_for 'st cap capdtm getusr WB 2>/dev/null | grep -q WB_AUTO\ '; RW=$? ;;
      '') ;;
      *) wait_for '[ "$(wb_k)" = "$WB" ]'; RW=$? ;;
    esac
    jlog "film $NAME done in $(( ($(now_cs) - T_START) * 10 ))ms isp $(isp_get) k $(wb_k)"
    if [ $R = 0 ] && [ $RW = 0 ]; then
      conf_set film_last "$NAME"
      case "$WB" in
        auto) popup "필름: $NAME<br>WB 자동" 2 ;;
        '') popup "필름: $NAME" 2 ;;
        *) popup "필름: $NAME<br>WB ${WB}K" 2 ;;
      esac
    else
      popup "반영 확인 안 됨<br>다시 해 보세요" 3
    fi
    ;;
esac
