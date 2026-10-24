#!/bin/sh
# LUT 재적재 트리거 찾기 (MF 에서 반셔터로는 적재가 안 됨, 2026-10-25 실기). 결과: 1~6 안 됨, 7 (재생 갔다가 반셔터로 복귀) 됨 -> common.sh lut_reload.
# 흑백 표를 써 둔 채 후보 동작을 하나씩 하며 팝업으로 번호를 보여 준다. 화면이 흑백으로 바뀐 번호가 트리거다.
# 끝나면 원래 표로 되돌리고 반셔터를 넣는다 (AF 면 복구됨. MF 면 찾은 트리거로 복구되는지 같은 번호를 다시 본다).
# 사용: sh /mnt/mmc/nx500ex/scripts/luttrig.sh   (MF 로 두고, 화면을 보면서)
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
. "$D/scripts/film/pw.sh"
ADDR_A=0x810c3500; ADDR_B=0x81123d00
G_A="$D/lut/gray_a.bin"; G_B="$D/lut/gray_b.bin"
O_A="$D/conf/lut_orig_a.bin"; O_B="$D/conf/lut_orig_b.bin"
[ -s "$O_A" ] && [ -s "$O_B" ] || { mkdir -p "$D/conf"; nxmem r $ADDR_A 0x603c4 "$O_A" > /dev/null 2>&1; nxmem r $ADDR_B 0x69dc4 "$O_B" > /dev/null 2>&1; }
wr() { nxmem w $ADDR_A "$1" > /dev/null 2>&1; nxmem w $ADDR_B "$2" > /dev/null 2>&1; }
step() { popup "$1" 3; jlog "luttrig $1"; sleep 1; }
wr "$G_A" "$G_B"
jlog "luttrig start (gray written)"
step "1 반셔터 주입";            key push s1; sleep 0.4; key release s1; sleep 4
step "2 모드 재진입";            reapply_mode; sleep 5
step "3 AEL 키";                 key push ael; sleep 0.3; key release ael; sleep 4
step "4 촬영 MF 끄고 켜기";      st cap capt mf off > /dev/null 2>&1; sleep 1; st cap capt mf on > /dev/null 2>&1; sleep 4
step "5 드라이브 단사";          st app drive single > /dev/null 2>&1; sleep 4
step "6 화면 마법사 바꿨다 복귀"; P=$(pget $PW_TYPE); pset $PW_TYPE 2; reapply_mode; sleep 3; pset $PW_TYPE "$P"; reapply_mode; sleep 5
step "7 재생 갔다 오기";         key push pb; sleep 0.3; key release pb; sleep 3; key push pb; sleep 0.3; key release pb; sleep 4
step "8 사진 한 장";             shoot; sleep 6
step "끝: 원래 표로 복구";       wr "$O_A" "$O_B"; key push s1; sleep 0.4; key release s1
jlog "luttrig done"
