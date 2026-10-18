#!/bin/sh
# 진단 기록 켬: 다음 블루투스 켜기(또는 전원 켜기)부터 mon.sh 와 keyscan debug 기록
D=${NX500EX:-/mnt/mmc/nx500ex}
touch "$D/debug"; sync
