# 펌웨어 분석: 블루투스와 SD 언마운트의 실제 동작 (2026-10-19)

공식 펌웨어 NX500_FW_v1.12.zip (nxfiles.nx.tc) 의 루트 파일시스템을 PC 에서 풀어 확인했다. 카메라의 /usr/sbin/bluetoothd 체크섬(759569816 332440)이 펌웨어 파일과 같으므로 카메라 루트는 공식 1.12 그대로다.

추출 방법: ge0rg 의 samsung-nx-hacks/tools/slp-firmware.py 로 SLP 컨테이너를 10개 조각으로 분리, chunk-06 (lzop) 을 풀면 ext4 rootfs (534MB), debugfs rdump 로 파일 추출.

## 1. 블루투스 켜기와 끄기

| 단계 | 근거 파일 | 동작 |
| --- | --- | --- |
| 관리자 | /usr/share/dbus-1/services/org.projectx.bt_core.service | D-Bus 요청이 오면 /usr/bin/bt-core 가 뜬다 |
| 켤 때 | bt-core 가 `/usr/etc/bluetooth/bt-stack-up.sh &` 실행 | 칩 등록(bt-dev-start-m8887.sh), 확인 후 `/usr/sbin/bluetoothd -d`, 이어서 wms.service 시작 |
| 끌 때 | bt-core 가 `bt-dev-end.sh &`, `bt-stack-down.sh &` 실행 | hci0 down, rfkill block, 드라이버 rmmod, 그리고 `killall bluetoothd` |
| 초기화 | bt-reset-env.sh | stack-down, 페어링 정보 삭제 |
| org.bluez D-Bus 서비스 | Exec=/bin/false | 실제로는 아무것도 띄우지 않음. bluetoothd 는 stack-up 스크립트가 띄운다 |

실기 기록(래퍼가 전원 ON 과 블루투스 ON 때마다 불림)과 합치면, bt-core 는 전원 ON(블루투스 설정이 켜져 있을 때)과 블루투스 ON 때 stack-up 을 실행한다.

## 2. 이전 래퍼 방식의 부작용

bt-stack-down.sh 는 `killall bluetoothd` 로 이름이 정확히 bluetoothd 인 프로세스만 죽인다. 원본을 bluetoothd.orig 로 바꾸었기 때문에 진짜 데몬의 이름이 bluetoothd.orig 가 되어 블루투스를 꺼도 죽지 않았다. 실기 로그에서 PID 336 이 블루투스 OFF/ON, 전원 OFF/ON 을 거치며 계속 살아 있었던 이유다. 순정이라면 끌 때 죽고 켤 때 새로 뜬다. 다시 켤 때 래퍼가 띄운 새 사본은 이미 떠 있는 336 때문에 곧 끝났다.

즉 bluetoothd 이름을 바꾸는 방식은 블루투스 수명 관리를 순정과 다르게 만든다. NX-KS 도 같은 방식이었고, NX-KS 래퍼는 아예 원본을 실행하지 않아 블루투스가 동작하지 않았다.

## 3. 바꾼 설계: bt-stack-up.sh 를 감싼다

- /usr/etc/bluetooth/bt-stack-up.sh 를 bt-stack-up.sh.orig 로 이름만 바꾸고, 같은 자리에 원본을 먼저 실행한 뒤 SD 의 boot.sh 를 띄우는 래퍼를 둔다.
- bluetoothd 바이너리와 이름은 그대로라 끌 때 killall 이 정상 동작한다. 블루투스 수명 관리가 순정과 같아진다.
- 훅이 불리는 시점은 같다 (전원 ON, 블루투스 ON). bluetoothd 를 띄우는 곳이 stack-up 뿐이었기 때문이다.
- 순정 bt-stack-up.sh: 1205 바이트, cksum 1579358536, mtime 2014-09-13 03:06:52 UTC.

## 4. 전원 OFF 때 SD 위의 프로세스

/usr/bin/deviced 의 문자열에서 확인한 SD 언마운트 절차

1. SD 를 쓰는 앱에 알림 ("notify to other app who already access sdcard")
2. /sbin/fuser 로 SD 를 붙잡은 프로세스를 찾아 SIGTERM ("kill app with SIGTERM")
3. 남아 있으면 SIGKILL
4. 강제 언마운트 ("execute force unmount!")

SD 에서 실행된 keyscan, 감시 스크립트가 전원 OFF 마다 종료되는 이유다. 기록을 남기는 스크립트는 SIGTERM 을 받을 때 정리할 수 있다.

## 5. 아직 설명되지 않은 것

첫 측정에서 블루투스 OFF 직후 조합키가 한 번 반응하지 않은 현상. bt-stack-down 은 keyscan 을 건드리지 않고 (이름이 다름), deviced 의 SD 처리는 언마운트 때만 일어난다. 이 분석으로도 설명되지 않는다. 다음 후보는 SD 접근 순간 오류이며, 재현 시 감시 기록으로 확인한다.
