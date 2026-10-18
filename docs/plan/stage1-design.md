# 단계 1 설계안: 진입 훅, 내장 부품, SD 구조, 설치기

진단 결과(docs/research/2026-10-18-probe-result.md)를 바탕으로 한 설계안이다. 끝의 결정 항목에 답하면 구현에 들어간다.

## 1. 전체 구조

```
[카메라 내장]
/usr/sbin/bluetoothd            래퍼 (약 10줄 셸 스크립트)
/usr/sbin/bluetoothd.orig       삼성 원본 (332440 바이트, 이름만 바꿈)
/opt/usr/nx500ex/
    boot.sh                     래퍼가 부르는 시작 스크립트
    bin/                        keyscan, popup_timeout, popup_ok, popup_entry, poker, stapp, busybox
    VERSION

[SD 카드]
/mnt/mmc/nx500ex/
    scripts/                    키 조합 스크립트 (EV_OK.sh 등)
    scripts/auto/               켤 때마다 번호 순으로 실행 (10_silent.sh 등)
    menu/                       메뉴 정의 파일
    conf/                       설정값
    log/                        실행 기록
    DISABLE                     이 파일이 있으면 아무것도 실행하지 않음 (안전 모드)
```

## 2. 동작 순서

콜드 부팅 (배터리를 뺐다 끼운 뒤)

