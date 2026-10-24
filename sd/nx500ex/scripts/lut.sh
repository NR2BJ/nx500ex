#!/bin/sh
# 3D LUT: 카메라 이미지 처리 메모리의 표 17 (0x81115200, 화면 마법사 표준의 라이브 뷰와 JPEG 표) 을 우리 표로 바꾼다.
#   lut.sh <id>      lut/<id>.bin (19652 바이트, (Cr, Cb, Y, 0) 17^3) 을 쓰고 반셔터를 넣어 다시 적재시킨다
#   lut.sh off       처음에 남긴 원래 표 (conf/lut_orig.bin) 를 되쓴다
#   lut.sh reapply   전원을 켤 때 (scripts/auto/lut_reapply.sh): 원래 표를 새로 남기고 마지막 LUT 를 다시 쓴다
# 근거: docs/research/2026-10-25-lut-dump-analysis.md. 표는 RAM 에만 있어 전원을 끄면 순정으로 돌아온다.
# 적재는 반셔터 때 일어난다 (st app mode 로는 안 됨, 2026-10-25 실기). 키 주입 s1 로 되는지는 실기 확인 대상.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
ADDR=0x81115200
SIZE=19652
ORIG="$D/conf/lut_orig.bin"
AUTO="$D/scripts/auto/lut_reapply.sh"
LOCK=/tmp/nx500ex-lut.pid

[ -f $LOCK ] && [ -d /proc/$(cat $LOCK) ] && exit 0
echo $$ > $LOCK
trap 'rm -f $LOCK' EXIT
job_running && { popup "촬영 작업 중" 2; exit 0; }

# 원래 표를 처음 한 번 남긴다. 크기가 맞고 중립축 (128,128,Y) 이 보존된 표인지 간단히 본다
orig_save() {
  [ -s "$ORIG" ] && [ "$(wc -c < "$ORIG")" = $SIZE ] && return 0
  mkdir -p "$D/conf"
  nxmem r $ADDR $SIZE "$ORIG" > /dev/null 2>&1 || { rm -f "$ORIG"; jlog "lut orig read failed"; return 1; }
  [ "$(wc -c < "$ORIG")" = $SIZE ] || { rm -f "$ORIG"; jlog "lut orig size bad"; return 1; }
  sync; jlog "lut orig saved"
}
# 표를 쓰고 반셔터를 넣어 다시 적재시킨다
bank_write() {
  nxmem w $ADDR "$1" > /dev/null 2>&1 || return 1
  key push s1; sleep 0.4; key release s1
}
name_of() { grep "^$1|" "$D/lut/luts.txt" 2>/dev/null | head -1 | cut -d'|' -f2; }

case "$1" in
  off)
    [ -s "$ORIG" ] || { popup "LUT 를 쓰고 있지 않음" 2; exit 0; }
    bank_write "$ORIG" && jlog "lut off" || jlog "lut off write failed"
    rm -f "$AUTO"; conf_set lut_last ""
    popup "LUT 끔" 2
    ;;
  reapply)
    ID=$(cat "$D/conf/lut_last" 2>/dev/null)
    [ -n "$ID" ] && [ -f "$D/lut/$ID.bin" ] || { rm -f "$AUTO"; exit 0; }
    rm -f "$ORIG"; orig_save || exit 0
    bank_write "$D/lut/$ID.bin" && jlog "lut reapply $ID" || jlog "lut reapply $ID failed"
    ;;
  "")
    popup "사용: lut.sh <id>|off" 2
    ;;
  *)
    F="$D/lut/$1.bin"
    [ -f "$F" ] && [ "$(wc -c < "$F")" = $SIZE ] || { popup "LUT 파일 없음: $1" 2; exit 0; }
    orig_save || { popup "원래 표를 못 읽음" 2; exit 0; }
    sleep 0.5   # 메뉴가 닫힐 때까지
    if bank_write "$F"; then
      conf_set lut_last "$1"
      printf '#!/bin/sh\n# 전원을 켤 때 마지막 LUT 를 다시 쓴다 (lut.sh 가 만들고 지운다)\nsh "${NX500EX:-/mnt/mmc/nx500ex}/scripts/lut.sh" reapply\n' > "$AUTO"; sync
      jlog "lut $1"
      popup "LUT: $(name_of "$1")" 2
    else
      jlog "lut $1 write failed"
      popup "LUT 쓰기 실패" 2
    fi
    ;;
esac
