#!/bin/sh
# SSH / SFTP / SCP 서버 (Dropbear, bin/dropbearmulti) 시작. 메뉴 체크박스 "SSH / SFTP" (켜 두면 전원 켤 때마다 auto 에서 시작).
# 텔넷/FTP 와 달리 암호화와 인증이 있다. 포트 22, 사용자 root.
#   공개키: conf/ssh/authorized_keys (한 줄에 키 하나). SD 루트에 authorized_keys 나 *.pub 를 두고 켜면 여기로 옮겨 합친다.
#   공개키가 하나라도 있으면 비밀번호 로그인은 막는다 (-s). 하나도 없으면 비밀번호 없는 root 로그인을 허용해 (-B) 텔넷처럼 들어올 수 있게 한다.
#   호스트 키: conf/ssh/host_ed25519 (첫 접속 때 만든다, -R). 카드를 바꾸면 PC 쪽 known_hosts 경고가 날 수 있다.
#   SFTP 는 bin/sftp-server (OpenSSH, 상류 ssh-server 의 빌드). 루트는 / 이고 카드는 /mnt/mmc.
# 모든 파일이 SD 안에 있다 (경로는 tools/ssh/localoptions.h 로 컴파일). 카메라 플래시에는 아무것도 두지 않는다.
# 기록: log/ssh.log (접속, 인증 결과), 시작 줄은 log/boot.log.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
CONF=$D/conf/ssh
mkdir -p "$CONF"
sh "$D/scripts/off_ssh.sh"
[ -f "$CONF/README.txt" ] || cat > "$CONF/README.txt" <<'TXT'
nx500ex SSH 폴더
- authorized_keys: 접속을 허용할 공개키 (ssh-ed25519 ... 또는 ssh-rsa ...). 한 줄에 하나. PC 의 ~/.ssh/id_ed25519.pub 내용을 붙여 넣는다.
  SD 루트에 authorized_keys 나 아무 이름의 .pub 파일을 두고 카메라를 켜도 여기로 옮겨 합쳐진다.
- host_ed25519: 카메라의 호스트 키. 첫 접속 때 생긴다. 지우면 다음 접속 때 새로 만들고 PC 에서 known_hosts 경고가 난다.
- 공개키가 없으면 비밀번호 없이 root 로 들어올 수 있다 (텔넷과 같은 수준). 공개키를 넣으면 비밀번호 로그인은 막힌다.
접속: ssh root@<카메라 IP>, sftp root@<카메라 IP> (카드는 /mnt/mmc), scp 파일 root@<IP>:/mnt/mmc/
TXT
# SD 루트에 둔 공개키 거두기
for f in /mnt/mmc/authorized_keys /mnt/mmc/*.pub; do
  [ -f "$f" ] || continue
  grep -E '^(ssh-|ecdsa-|sk-)' "$f" >> "$CONF/authorized_keys" && rm -f "$f"
done
sync
OPTS="-F -E -R -p 22 -D $CONF -K 60"
if [ -s "$CONF/authorized_keys" ]; then OPTS="$OPTS -s"; AUTH="공개키 $(grep -c -E '^(ssh-|ecdsa-|sk-)' "$CONF/authorized_keys")개"
else OPTS="$OPTS -B"; AUTH="공개키 없음, 비밀번호 없이 허용"; fi
"$D/bin/dropbearmulti" dropbear $OPTS >> "$D/log/ssh.log" 2>&1 < /dev/null &
echo $! > /tmp/nx500ex-ssh.pid
sleep 1
if [ -d /proc/$(cat /tmp/nx500ex-ssh.pid) ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') ssh start ip=$(wifi_ip) pid=$(cat /tmp/nx500ex-ssh.pid) $AUTH" >> "$D/log/boot.log"; sync
  case "$0" in */auto/*) ;; *) popup "SSH 켜짐 (포트 22)<br>$AUTH" 3 ;; esac
else
  echo "$(date '+%Y-%m-%d %H:%M:%S') ssh failed: $(tail -n 2 "$D/log/ssh.log" | tr '\n' ' ')" >> "$D/log/boot.log"; sync
  popup "SSH 시작 실패<br>log/ssh.log 확인" 4
fi
exit 0
