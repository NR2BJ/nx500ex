#!/bin/sh
# 사용자 LUT 메뉴 생성: lut/user/<id>_a.bin, <id>_b.bin (웹 변환기 nx500ex LUT 변환기 또는 tools/lut 로 만든 것) 을 훑어
# scripts/gui_lut_user.NX500 (넘치면 gui_lut_user2, 3 ...) 을 만든다. 표시 이름은 lut/user/<id>.txt 첫 줄, 없으면 id.
# 전원을 켤 때 boot.sh 가 부른다. 한 화면 7개 + 다음.
D=${NX500EX:-/mnt/mmc/nx500ex}
U="$D/lut/user"
S="$D/scripts"
SIZE_A=394180; SIZE_B=433604
rm -f "$S"/gui_lut_user*.NX500
PAGE=1; N=0; TOTAL=0
page_file() { [ "$1" = 1 ] && echo "$S/gui_lut_user.NX500" || echo "$S/gui_lut_user$1.NX500"; }
page_name() { [ "$1" = 1 ] && echo gui_lut_user || echo gui_lut_user$1; }
start_page() {
  F=$(page_file $PAGE)
  { echo "# 자동 생성 (scripts/lut_menu.sh, 전원 켤 때 lut/user 를 훑음)"
    [ $PAGE = 1 ] && echo "back|gui_lut" || echo "back|$(page_name $((PAGE - 1)))"; } > "$F"
}
start_page
for a in "$U"/*_a.bin; do
  [ -f "$a" ] || continue
  id=${a##*/}; id=${id%_a.bin}
  b="$U/${id}_b.bin"
  [ -f "$b" ] || continue
  [ "$(wc -c < "$a")" = $SIZE_A ] && [ "$(wc -c < "$b")" = $SIZE_B ] || continue
  name=$(head -n 1 "$U/$id.txt" 2>/dev/null | tr -d '\r|')
  [ -n "$name" ] || name=$id
  if [ $N -ge 7 ]; then
    echo "page|다음 >|$(page_name $((PAGE + 1)))" >> "$F"
    PAGE=$((PAGE + 1)); N=0; start_page
  fi
  echo "button|$name|lut.sh $id" >> "$F"
  N=$((N + 1)); TOTAL=$((TOTAL + 1))
done
[ $TOTAL = 0 ] && echo "button|lut/user 폴더가 비어 있음|lut.sh help" >> "$F"
sync
echo "user luts: $TOTAL"
