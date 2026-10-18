# nx500ex SD 패키지 (단계 2 첫 판)

이 폴더를 SD 카드 루트에 nx500ex 라는 이름 그대로 복사한다. 내장에는 stage1-install 로 래퍼(v2)가 설치되어 있어야 하고, 카메라 설정에서 블루투스를 켜 둔다.

## 동작 규칙

| 상황 | 동작 |
| --- | --- |
| 블루투스 켜짐 (전원 ON 포함) | 모드 시작. 켜 둔 기능(체크박스)을 다시 적용 |
| 블루투스 끔 | 2초 안에 모드 정지. 켜 둔 기능은 순정 상태로 되돌림 (체크 상태는 유지되어 다시 켜면 재적용) |
| 전원 OFF | 모드 정지 |
| nx500ex/DISABLE 파일 있음 | 아무것도 실행하지 않음 |
| nx500ex 폴더 없음 | 순정과 같음 |

## 키 조합

| 키 | 동작 |
| --- | --- |
| EV 두 번 | 메뉴 열기 / 닫기 |
| EV + 왼쪽 | AF-S/단사 와 AF-C/고속연사 전환 |
| EV + 오른쪽 | 터치스크린 켜기/끄기 |
| EV + 위 / 아래 | UP / DN 프로필 불러오기 |
| EV + WiFi | 텔넷/FTP 켜기 (이번 전원 동안만) |
| 비어 있음 | EV + 반셔터, EV + OK, EV + AEL, WiFi 두 번 등. scripts 에 EV_OK.sh 처럼 만들면 된다 |

EV 는 다른 키보다 먼저 누르고 있어야 한다.

## 메뉴

메뉴와 팝업은 영어다. 메뉴 프로그램(mod_gui)이 한글 폭을 계산하지 못해 라벨이 가운데 한 칸 폭만 보였다 (2026-10-19 실기).

| 항목 | 종류 | 내용 |
| --- | --- | --- |
| Self-Timer | 버튼 | 셀프타이머. 지금 드라이브 모드(브라케팅, 연사) 그대로 촬영. 화면 안내는 항상 표시 |
| Timer Delay | 버튼 | 타이머 시간 입력 (2~60초, 기본 5초). conf/timer_delay 에 저장 |
| Timer Lamp | 체크박스 | 타이머 동안 앞쪽 AF 보조광 깜빡임. 기본 켜짐 |
| Silent Shutter | 체크박스 | 완전 전자셔터. 단사 전용, 1/30 보다 느린 셔터 불가 |
| No Lens Release | 체크박스 | 렌즈 미인식 상태에서도 셔터 허용 |
| Profiles | 하위 메뉴 | UP/DN 저장, 불러오기, 설정 전체 백업, 복원 (복원 뒤 전원 꺼짐) |
| Shutter Count | 버튼 | 셔터, 전원, 플래시 횟수 표시 |
| Telnet / FTP | 체크박스 | 계속 켜 둠. 인증 없음, 본인 기기만 있는 네트워크에서만 |
| IP | 버튼 | 현재 WiFi IP 표시 |
| My Checkbox, My Button | 체크박스, 버튼 | nx500ex/user 의 스크립트 실행 (user/README.txt) |
| Debug Log | 체크박스 | 다음 블루투스 켜기부터 log/mon.log, log/keyscan.out 기록. 바로 다음 동작부터 log/timing.log 에 스크립트별 시작/끝 시각 기록 |
| Korean Test | 하위 메뉴 | 한글 라벨과 한글 팝업 표시 시험 (시험이 끝나면 없앤다) |
| CLOSE | 버튼 | |

체크박스를 켜면 그 스크립트가 scripts/auto 에 복사되어 켤 때마다 자동 적용된다. PC 에서 scripts/auto 를 보면 무엇이 켜져 있는지 알 수 있다.

## 폴더 구조

```
nx500ex/
  boot.sh              내장 래퍼가 부름
  bin/                 keyscan, mod_gui, popup_*, poker, stapp, busybox, telnetd, watch.sh, mon.sh
  scripts/             키 조합(EV_*.sh), 기능, 메뉴(gui_*.NX500), common.sh
  scripts/auto/        켜 둔 기능 (체크박스가 관리)
  user/                내 스크립트
  presets/             프로필과 전체 백업 (처음 저장할 때 생김)
  log/                 boot.log 등
```

## 바이너리 출처

| 파일 | 출처 | 라이선스 |
| --- | --- | --- |
| keyscan, popup_timeout, popup_ok, popup_entry, poker | Otto Kiksmaler, NX-KS 2.88 에 포함된 빌드 | AGPL-3.0 (상류 ottokiksmaler/nx500_nx1_modding) |
| mod_gui, stapp | ge0rg/nx-ks-mod 의 빌드 (IP 표시 지원) | AGPL-3.0 |
| busybox, telnetd | NX-KS 2.88 에 포함된 빌드 | GPL-2.0 |

## 첫 확인 순서

1. SD 의 기존 nx500ex 폴더(검증용)를 지우고 이 폴더를 복사한다.
2. 블루투스 켠 채로 전원 ON. 몇 초 뒤 EV 두 번으로 메뉴가 뜨는지, 한글이 깨지지 않는지 본다.
3. 메뉴의 각 항목을 한 번씩 눌러 본다. 무음 셔터를 체크하고 촬영해 셔터 소리가 없는지 확인한다.
4. 블루투스를 끄고 촬영해 셔터 소리가 돌아왔는지, 다시 켜고 무음이 되는지 확인한다.
5. 키 조합을 하나씩 확인한다.
6. 이상하면 메뉴에서 진단 기록을 켜고, 블루투스를 껐다 켠 뒤 다시 해 보고 log 폴더를 전달한다.

## 텔넷, FTP 접속

브라우저로는 접속되지 않는다 (웹 서버가 아님).

| 용도 | 방법 |
| --- | --- |
| 텔넷 | PuTTY 등 텔넷 프로그램. 연결 종류 Telnet, 주소 카메라 IP, 포트 23. 사용자 root, 비밀번호 없음 |
| FTP | 윈도우 탐색기 주소창에 ftp://카메라IP, 또는 FileZilla. SD 카드 내용이 보인다 |

카메라가 WiFi 기능 화면을 나오면 연결을 끊을 수 있다. 접속이 안 되면 WiFi 화면에 머문 채로 시도해 본다.

## 키 할당 바꾸기

지금 keyscan 이 인식하는 것은 EV 를 누른 채 다른 키를 누르는 순간, 같은 키 1초 안에 두 번, 모드 다이얼이 SAS 를 떠나는 순간뿐이다. 길게 누르기, 누르는 동안, 떼는 순간은 단계 3 의 keyscan2 에서 추가한다.

scripts 폴더의 파일 이름이 곧 키 할당이다. EV_<키>.sh (EV 를 누른 채 그 키), <키>_<키>.sh (같은 키 두 번) 형식이다.
키 이름: OK, AEL, UP, DOWN, LEFT, RIGHT, S1(반셔터), S2(셔터), MOBILE(WiFi), FN, DEL, PB(재생), EV.
예: 메뉴의 타이머를 EV+반셔터에 걸려면 scripts 에 EV_S1.sh 를 만들고 내용을 sh "$NX500EX/scripts/timer.sh" 한 줄로 한다.