1. 카메라가 하이버네이션 이미지에서 복귀한다.
2. 블루투스가 켜져 있으면 systemd 가 bluetoothd 를 실행한다. 실제로는 우리 래퍼가 실행된다.
3. 래퍼는 boot.sh 를 백그라운드로 띄우고, 곧바로 원본 bluetoothd.orig 를 실행한다. 블루투스 기능은 그대로 유지된다.
4. boot.sh 는 SD 카드가 마운트될 때까지 최대 30초 기다린다. SD 에 nx500ex/scripts 가 없거나 DISABLE 파일이 있으면 아무것도 하지 않고 끝난다.
5. 있으면 내장의 keyscan 을 SD 의 scripts 폴더를 대상으로 실행한다. keyscan 은 scripts/auto/*.sh 를 번호 순으로 실행한다.

전원 스위치 OFF 후 ON (일상)

1. keyscan 은 내장에서 실행 중이라 OFF 중에도 메모리에 남아 있다.
2. ON 하면 keyscan 이 시간 점프를 감지하고 SD 마운트를 2초 기다린 뒤 auto/*.sh 를 다시 실행한다.
3. 무음 셔터처럼 매번 풀리는 설정이 여기서 재적용된다.

SD 카드를 빼면

- keyscan 은 스크립트를 찾지 못해 아무것도 하지 않는다. 카메라는 순정처럼 동작한다.
- 다른 카드를 넣고 켜면 그 카드의 스크립트가 적용된다.

## 3. 래퍼

```sh
#!/bin/sh
# nx500ex bluetoothd wrapper
[ -x /opt/usr/nx500ex/boot.sh ] && /opt/usr/nx500ex/boot.sh </dev/null >/dev/null 2>&1 &
exec /usr/sbin/bluetoothd.orig "$@"
```

- boot.sh 가 없거나 실패해도 원본 bluetoothd 는 항상 실행된다. 래퍼 자체가 문제를 일으킬 여지를 최소화한다.
- NX-KS 래퍼는 원본을 실행하지 않아 블루투스가 꺼졌고 별도 복원 기능이 필요했다. 이 설계에서는 그 문제가 없다.
- 루트 파일시스템에 쓰는 것은 이 파일 하나와 원본 이름 변경 하나뿐이다.

## 4. boot.sh 의 안전장치

- 중복 실행 방지: 블루투스를 껐다 켜면 래퍼가 다시 불린다. keyscan 이 이미 실행 중이면 다시 띄우지 않는다 (keyscan 자체의 잠금 파일도 있음).
- 녹화 중 보호: 영상 모드(hevc ON)면 끝날 때까지 기다린다. NX-KS init.sh 와 같은 방식.
- 안전 모드: SD 루트의 nx500ex/DISABLE 파일. 스크립트가 카메라를 멈추게 하는 경우, PC 에서 이 파일만 만들고 배터리를 뺐다 끼우면 된다.
- 기록: 실행 결과를 SD 의 nx500ex/log/ 에 남긴다. 카드가 없으면 /tmp 에 남긴다.

## 5. 설치기

SD 카드용 설치 패키지 (factory mode 로 한 번 실행)

```
info.tg
nx_cs.adj
nx500ex-install/install.sh
nx500ex-install/payload/        (내장에 들어갈 파일들)
```

install.sh 의 동작

1. /etc/version.info 가 NX500 과 1.12 가 아니면 중단.
2. bluetoothd 상태 확인
   - 원본(ELF, 332440 바이트)이고 bluetoothd.orig 가 없으면 설치 진행
   - 이미 우리 래퍼면 내장 부품만 갱신 (재설치)
   - 그 밖의 상태(NX-KS 래퍼 등)면 중단하고 화면에 알림
3. 루트를 읽기쓰기로 다시 마운트, bluetoothd 를 bluetoothd.orig 로 이름 변경, 래퍼 작성, sync, 읽기 전용으로 되돌림.
4. /opt/usr/nx500ex 에 부품 복사.
5. 각 단계 결과를 SD 의 로그에 기록하고 화면에 표시.
6. info.tg 를 info.tg.done 으로 바꿈.

NX-KS 설치기와 달리 두 번 실행해도 제거되지 않는다. 제거는 별도 패키지로 한다.

제거 패키지: bluetoothd.orig 를 bluetoothd 로 되돌리고 /opt/usr/nx500ex 를 지운다. 펌웨어 재설치로도 래퍼는 지워진다 (/opt/usr 의 파일은 남지만 아무것도 부르지 않으므로 무해).

## 6. 바이너리 조달

| 부품 | 출처 | 비고 |
| --- | --- | --- |
| keyscan, popup_*, poker, stapp | 상류 저장소 C 소스와 기존 바이너리 | 처음에는 기존 바이너리, 이후 소스에서 다시 빌드 |
| busybox | NX-KS 동봉본 (동적 링크) 또는 직접 빌드한 정적 바이너리 | telnet, FTP, 웹 서버에 필요 |
| telnetd | NX-KS 동봉본 (NX300 의 busybox, 정적) | 개발 통로 |
| mod_gui | 상류 소스 | 메뉴 결정에 따라 |

공개 배포 시 상류 코드는 AGPL-3.0 을 따른다. busybox 는 GPL-2.0 이다.

## 7. 첫 검증 순서

1. 설치 패키지 실행 후 래퍼 존재와 원본 보존을 진단 패키지로 확인.
2. SD 에 auto/10_hello.sh (AF 보조광 1초 켜기) 하나만 두고 콜드 부팅. 켤 때 불이 들어오면 경로 전체가 동작하는 것.
3. 전원 OFF/ON 반복 시 매번 불이 들어오는지 확인.
4. EV+반셔터에 같은 스크립트를 걸어 키 조합 확인.
5. DISABLE 파일로 안전 모드 확인.
6. 제거 패키지 실행 후 순정 복귀 확인.

여기까지 통과하면 단계 2 의 A 순위 기능을 하나씩 SD 스크립트로 추가한다.

## 8. 결정 항목

| 항목 | 선택지 | 권장 |
| --- | --- | --- |
| 래퍼가 원본 bluetoothd 실행 | 실행 / 실행 안 함 | 실행. 블루투스 기능 유지, 복원 기능 불필요 |
| 메뉴 | mod_gui 그대로 / 키 조합만 / 새로 작성 | 처음엔 mod_gui 그대로. 메뉴 파일은 SD 에 |
| 스크립트 위치 | 전부 SD / 내장 캐시 병행 | 전부 SD. 카드 없으면 순정 |
| 내장 폴더 이름 | /opt/usr/nx500ex | NX-KS 의 /opt/usr/nx-ks 와 겹치지 않게 |
| NX-KS 와 공존 | 허용 / 금지 | 금지. 설치기가 다른 래퍼를 발견하면 중단 |
| 블루투스 상시 ON | 필요 | 콜드 부팅 시 훅이 불리려면 카메라 설정에서 켜 두어야 함. 배터리 영향은 작다고 알려져 있으나 직접 확인 필요 |
