#!/bin/sh
# 사용자 LUT 메뉴 생성: lut/user 의 zip (웹 변환기 결과) 을 풀고, lut/user/<id>_a.bin, <id>_b.bin 을 훑어
# scripts/gui_lut_user.NX500 (넘치면 gui_lut_user2, 3 ...) 을 만든다. 표시 이름은 lut/user/<id>.txt 첫 줄, 없으면 id.
# 전원을 켤 때 boot.sh 가 부른다. 한 화면 7개 + 다음.
D=${NX500EX:-/mnt/mmc/nx500ex}
U="$D/lut/user"
S="$D/scripts"
SIZE_A=394180; SIZE_B=433604
mkdir -p "$U"
# 웹 변환기의 zip 을 그대로 넣어도 되게: lut/user 의 *.zip 과 SD 루트의 nx500ex-lut-*.zip 을 풀고 (경로 무시) zip 은 lut/user/zip 으로 옮긴다
for z in "$U"/*.zip "$U"/*.ZIP "${D%/*}"/nx500ex-lut-*.zip; do
  [ -f "$z" ] || continue
  # 카메라 busybox 1.20 의 unzip 에는 -j (경로 무시) 가 없다. 변환기의 zip 은 폴더 없이 평면이고, 예전 판의 nx500ex/lut/user/ 폴더형이면 끌어올린다
  if unzip -o -q "$z" -d "$U" 2>/dev/null; then
    if [ -d "$U/nx500ex/lut/user" ]; then mv -f "$U"/nx500ex/lut/user/* "$U"/ 2>/dev/null; rm -rf "$U/nx500ex"; fi
    mkdir -p "$U/zip"; mv -f "$z" "$U/zip/" 2>/dev/null
    echo "unzipped ${z##*/}"
  else
    echo "unzip failed ${z##*/}"
  fi
done
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
  [ "$(wc -c < "$a" | tr -d " ")" = $SIZE_A ] && [ "$(wc -c < "$b" | tr -d " ")" = $SIZE_B ] || continue
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
