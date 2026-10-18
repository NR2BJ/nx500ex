#!/bin/sh
# 셔터, 전원, 플래시 횟수 (깨끗하게 전원을 끌 때만 갱신된다)
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
v() { prefman get 3 "$1" l 2>/dev/null | sed -n 's/.*value = \([0-9]*\).*/\1/p'; }
popup "셔터 $(v 0x208)  전원 $(v 0x244)  플래시 $(v 0x248)" 5
