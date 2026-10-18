# 단계 0 진단 결과 (2026-10-18 17:07)

sd/stage0-probe 를 사용자 카메라에서 실행한 결과다. 설정 백업(prefman/FullSave0~10)은 개인 설정이 들어 있을 수 있어 저장소에 올리지 않고 사용자 PC 에 보관한다.

## 요약

| 항목 | 값 | 의미 |
| --- | --- | --- |
| 펌웨어 | 1.12 (NX500GLU0APC1, DSP SR1, BABF43A) | 모든 기존 모드의 대상 버전과 일치 |
| 커널 | Linux 3.5.0, 2015-06-03 빌드, armv7l | |
| 셔터 횟수 | 894 | 기계 셔터 수명 대비 사실상 새것 |
| 전원 켠 횟수 | 354 | |
| 플래시 횟수 | 내장 0, 외장 0 | |
| 기존 모드 흔적 | 없음 | 아래 참고 |
| SD 카드 | 128GB exFAT, 103GB 여유 | |

## 기존 모드 흔적: 깨끗함

- /usr/sbin/bluetoothd 는 크기 332440 바이트, 날짜 2015-04-02 이다. 상류 문서에 기록된 원본 bluetoothd 크기와 정확히 같다. bluetoothd.orig 도 없다. 훅이 설치된 적이 없다.
- /opt/usr 에는 lost+found 만 있다. NX-KS(/opt/usr/nx-ks), nx-on-wake, devel 폴더 모두 없다.
- nx-on-wake 서비스 파일도 없다. 하이버네이션 이미지를 고친 적이 없다는 뜻이다.
- /usr/local/bin 에는 삼성 원본 테스트 프로그램 하나만 있다.

즉 카메라는 순정 상태이고, 이후 변경은 모두 이 프로젝트가 한 것으로 추적할 수 있다.

## 저장소

| 위치 | 크기 | 사용 | 여유 | 비고 |
| --- | --- | --- | --- | --- |
| / (루트, p10) | 507M | 480M | 23M | 읽기 전용 마운트. bluetoothd 래퍼 한 파일만 쓸 곳 |
| /opt (p11) | 74M | 33M | 41M | 앱 데이터 |
| /opt/usr (p14) | 2.3G | 97M | 2.1G | 내장 부품을 둘 곳. 펌웨어 재설치로 지워지지 않음 |
| SD (mmcblk1p1) | 117G | 15G | 103G | |
| /tmp 등 tmpfs | 250M | | | 메모리 위 임시 공간 |

파티션 크기는 NXWA 측정과 같다. eMMC 전체는 약 3.7GB 다.

## 메모리

부팅 39초 시점 factory mode 에서 MemTotal 500MB, MemFree 44MB, 스왑 없음(zram0 50MB 장치는 있음). 정상 모드에서는 NXWA 측정 기준 10MB 안팎까지 줄어든다. 상주 프로그램은 작게 유지해야 한다.

## 키 입력 장치

| 장치 | 이름 | 용도 |
| --- | --- | --- |
| event0 | Drime5 GPIO Keyboard | 상단 키 |
| event1 | Drime5 ADC Keyboard | 후면 키 |
| event2 | Melfas MMS100s Touchscreen | 터치 |

keyscan 이 쓰는 /dev/event0, /dev/event1 이 그대로 있다. 터치 이벤트는 event2 라 필요하면 따로 읽을 수 있다.

## 카메라에 있는 명령

| 있음 | 없음 |
| --- | --- |
| st, prefman, dfmstool, rtcwake, systemctl | busybox, telnetd, ftpd, tcpsvd, inetd, httpd, python, dropbear, ssh, strings |

telnet, FTP, 웹 서버를 쓰려면 busybox 를 직접 가져가야 한다. NX-KS 가 busybox 와 telnetd 바이너리를 동봉한 이유다. rtcwake 가 있으므로 Wake Lapse 는 추가 부품 없이 된다.

## 프로세스와 서비스

- di-camera-app 은 PID 247 로 동작한다. NX-KS 문서, NXWA 측정과 같은 번호다.
- 블루투스가 꺼진 상태라 bluetooth 관련 서비스는 목록에 없다. 훅을 쓰려면 카메라 설정에서 블루투스를 켜 두어야 한다.
- hibernation.service, hib_tmp.service, hib_post.path 가 있다. 전원 OFF 가 하이버네이션 구조라는 문서 내용과 일치한다.

## 촬영 설정 (실행 당시)

다이얼 M, AF 싱글, 기계 셔터, LCD 출력.

## 진단 스크립트 수정

bluetoothd 앞부분을 보려던 strings 명령이 카메라에 없어 실패했다. od 로 첫 4바이트를 보는 방식으로 고쳤다. 다른 항목은 모두 정상 수집됐다.
