#!/bin/sh
# LUT 재적재 트리거 2차 (가볍고 빠른 후보). 1차 (luttrig.sh) 결과: 재생 갔다 오기와 촬영은 되고 나머지는 안 됨.
# 흑백 표를 써 둔 채 후보를 하나씩, 팝업 번호와 함께. 화면이 흑백으로 바뀐 번호를 알려 주면 lut_reload 에 넣는다.
# 사용: sh /mnt/mmc/nx500ex/scripts/luttrig2.sh   (MF 로 두고, 화면을 보면서)
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
ADDR_A=0x810c3500; ADDR_B=0x81123d00
G_A="$D/lut/gray_a.bin"; G_B="$D/lut/gray_b.bin"
O_A="$D/conf/lut_orig_a.bin"; O_B="$D/conf/lut_orig_b.bin"
[ -s "$O_A" ] && [ -s "$O_B" ] || { mkdir -p "$D/conf"; nxmem r $ADDR_A 0x603c4 "$O_A" > /dev/null 2>&1; nxmem r $ADDR_B 0x69dc4 "$O_B" > /dev/null 2>&1; }
wr() { nxmem w $ADDR_A "$1" > /dev/null 2>&1; nxmem w $ADDR_B "$2" > /dev/null 2>&1; }
step() { popup "$1" 3; jlog "luttrig2 $1"; sleep 1; }
wr "$G_A" "$G_B"
jlog "luttrig2 start (gray written) focusmode: $(st cap capdtm getusr FOCUSMODE 2>/dev/null | tr -d '\000\r' | tail -c 80)"
step "1 AF 모드 다시 설정";       st app nx capture af-mode single > /dev/null 2>&1; sleep 4
step "2 LCD 껐다 켜기";            st app bb lcd off > /dev/null 2>&1; sleep 0.5; st app bb lcd on > /dev/null 2>&1; sleep 4
step "3 초점 모터 0 이동";         st cap iq af mv 0 > /dev/null 2>&1; sleep 4
step "4 화면 터치 (MF 확대)";      st key touch click 360 240 > /dev/null 2>&1; sleep 2; key push s1; sleep 0.3; key release s1; sleep 4
step "5 다른 모드 갔다 오기";      st app mode p > /dev/null 2>&1; sleep 1.5; reapply_mode; sleep 5
step "6 OK 키";                    key click ok; sleep 4
step "7 촬영 서비스 정지";         st cap capt stop > /dev/null 2>&1; sleep 4
step "끝: 원래 표로 복구 (재생 왕복)"; wr "$O_A" "$O_B"; lut_reload
jlog "luttrig2 done"
