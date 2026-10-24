#!/bin/sh
# 3D LUT: 카메라 이미지 처리 메모리의 3D LUT 표 42개를 전부 우리 표로 바꾼다.
#   lut.sh <id> [quiet]  lut/<id>_a.bin (구간 A, 0x810c3500 부터 표 20개) 와 lut/<id>_b.bin (구간 B, 0x81123d00 부터 22개) 를 쓰고
#                        반셔터 키를 넣어 다시 적재시킨다. quiet 는 film.sh 가 부를 때 (팝업과 메뉴 대기 없음, conf/lut_by_film 표식 유지)
#   lut.sh off [quiet]   처음에 남긴 원래 표 (conf/lut_orig_a.bin, lut_orig_b.bin) 를 되쓴다
#   lut.sh reapply   전원을 켤 때 (scripts/auto/lut_reapply.sh): 원래 표를 새로 남기고 마지막 LUT 를 다시 쓴다
# 근거: docs/research/2026-10-25-lut-dump-analysis.md. 표는 RAM 에만 있어 전원을 끄면 순정으로 돌아온다.
# 적재는 반셔터 때 일어나고 키 주입(key push s1)으로도 된다 (2026-10-25 실기). 라이브 뷰는 표준에서 표 17 을 쓰지만
# 정지 사진은 밝기, 색온도에 따라 다른 표를 골라서 (표 17 만 바꾸면 사진이 안 바뀐 경우 있음) 42개 전부를 바꾼다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
ADDR_A=0x810c3500; SIZE_A=0x603c4    # 394180
ADDR_B=0x81123d00; SIZE_B=0x69dc4    # 433604
ORIG_A="$D/conf/lut_orig_a.bin"
ORIG_B="$D/conf/lut_orig_b.bin"
AUTO="$D/scripts/auto/lut_reapply.sh"
LOCK=/tmp/nx500ex-lut.pid
QUIET=$2
BYFILM="$D/conf/lut_by_film"   # 필름 레시피가 켠 LUT 라는 표식 (film.sh 가 만들고 지운다. 메뉴에서 직접 고르면 지운다)
say() { [ -n "$QUIET" ] || popup "$@"; }

[ -f $LOCK ] && [ -d /proc/$(cat $LOCK) ] && exit 0
echo $$ > $LOCK
trap 'rm -f $LOCK' EXIT
job_running && { say "촬영 작업 중" 2; exit 0; }

size_ok() { [ -s "$1" ] && [ "$(wc -c < "$1")" = "$2" ]; }
# 원래 표를 처음 한 번 남긴다
orig_save() {
  size_ok "$ORIG_A" $((SIZE_A)) && size_ok "$ORIG_B" $((SIZE_B)) && return 0
  mkdir -p "$D/conf"
  nxmem r $ADDR_A $SIZE_A "$ORIG_A" > /dev/null 2>&1
  nxmem r $ADDR_B $SIZE_B "$ORIG_B" > /dev/null 2>&1
  size_ok "$ORIG_A" $((SIZE_A)) && size_ok "$ORIG_B" $((SIZE_B)) || { rm -f "$ORIG_A" "$ORIG_B"; jlog "lut orig read failed"; return 1; }
  sync; jlog "lut orig saved"
}
# 두 구간을 쓰고 반셔터를 넣어 다시 적재시킨다
bank_write() {
  nxmem w $ADDR_A "$1" > /dev/null 2>&1 || return 1
  nxmem w $ADDR_B "$2" > /dev/null 2>&1 || return 1
  key push s1; sleep 0.4; key release s1
}
name_of() { grep "^$1|" "$D/lut/luts.txt" 2>/dev/null | head -1 | cut -d'|' -f2; }

case "$1" in
  off)
    size_ok "$ORIG_A" $((SIZE_A)) || { say "LUT 를 쓰고 있지 않음" 2; exit 0; }
    bank_write "$ORIG_A" "$ORIG_B" && jlog "lut off" || jlog "lut off write failed"
    rm -f "$AUTO"; conf_set lut_last ""
    [ -n "$QUIET" ] || rm -f "$BYFILM"
    say "LUT 끔" 2
    ;;
  reapply)
    ID=$(cat "$D/conf/lut_last" 2>/dev/null)
    [ -n "$ID" ] && [ -f "$D/lut/${ID}_a.bin" ] || { rm -f "$AUTO"; exit 0; }
    rm -f "$ORIG_A" "$ORIG_B"; orig_save || exit 0
    bank_write "$D/lut/${ID}_a.bin" "$D/lut/${ID}_b.bin" && jlog "lut reapply $ID" || jlog "lut reapply $ID failed"
    ;;
  "")
    say "사용: lut.sh <id>|off" 2
    ;;
  *)
    FA="$D/lut/$1_a.bin"; FB="$D/lut/$1_b.bin"
    size_ok "$FA" $((SIZE_A)) && size_ok "$FB" $((SIZE_B)) || { say "LUT 파일 없음: $1" 2; exit 1; }
    orig_save || { say "원래 표를 못 읽음" 2; exit 1; }
    [ -n "$QUIET" ] || sleep 0.5   # 메뉴가 닫힐 때까지
    if bank_write "$FA" "$FB"; then
      conf_set lut_last "$1"
      printf '#!/bin/sh\n# 전원을 켤 때 마지막 LUT 를 다시 쓴다 (lut.sh 가 만들고 지운다)\nsh "${NX500EX:-/mnt/mmc/nx500ex}/scripts/lut.sh" reapply\n' > "$AUTO"; sync
      [ -n "$QUIET" ] || rm -f "$BYFILM"
      jlog "lut $1${QUIET:+ (film)}"
      say "LUT: $(name_of "$1")" 2
    else
      jlog "lut $1 write failed"
      say "LUT 쓰기 실패" 2
      exit 1
    fi
    ;;
esac
