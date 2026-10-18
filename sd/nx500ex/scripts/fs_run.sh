#!/bin/sh
# 포커스 스태킹 실행: 가까운 끝에서 먼 끝까지 초점을 같은 간격으로 옮기며 찍는다. 찍는 동안 MF, 끝나면 AF 복원.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중. EV 두 번으로 중단" 3; exit 0; }
NEAR=$(cat /tmp/nx500ex-fs.near 2>/dev/null); FAR=$(cat /tmp/nx500ex-fs.far 2>/dev/null)
{ [ -n "$NEAR" ] && [ -n "$FAR" ]; } || { popup "가까운 끝, 먼 끝을 먼저 저장" 3; exit 0; }
[ "$NEAR" = "$FAR" ] && { popup "두 끝이 같음" 3; exit 0; }
F=$(ask "장수 (2~200):" "$(conf_get fs_frames 10)" 2 200) || exit 0
conf_set fs_frames "$F"
popup "스태킹 ${F}장 시작 (EV 두 번 = 중단)" 2
(
  fin() { af_restore; rm -f $JOBPID; }
  trap 'fin; jlog "fstack stopped"; exit 0' TERM
  pos() { set -- $(st cap iq af pos 2>/dev/null); echo "$3"; }
  af_save; af_manual
  jlog "fstack start near=$NEAR far=$FAR frames=$F"
  sleep 1
  k=0
  while [ $k -lt "$F" ]; do
    T=$((NEAR + (FAR - NEAR) * k / (F - 1)))
    P=$(pos)
    st cap iq af mv 255 $((T - P)) 255 > /dev/null 2>&1
    sleep 1
    shoot
    jlog "fstack shot $((k+1)) target=$T pos=$(pos)"
    sleep 1
    k=$((k+1))
  done
  fin; jlog "fstack done"
  popup "스태킹 완료 ${F}장" 3
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
