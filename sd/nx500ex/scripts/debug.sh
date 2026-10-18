#!/bin/sh
# 메뉴 "진단 기록" 체크박스. boot.sh 와 common.sh 가 auto 에 이 파일이 있는지로 판단한다 (다음 블루투스 켜기부터 mon.log, keyscan.out, 바로 timing.log).
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
stay
