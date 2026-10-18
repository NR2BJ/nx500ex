#!/bin/sh
# 포커스 스태킹 실행: 가까운 끝에서 먼 끝까지 초점을 같은 간격으로 옮기며 찍는다. 장수는 메뉴 (conf/fs_frames).
# 초점은 모터를 직접 움직이고(st cap iq af mv), 촬영 때 카메라가 초점을 다시 잡지 않도록 촬영 서비스의 MF 를 켠다 (st cap capt mf on).
# 반셔터를 누른 채 두는 방식은 AF-S 가 처음 잡은 위치로 되돌려 초점이 들쭉날쭉했다 (2026-10-19 실기).
# st cap capt mf 는 펌웨어의 촬영 디버그 명령이다 (효과는 jobs.log 의 촬영 전후 위치로 확인).
# 드라이브는 그동안 단사로 바꿨다가 되돌린다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
job_running && { popup "다른 작업 중" 3; exit 0; }
NEAR=$(cat /tmp/nx500ex-fs.near 2>/dev/null); FAR=$(cat /tmp/nx500ex-fs.far 2>/dev/null)
{ [ -n "$NEAR" ] && [ -n "$FAR" ]; } || { popup "가까운 끝, 먼 끝을<br>먼저 저장" 3; exit 0; }
[ "$NEAR" = "$FAR" ] && { popup "두 끝이 같음" 3; exit 0; }
F=$(conf_get fs_frames 10 2 200)
popup "스태킹 ${F}장<br>(EV 두번=중단)" 2
(
  fin() { keys_release; st cap capt mf off > /dev/null 2>&1; drive_restore; rm -f $JOBPID; }
  trap 'fin; jlog "fstack stopped"; exit 0' TERM
  pos() { set -- $(st cap iq af pos 2>/dev/null); echo "$3"; }
  jlog "fstack start near=$NEAR far=$FAR frames=$F"
  drive_save; drive_single
  st cap capt mf on > /dev/null 2>&1
  sleep 1
  k=0
  while [ $k -lt "$F" ]; do
    T=$((NEAR + (FAR - NEAR) * k / (F - 1)))
    P=$(pos)
    st cap iq af mv 255 $((T - P)) 255 > /dev/null 2>&1
    sleep 0.5
    B=$(pos)
    n0=$(dcim_count)
    shoot
    wait_file $n0 8 || { fin; jlog "fstack stopped: no photo at $((k+1))"; popup "사진 없음, 중단" 3; exit 0; }
    jlog "fstack shot $((k+1)) target=$T before=$B after=$(pos)"
    k=$((k+1))
  done
  fin; jlog "fstack done"
  popup "스태킹 완료 ${F}장" 3
) < /dev/null > /dev/null 2>&1 &
echo $! > $JOBPID
