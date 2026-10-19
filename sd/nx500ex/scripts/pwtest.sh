#!/bin/sh
# 화면 마법사(Picture Wizard) 시험 도구 (FilmLab 준비, 텔넷에서 실행)
#   sh pwtest.sh info      종류 값, 사용자 1 슬롯 값, 실제 반영된 값(ISP) 보기
#   sh pwtest.sh bw        사용자 1 슬롯을 흑백(채도 0)으로 (처음 한 번 원래 값을 conf/pw_custom1.bak 에 백업)
#   sh pwtest.sh restore   사용자 1 슬롯을 백업 값으로 되돌림
#   sh pwtest.sh type N    화면 마법사 종류 값을 N 으로 씀 (prefman)
#   sh pwtest.sh open      Fn 패널을 열고 화면 마법사 칸을 터치한 뒤 OK (목록 열기)
#   sh pwtest.sh ok        OK 한 번
#   sh pwtest.sh go        목록을 열고 사용자 1 까지 오른쪽으로 옮긴 뒤 OK (목록 커서 = 지금 종류, 해제 0 ~ 사용자 3 12 의 13칸, 끝에서 처음으로 돎)
#   sh pwtest.sh wbinfo    화이트 밸런스: prefman 이름표와 값, 촬영 쪽 WB, 반영된 변수
#   sh pwtest.sh wbset K A B   prefman 에 WB 종류 = 색온도(10), 색온도 K, 미세 조정 (A<<16)|B 를 쓴다 (중립 7 7)
#   sh pwtest.sh wbopen    Fn 패널을 열고 WB 칸(AWB)을 터치한 뒤 OK (WB 목록 열기)
# 값 위치: NXWA filmlab.sh (prefman 0xa3ec = APPPREF_EFFECT_STANDARD_R_COLOR, 항목 간격 52, 종류 간격 4, 사용자 1 = 9번째)
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
PW_TYPE=0xa3d4   # APPPREF_EFFECT_PW_TYPE 추정 (STANDARD_R_COLOR 바로 앞 OFF_* 다섯 개 앞). info 가 이름표로 확인
pget() { prefman get 0 "$1" l 2>/dev/null | tr -d '\000\r' | sed -n 's/.*value = \([-0-9]*\).*/\1/p'; }
pset() { prefman set 0 "$1" l "$2" > /dev/null 2>&1; }
c1() { printf 0x%05x $((0xa3ec + $1 * 52 + 9 * 4)); }   # 사용자 1 의 항목 $1 (R G B HUE SAT SHARP CON = 0..6)
isp() {
  st cap capdtm varlist 2>/dev/null | tr -d '\000' | awk -F'|' '/VARIABLE_PW/ { gsub(/ /, "", $2); gsub(/ /, "", $4); print $2, $4 }' |
  while read n h; do
    case "$h" in 0x*) ;; *) continue ;; esac
    v=$(( h >> 16 ))
    case "$n" in
      *COLOR_*) echo "$n=$(( v * 100 / 2032 ))" ;;
      *) [ $v -ge 32768 ] && v=$((v - 65536)); echo "$n=$(( 10 + (v - 15) / 16 ))" ;;
    esac
  done | sed 's/VARIABLE_PW//' | tr '\n' ' '; echo
}
case "$1" in
  info)
    echo "이름표: $(prefman info 0 2>/dev/null | tr -d '\000' | grep -a -i 'PW_TYPE' | head -3)"
    echo "종류 ($PW_TYPE) = $(pget $PW_TYPE)"
    echo "사용자 1 슬롯: R=$(pget $(c1 0)) G=$(pget $(c1 1)) B=$(pget $(c1 2)) HUE=$(pget $(c1 3)) SAT=$(pget $(c1 4)) SHARP=$(pget $(c1 5)) CON=$(pget $(c1 6))"
    echo "반영된 값 (ISP): $(isp)"
    echo "PW (촬영 쪽): $(st cap capdtm getusr PW 2>/dev/null | tr -d '\000\r')"
    ;;
  bw)
    B="$D/conf/pw_custom1.bak"
    if [ ! -s "$B" ]; then
      mkdir -p "$D/conf"
      echo "$(pget $(c1 0)) $(pget $(c1 1)) $(pget $(c1 2)) $(pget $(c1 3)) $(pget $(c1 4)) $(pget $(c1 5)) $(pget $(c1 6))" > "$B"; sync
      echo "백업: $(cat "$B")"
    fi
    pset $(c1 4) 0
    echo "사용자 1 채도 = $(pget $(c1 4))"
    ;;
  restore)
    B="$D/conf/pw_custom1.bak"
    [ -s "$B" ] || { echo "백업 없음"; exit 1; }
    set -- $(cat "$B")
    i=0; for v in "$@"; do pset $(c1 $i) "$v"; i=$((i + 1)); done
    echo "되돌림: $*"
    ;;
  type) pset $PW_TYPE "$2"; echo "종류 = $(pget $PW_TYPE)" ;;
  open) key click fn; sleep 1; st key touch click 300 300 > /dev/null 2>&1; sleep 0.5; key click ok ;;
  ok) key click ok ;;
  go)
    cur=$(pget $PW_TYPE)
    case "$cur" in ''|*[!0-9]*) echo "종류 값을 읽지 못함"; exit 1 ;; esac
    n=$(( (10 - cur + 13) % 13 ))
    echo "지금 종류 $cur -> 오른쪽 $n 번"
    key click fn; sleep 1; st key touch click 300 300 > /dev/null 2>&1; sleep 0.5; key click ok; sleep 1
    while [ $n -gt 0 ]; do key click right; sleep 0.3; n=$((n - 1)); done
    key click ok; sleep 1
    echo "종류 = $(pget $PW_TYPE)"
    echo "반영된 값 (ISP): $(isp)"
    ;;
  wbinfo)
    echo "이름표:"; prefman info 0 2>/dev/null | tr -d '\000' | grep -a -E 'APPPREF_WB_(TYPE|K_VALUE|K_DETAIL|AUTO_DETAIL)'
    echo "종류 (0xa390) = $(pget 0xa390)  색온도 (0xa394) = $(pget 0xa394)"
    _ba=$(pget 0xa3c0); _ba=${_ba:-0}; echo "색온도 미세 (0xa3c0) = $_ba (A=$(( (_ba >> 16) & 0xffff )) B=$(( _ba & 0xffff )))"
    _ba=$(pget 0xa398); _ba=${_ba:-0}; echo "자동 미세 (0xa398) = $_ba (A=$(( (_ba >> 16) & 0xffff )) B=$(( _ba & 0xffff )))"
    echo "촬영 쪽: $(st cap capdtm getusr WB 2>/dev/null | tr -d '\000\r')"
    st cap capdtm varlist 2>/dev/null | tr -d '\000' | grep -a 'WB'
    ;;
  wbset)
    pset 0xa390 10; pset 0xa394 "$2"; pset 0xa3c0 $(( ($3 << 16) | $4 ))
    echo "종류 = $(pget 0xa390)  색온도 = $(pget 0xa394)  미세 = $(pget 0xa3c0)"
    ;;
  wbopen) key click fn; sleep 1; st key touch click 150 330 > /dev/null 2>&1; sleep 0.5; key click ok ;;
  *) sed -n '2,12p' "$0" ;;
esac
