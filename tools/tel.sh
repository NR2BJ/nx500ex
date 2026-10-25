#!/bin/sh
# 카메라 텔넷으로 명령을 보내고 출력을 받는다 (집 WiFi 에 붙어 있을 때). 사용: sh tools/tel.sh "명령1" "명령2" ... [마지막 인자가 숫자면 기다릴 초]
# root 로 들어가며 비밀번호는 없다. 각 명령 뒤 1 초 기다리고, 마지막에 WAIT 초 (기본 3) 뒤 exit.
IP=${NXIP:-192.168.1.66}
WAIT=3
eval "last=\${$#}"; case "$last" in [0-9]|[0-9][0-9]) WAIT=$last ;; esac
{ sleep 1; printf 'root\n'; sleep 1; printf '\n'; sleep 1
  for c in "$@"; do case "$c" in "$last") [ "$WAIT" = "$last" ] && continue ;; esac; printf '%s\n' "$c"; sleep 1; done
  sleep "$WAIT"; printf 'exit\n'; sleep 1; } | timeout $((WAIT + 3 * $# + 15)) nc "$IP" 23 2>&1 | tr -d '\r' | sed -n '/^\[root@drime5/,$p' | grep -v '^\[root@drime5 ~\]# exit$\|^logout$'
