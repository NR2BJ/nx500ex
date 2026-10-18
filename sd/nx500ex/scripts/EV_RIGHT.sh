#!/bin/sh
# EV+오른쪽: 터치스크린 켜기/끄기
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
if [ "$(touch_get)" = 1 ]; then touch_set 0; popup "터치 끔" 1; else touch_set 1; popup "터치 켬" 1; fi
reapply_mode
