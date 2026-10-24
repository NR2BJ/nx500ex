#!/bin/sh
# LUT 재적재 트리거 3차: 한 번에 후보 하나만. 2차에서 "다이얼과 다른 앱 모드로 보내기 (st app mode p, 다이얼 M)" 직후 촬영 명령이 죽고
# 마지막의 st cap capt stop 까지 가서 소프트 프리징 (배터리 분리로 복구). 그 둘과 st cap iq af mv 는 뺌.
#   luttrig3.sh <번호>     흑백 표를 쓰고 그 후보 하나를 한 뒤 5초 기다리고 원래 표로 복구 (재생 왕복)
#   luttrig3.sh info       포커스 모드 관련 값 보기 (AF/MF 판정에 쓸 이름 찾기)
# 후보: 1 AF 모드 다시 설정 (st app nx capture af-mode single, af_toggle 이 쓰는 명령)
#       2 LCD 껐다 켜기 (st app bb lcd off/on, 전에 무해 확인)
#       3 화면 터치 (st key touch click, pwtest 가 쓰는 명령) 뒤 반셔터
#       4 (뺌: 다이얼과 다른 앱 모드로 보내면 촬영 서비스가 죽음)
#       5 재생 진입 뒤 반셔터 (지금 lut_reload 가 쓰는 방식, 비교용)
# 사용: sh /mnt/mmc/nx500ex/scripts/luttrig3.sh 1   (MF 로 두고 화면을 보면서. 하나 끝나면 다음 번호)
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
ADDR_A=0x810c3500; ADDR_B=0x81123d00
G_A="$D/lut/gray_a.bin"; G_B="$D/lut/gray_b.bin"
O_A="$D/conf/lut_orig_a.bin"; O_B="$D/conf/lut_orig_b.bin"
wr() { nxmem w $ADDR_A "$1" > /dev/null 2>&1; nxmem w $ADDR_B "$2" > /dev/null 2>&1; }
case "$1" in
  info)
    echo "--- getusr FOCUSMODE"; st cap capdtm getusr FOCUSMODE 2>&1 | tr -d '\000'
    echo "--- getusr AFMODE"; st cap capdtm getusr AFMODE 2>&1 | tr -d '\000'
    echo "--- varlist (focus, af, mf)"; st cap capdtm varlist 2>/dev/null | tr -d '\000' | grep -a -i -E "focus|af|mf" | head -20
    exit 0 ;;
  1|2|3|5) ;;
  *) echo "사용: luttrig3.sh 1|2|3|5|info"; exit 2 ;;
esac
[ -s "$O_A" ] && [ -s "$O_B" ] || { mkdir -p "$D/conf"; nxmem r $ADDR_A 0x603c4 "$O_A" > /dev/null 2>&1; nxmem r $ADDR_B 0x69dc4 "$O_B" > /dev/null 2>&1; }
wr "$G_A" "$G_B"
jlog "luttrig3 $1 start (gray written)"
popup "후보 $1" 2; sleep 1
case "$1" in
  1) st app nx capture af-mode single > /dev/null 2>&1 ;;
  2) st app bb lcd off > /dev/null 2>&1; sleep 0.5; st app bb lcd on > /dev/null 2>&1 ;;
  3) st key touch click 360 240 > /dev/null 2>&1; sleep 1.5; key push s1; sleep 0.3; key release s1 ;;
  5) key click pb; sleep 1.2; key push s1; sleep 0.4; key release s1 ;;
esac
sleep 5
popup "후보 $1 끝, 복구" 2
wr "$O_A" "$O_B"; key click pb; sleep 1.2; key push s1; sleep 0.4; key release s1
jlog "luttrig3 $1 done"
