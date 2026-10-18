#!/bin/sh
# 화면 캡처 (순정 기능): SD 루트에 save_screen_enable.txt 가 있으면 EV+OK 로 SD 루트에 OSD####.jpg 를 저장한다.
# 파일 내용은 다음 번호 (2바이트, 1부터). 카메라가 시작할 때만 읽는다면 전원을 껐다 켜야 동작한다.
[ -f /mnt/mmc/save_screen_enable.txt ] || printf '\001\000' > /mnt/mmc/save_screen_enable.txt
sync
