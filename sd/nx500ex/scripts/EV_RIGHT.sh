#!/bin/sh
# EV+오른쪽: 터치스크린 켜기/끄기 (NX-KS 와 같이 prefman 값만 바꾼다)
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
if [ "$(touch_get)" = 1 ]; then touch_set 0; popup "터치 꺼짐" 1; else touch_set 1; popup "터치 켜짐" 1; fi
