# 화면 마법사와 WB 를 prefman 으로 다루는 공용 함수 (film.sh, calib.sh 가 불러 쓴다)
# 값을 쓴 뒤 촬영 모드를 다시 들어가면(reapply_mode) 카메라 앱이 prefman 을 다시 읽어 적용한다 (2026-10-19 실기).
# prefman 위치는 상류 ottokiksmaler/nx500_nx1_modding 의 Prefman_tool.md, 반영 확인(varlist)은 ST_CAP_CAPDTM.md. 값 환산은 실기로 맞췄다.
PW_TYPE=0xa3d4   # APPPREF_EFFECT_PW_TYPE: 해제 0, 표준 1 ... 클래식 9, 사용자 1~3 10~12
WB_TYPE=0xa390   # APPPREF_WB_TYPE: 자동 0 ... 색온도 10
WB_K=0xa394      # APPPREF_WB_K_VALUE
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
