/* nx500ex Dropbear 빌드 옵션 (src/default_options.h 를 덮어쓰는 값만).
 * 모든 경로를 SD 카드 (/mnt/mmc/nx500ex) 안으로 둔다. 카메라 플래시에는 아무것도 두지 않는다.
 * 호스트 키는 conf/ssh 에 (카드마다 한 번 만들어 유지), authorized_keys 는 실행 때 -D 로 conf/ssh 를 준다. */
#define DSS_PRIV_FILENAME "/mnt/mmc/nx500ex/conf/ssh/host_dss"
#define RSA_PRIV_FILENAME "/mnt/mmc/nx500ex/conf/ssh/host_rsa"
#define ECDSA_PRIV_FILENAME "/mnt/mmc/nx500ex/conf/ssh/host_ecdsa"
#define ED25519_PRIV_FILENAME "/mnt/mmc/nx500ex/conf/ssh/host_ed25519"
#define DROPBEAR_PIDFILE "/tmp/nx500ex-dropbear.pid"
/* SFTP 는 OpenSSH 의 sftp-server (bin/sftp-server, 상류 ssh-server 의 빌드) 를 쓴다 */
#define SFTPSERVER_PATH "/mnt/mmc/nx500ex/bin/sftp-server"
#define DROPBEAR_PATH_SSH_PROGRAM "/mnt/mmc/nx500ex/bin/dbclient"
#define DEFAULT_PATH "/mnt/mmc/nx500ex/bin:/usr/bin:/bin:/usr/sbin:/sbin"
/* 카메라는 root 하나뿐. DSS 는 끈다 (낡은 알고리즘), 나머지는 기본값 */
#define DROPBEAR_DSS 0
/* syslog 없음: -E 로 stderr 에 남기거나 조용히 */
#define DROPBEAR_SVR_PASSWORD_AUTH 1
#define INETD_MODE 0
/* /etc/shells 가 없을 때 허용할 셸 (root 의 셸이 bash 일 수 있음) */
#define COMPAT_USER_SHELLS "/bin/sh","/bin/bash","/bin/ash"
