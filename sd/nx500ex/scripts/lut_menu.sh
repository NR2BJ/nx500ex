#!/bin/sh
# 사용자 LUT 메뉴 생성: lut/user 의 zip (웹 변환기 결과) 을 zip 마다 자기 폴더에 풀고, lut/user/*/<id>_a.bin, <id>_b.bin 을 훑어
# scripts/gui_lut_user.NX500 (넘치면 gui_lut_user2, 3 ...) 을 만든다. 표시 이름은 그 폴더의 <id>.txt 첫 줄, 없으면 id. 폴더 이름과 id 는 달라도 된다.
# 전원을 켤 때 boot.sh 가 부른다. 한 화면 7개 + 다음.
D=${NX500EX:-/mnt/mmc/nx500ex}
U="$D/lut/user"
S="$D/scripts"
SIZE_A=394180; SIZE_B=433604
mkdir -p "$U"
# 웹 변환기의 zip 을 그대로 넣어도 되게: lut/user 의 *.zip 과 SD 루트의 nx500ex-lut-*.zip 을 zip 마다 자기 폴더 lut/user/<이름>/ 에 풀고 zip 은 지운다.
# 폴더 이름은 nx500ex-lut-<id>.zip 이면 <id>, 아니면 zip 이름. 카메라 busybox 1.20 의 unzip 에는 -j 가 없어 예전 판의 nx500ex/lut/user/ 폴더형이면 끌어올린다
for z in "$U"/*.zip "$U"/*.ZIP "${D%/*}"/nx500ex-lut-*.zip "${D%/*}"/nx500ex-lut-*.ZIP; do
  [ -f "$z" ] || continue
  n=${z##*/}; n=${n%.*}; n=${n#nx500ex-lut-}
  T="$U/$n"; mkdir -p "$T"
  if unzip -o -q "$z" -d "$T" 2>/dev/null; then
    if [ -d "$T/nx500ex/lut/user" ]; then mv -f "$T"/nx500ex/lut/user/* "$T"/ 2>/dev/null; rm -rf "$T/nx500ex"; fi
    rm -f "$z"
    echo "unzipped $n"
  else
    rm -rf "$T"; echo "unzip failed ${z##*/}"
  fi
done
# 예전 판이 lut/user 바로 아래에 풀어 둔 파일은 자기 폴더로 옮긴다
for a in "$U"/*_a.bin; do
  [ -f "$a" ] || continue
  id=${a##*/}; id=${id%_a.bin}
  mkdir -p "$U/$id"; mv -f "$U/$id"_[ab].bin "$U/$id.txt" "$U/readme-$id.txt" "$U/읽어주세요-$id.txt" "$U/$id/" 2>/dev/null
done
rm -rf "$U/zip"
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
for a in "$U"/*/*_a.bin; do
  [ -f "$a" ] || continue
  dir=${a%/*}
  id=${a##*/}; id=${id%_a.bin}
  b="$dir/${id}_b.bin"
  [ -f "$b" ] || continue
  [ "$(wc -c < "$a" | tr -d " ")" = $SIZE_A ] && [ "$(wc -c < "$b" | tr -d " ")" = $SIZE_B ] || continue
  name=$(head -n 1 "$dir/$id.txt" 2>/dev/null | tr -d '\r|')
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
