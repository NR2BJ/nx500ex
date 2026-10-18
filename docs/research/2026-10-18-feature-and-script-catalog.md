# NX500 모드 기능 및 스크립트 전수 카탈로그 (2026-10-18)

NX-KS 2.88 원본, ge0rg 수정본(nx-ks-mod), ge0rg 저장소에 올라온 미병합 PR, NXWA(WApaperplane) 최신본(2.88.0-nxwa.6, 커밋 d2c4c98), 그리고 상류 저장소에만 있는 도구까지 모두 한 곳에 모은 목록이다.
각 저장소를 직접 clone 해서 파일 단위로 확인했다. 로드맵을 만들 때 1장의 선택 칸에 표시하는 용도로 쓴다.

목차

1. 기능 카탈로그 (선택 칸 포함)
2. 스크립트와 바이너리 전수 목록
3. 진행 중이거나 계획만 있는 것
4. 이전 조사 문서 정정 사항

출처 약어

| 약어 | 의미 |
| --- | --- |
| KS | NX-KS 2.88 원본 (KinoSeed, 2017) |
| G | ge0rg/nx-ks-mod 의 추가/수정 (2025) |
| PR | ge0rg/nx-ks-mod 에 열려 있는 미병합 PR (fritzchentastig, 2025-05) |
| W | NXWA 추가/수정 (2026-08 ~ 현재) |
| U | 상류 ottokiksmaler/nx500_nx1_modding 에만 있고 NX-KS 에 포함되지 않은 것 |
| V | Vasile 의 nx-patch 5.3 에만 있던 것 |
| M | mewlips 별도 패키지 |
| E | 그 밖의 제작자 |

위험도 표기: 낮음은 설정값/프로세스만 다루고 배터리 분리로 원복되는 것, 중간은 실행 중 프로세스 메모리 패치나 /dev/mem 접근처럼 잘못되면 멈추는 것, 높음은 파티션/펌웨어/시스템 파일을 쓰는 것.

---

## 1. 기능 카탈로그

선택 칸은 비워 두었다. 원함, 보류, 불필요 등으로 채우면 된다.

### 1.1 사진 촬영과 노출

| 선택 | 기능 | 출처 | 진입 방법 | 구현 | 위험 | 비고 |
| --- | --- | --- | --- | --- | --- | --- |
|1 | 무음 전자셔터 | KS | 설정 > Silent Shutter (체크박스, 부팅마다 재적용) | rolling_shutter.sh: st cap capdtm setusr ADJUSTSHUTTERTYPE 0x750001 | 낮음 | NX500 전용. 단사만, 1/30 보다 느린 셔터 불가, ISO 6400 이상 화질 저하 |
|2 | HDR 5장 브라케팅 | KS | Custom Func. > HDR | 1HDR.sh: M 모드, MF 고정 후 셔터 속도 5단계(약 1/15~1/6000) prefman 로 바꿔가며 촬영 | 낮음 | 카메라 내장 브라케팅보다 범위가 넓음 |
|1 | 벌브 타이머 | G | Time-Lapse > Bulb | bulb_menu.sh 로 초 입력, bulb.sh 가 S1+S2 누른 상태 유지, LCD 블랙아웃, /tmp/stop.flag 로 중단 | 낮음 | 원본 2.88 의 Coming soon 자리. NXWA 에는 없음 |
|1 | 렌즈 미인식 상태 촬영 | KS | 설정 > No Lens Release | nolens.sh: prefman 0xc2dd(NX500) / 0x3071(NX1) = 1 | 낮음 | 접점 불량 렌즈, 어댑터 렌즈용 |
|2 | ZoomZoom (줌 버스트) | KS | Custom Func. > ZoomZoom | zoomzoom.sh: 지연 입력 후 촬영 시작과 동시에 파워줌을 wide 로 | 낮음 | 파워줌 렌즈 필요 |
|2 | 촬영 지연 셀프타이머 | U | 초기 sd.zip 의 EV+반셔터 | 약 10초 뒤 LED 깜빡이며 촬영, 브라케팅/연사 그대로 | 낮음 | NX-KS 에는 없음. 스크립트 몇 줄 |
|1 | AF-S/단사 와 AF-C/고속연사 토글 | U | 초기 sd.zip 의 EV 더블클릭 | st app nx capture 계열 | 낮음 | NX-KS 에는 없음 |
|3 | JPEG SuperFine 과 RAW 토글 | U | 초기 sd.zip 의 EV+AEL | capdtm 설정 | 낮음 | NX-KS 에는 없음 |
|1 | 진짜 백버튼 AF (BBAF) | U | keyscan bbaf 옵션 | keymask 로 반셔터 AF 차단 | 낮음 | 상류 문서에 "아직 제대로 안 됨". NX-KS 1.48~1.79 에 TBBAF 로 있다가 제거됨 |

### 1.2 포커스

| 선택 | 기능 | 출처 | 진입 방법 | 구현 | 위험 | 비고 |
| --- | --- | --- | --- | --- | --- | --- |
|2 | 포커스 풀 (두 지점 왕복) | KS | EV+반셔터 | EV_S1.sh: 저장 위치와 현재 위치 차이만큼 st cap iq af mv | 낮음 | 영상용. 속도는 Focus-Pull Speed |
|2 | 포커스 풀 속도 | KS | Focus+Profiles > Focus-Pull Speed | fpspeed.sh: 1~255 를 systemctl 환경변수 fps 에 저장 | 낮음 | |
|2 | 포커스 스태킹 | KS | Focus+Profiles > Focus Stacking | fstack.sh -> focus_stack 바이너리 (Near/Far 지정 후 Stack) | 낮음 | G 는 stapp 사용으로 교체, U 원본에 sweep 모드와 명령행 인자 있음 |
|3 | 포커스 위치 버튼 | KS | Focus+Profiles > Focus Buttons | focus_buttons 바이너리: 길게 눌러 저장, 짧게 눌러 복원 | 낮음 | 저장 파일이 /mnt/mmc/scripts/af_positions.txt 로 바이너리에 하드코딩. W 가 fbuttons.sh 로 폴더 생성 버그 수정 |
|3 | 부팅 시 마지막 포커스 복원 | KS | 설정 > Refocus on Boot | refocus.sh: /sdcard/presets/hib 값으로 이동 | 낮음 | Hibernate, Sleep, Wake Lapse 가 위치를 저장 |
|2 | 지속 피킹 (반셔터 놓으면 MF 어시스트 유지) | KS/U | keyscan peaking 옵션 + peak.sh | /tmp/peaking_on 플래그 | 낮음 | 2.88 에서는 메뉴에 없고 스크립트만 남음 |

### 1.3 동영상

| 선택 | 기능 | 출처 | 진입 방법 | 구현 | 위험 | 비고 |
| --- | --- | --- | --- | --- | --- | --- |
|3 | 비트레이트 변경 | KS | Custom Func. > Video Bitrates | br_set.sh, pokemon, pokemonche, gbr, poker: di-camera-app 메모리의 비트레이트 상수 패치. 슬롯 4K Pro/HQ, HD Pro/HQ, VGA HQ, 35~400 Mbps | 중간 | 부팅 기본값 Pro4K 160, ProHD 180, Hq4K 90, HqHD 90, HqVGA 180 (auto/a_init.sh). 펌웨어 1.12/1.41 고정 오프셋 |
|3 | 해상도 슬롯 바꿔치기 | KS | Custom Func. > Mod Resolutions | res_*.sh 와 resup: di-camera-app 코드의 해상도 상수 패치. DC/UHD/VGA 슬롯을 UHD/DC/2.5K/1080p 로 | 중간 | NX500 8종, NX1 6종(2.5K 없음). 이전 문서의 "NX500 전용"은 오류 |
|3 | 4K 15분 제한 우회 | KS | VGA 슬롯을 UHD 로 바꿔 촬영 | res_VGAUHD.sh | 중간 | NX500 은 UHD 15분 제한이 별도. V 의 nx-patch 는 이를 직접 제거했었음 |
|3 | 30분 녹화 제한 해제 | KS | 설정 > No Rec Limit | r-limit.sh: prefman 0xc2d9 / 0x306d = 1 | 낮음 | 70분 넘는 파일 문제 있다는 원본 경고. 해킹 없이 쓰는 U 의 nx_rec_limit_remover.zip 도 있음 |
|3 | 배치 녹화 (클립 자동 이어 찍기) | KS | Custom Func. > Batch Recording | brec.sh, brb.sh, blackout: 길이 입력 후 REC 누를 때까지 반복, 블랙아웃 선택 | 낮음 | 제한 시간보다 짧게 설정해야 함 |
|3 | 스텔스 녹화 | KS | EV+AEL | EV_AEL.sh: 터치 OFF, LCD/LED 끄고 10분 단위 배치 녹화 즉시 시작 | 낮음 | W 는 이 키를 FilmLab 으로 재할당, 원본은 EV_AEL.community.sh 로 보존 |
|3 | LCD 끈 채 녹화 | KS | 2.55 메뉴의 LCD-Off Rec (2.88 은 메뉴 제외) | nrec.sh | 낮음 | 스크립트만 잔존 |
|3 | 캠코더 모드 (반셔터=일시정지, 셔터=REC) | KS | Custom Func. > Camcorder Mode | camcorder_mode.sh -> shutter_to_rec | 낮음 | 짐벌 사용 시 유용 |
|3 | 셔터 키 임의 재지정 | U | 없음 | shutter_to_key ael rec 처럼 반셔터/전셔터를 원하는 키로 | 낮음 | 2019년 Otto 추가, NX-KS 에 미포함 |
|3 | 영상 파일 손상 전 자동 재시작 | U | 없음 | log_watcher | 낮음 | 상류에만 있음 |
|3 | 1080p 120fps (NX500, 실제로는 진짜 120 아님) | U | factory mode 스크립트 | sys_param movie size | 낮음 | 비트레이트 낮음 |
|3 | 2.5K 영상 (구형 방식) | U | factory mode 스크립트 | sys_param movie size 2560_1440_30p | 낮음 | 저비트레이트. 해상도 모드로 대체됨 |
|3 | NX500 UHD 15분, FHD 50/60p 25분 제한 제거 | V | nx-patch | 메모리 패치 | 중간 | NX-KS 에는 직접 제거 기능 없음 |
|2 | DEV 메뉴 상시 접근 | V | nx-patch | | 중간 | 키 조합은 여전히 필요 |

### 1.4 타임랩스와 예약 촬영

| 선택 | 기능 | 출처 | 진입 방법 | 구현 | 위험 | 비고 |
| --- | --- | --- | --- | --- | --- | --- |
|2 | Wake Lapse (예약 시작 타임랩스) | KS | Time-Lapse > Wake Lapse | wakelapse.sh + timelapse.tp: rtcwake -m mem 으로 잠들었다 깨어나 포커스 복원 후 촬영 | 낮음 | 영상 모드에서는 거부 |
|2 | Ramping (노출 램핑, 홀리그레일) | KS | Time-Lapse > Ramping | ramping.sh + ramplapse.tp + ramp/*.sh 7개 파라미터 | 낮음 | 수동 렌즈나 조리개 고정 권장 |
|2 | Mod Lapse (사진/영상 인터벌, EV Smooth) | KS/U | Time-Lapse > Mod Lapse | mod_lapse 바이너리 자체 GUI | 낮음 | 종료 후 전원 OFF, 블랙아웃 옵션 |
|2 | 전원 절약 기능 끄기/켜기 | U | factory mode 도구 | nx_power_save_disabler.zip | 낮음 | 장시간 타임랩스용 |

### 1.5 화면과 조작

| 선택 | 기능 | 출처 | 진입 방법 | 구현 | 위험 | 비고 |
| --- | --- | --- | --- | --- | --- | --- |
|1 | 모드 메뉴 (두 열 버튼) | KS | EV 더블클릭(NX500), EV+OK(NX1), 화면의 NX-KS 버튼 | loadgui.sh -> mod_gui + gui_*.NX500 | 낮음 | 최대 24버튼, 스크롤 없음, 누르면 닫힘 |
|1 | 메뉴에 IP 표시 | G/W | 메인 메뉴 IP 버튼 | G: 수정된 mod_gui 바이너리(소스 없음). W: gen_menu.sh 가 메뉴 파일을 매번 생성 | 낮음 | W 방식은 바이너리 수정 없음 |
|2 | 메뉴 속도 개선 | W | | fork 횟수 줄이기, 메뉴 캐시 | 낮음 | |
|2 | NXUI 대체 메뉴 (Nuklear) | W | EV+AEL, EV+WiFi, nxui.sh | nxui.arm (X11 직접, EFL 미사용) | 낮음 | 720x192 하단 필터 바, 720x336 메인 메뉴. 중국어 |
|2 | 화면 상단 NX-KS 버튼 | KS | 자동 | onscreen_ks, on_ks(PNG) | 낮음 | OFF menu-button 체크로 5초 뒤 숨김 |
|2 | 2.35:1 시네마 가이드 | KS | EV+OK (NX500) | onscreen_235 | 낮음 | |
|2 | PNG 오버레이 또는 3x3 그리드 | KS | 설정 > Overlay | ov.sh -> onscreen_ov, /sdcard/overlay.png | 낮음 | |
|2 | 터치스크린 ON/OFF | KS | EV+RIGHT | EV_RIGHT.sh: prefman 0xa690 토글 | 낮음 | |
|2 | 온스크린 가상 버튼 | U | 없음 | onscreen_key [라벨] [키] [좌표] | 낮음 | 화면에 REC 등 버튼 띄우기 |
|2 | LCD/EVF 제어 | U | 없음 | st app disp, st app bb lcd | 낮음 | |
|2 | 화면 스크린샷 | U/E | 없음 | Enable-Screenshot 문서, MultiNX 의 screenshot.sh | 낮음 | |
|2 | 사용자 정의 버튼/체크박스 | KS | Focus+Profiles > My Button / My Checkbox | /sdcard/mod/cButton.sh, cCheckbox.sh, off_cCheckbox.sh 호출 | 낮음 | SD 기반 확장 지점. 예제 CustomButtons-example.zip |
|2 | WiFi 키 더블클릭 동작 | W | WiFi 두 번 | MOBILE_MOBILE.sh (keyscan 의 같은 키 연타 규칙) | 낮음 | keyscan 이 EV 없이 같은 키 1초 내 연타도 인식한다는 사실을 W 가 문서화 |

### 1.6 프로필과 설정 관리

| 선택 | 기능 | 출처 | 진입 방법 | 구현 | 위험 | 비고 |
| --- | --- | --- | --- | --- | --- | --- |
|2 | UP/DOWN 프로필 저장/로드 | KS | EV+UP, EV+DOWN, 메뉴 | save_UP.sh 등: prefman save_file/load_file 블록 0, 두 사본 cksum 비교 | 낮음 | /sdcard/presets/ |
|1 | 전체 설정 백업/복원 | KS | Profiles > Save/Load FullBackup | FullSave.sh, FullLoad.sh: prefman 블록 0~10 | 낮음 | 로드 후 전원 OFF |
|2 | prefman 덤프 해석기 | G(U에 커밋) | PC | prefmandumpread.py + NX500 필드 정의 | 없음 | 설정 오프셋 찾기용 |
|2 | 펌웨어 업데이트 알림 메시지 조작 | G(U에 커밋) | 수동 | prefman 0x5ce6, 0x746c | 낮음 | 재미 요소 |
|1 | 셔터 횟수/전원 횟수 조회 | U | factory mode 도구 | nxinfo.zip | 없음 | |

### 1.7 전원과 시스템

| 선택 | 기능 | 출처 | 진입 방법 | 구현 | 위험 | 비고 |
| --- | --- | --- | --- | --- | --- | --- |
|3 | Hibernate | KS | 메인 메뉴 | hibernate.sh: 포커스 저장, 렌즈 전원 OFF, systemctl hybrid-sleep | 낮음 | PR 에서는 "더 이상 필요 없다"며 메뉴에서 제거 제안 |
|3 | Sleep (아무 키로 복귀) | KS | EV+LEFT | sleep.sh: LCD OFF, 12분 후 렌즈 전원 OFF | 낮음 | |
|2 | 블루투스 복원 | KS | 설정 > Enable Bluetooth | bt.sh: bluetoothd.orig 실행 | 낮음 | NX-KS 래퍼가 원본 bluetoothd 를 실행하지 않기 때문에 필요 |
|3 | 128MB 스왑 | KS | 2.55 메뉴 (2.88 은 제외) | swap.sh: /opt/usr/home/swapmod | 낮음 | eMMC 마모 |
|2 | CPU performance 모드 | KS | 스크립트만 | performance.sh | 낮음 | |
|1 | 설치/제거 | KS/W | SD 루트 install.sh, 설정 > Uninstall | install.sh, uninstall.sh. W 는 증분 동기화 설치기, uninstall_direct.sh, update_nxrc.sh | 높음(rootfs 1파일) | 원본 install.sh 는 두 번 실행하면 제거됨 |
|2 | 설치 직후 telnet/ftp 자동 기동 | W | 자동 | onboard.sh | 낮음 | 디버깅 경로 확보용 |

### 1.8 네트워크와 원격

| 선택 | 기능 | 출처 | 진입 방법 | 구현 | 위험 | 비고 |
| --- | --- | --- | --- | --- | --- | --- |
|2 | telnet + FTP | KS | EV+MOBILE | EV_MOBILE.sh: telnetd, busybox ftpd(21, SD 루트), WiFi 끊기면 종료 | 낮음 | 인증 없음. W 가 원본의 멈춤 버그 수정, 메뉴에서 토글(telnet_toggle.sh) |
|1 | 웹 원격 제어 (라이브뷰, 키 입력, 갤러리) | KS+M | 메인 메뉴 Remote Ctr | nx-rc.sh -> nx-remote-controller-daemon, xdotool, nx-input-injector, web_root | 낮음 | 2.56 부터 내장. G 의 fork 에 AP 모드 IP 대응 수정 |
|2 | 웹 갤러리 개선 | W | Remote Ctr | thumb-cgi, dirlist-cgi, prewarm-cgi(8080), 썸네일 캐시 | 낮음 | 실시간 디렉터리, 접이식 폴더 |
|2 | 웹 촬영 파라미터 API | W | 8080 | capdtm-cgi, capdtm-httpd.sh | 낮음 | |
|2 | WiFi 로 웹 프런트 푸시 | W | PC 에서 | push.sh, push-cgi | 낮음 | 개발용 |
|2 | 원격 저장 (SMB/SFTP 마운트) | KS+M | Custom Func. > Remote Save | rem*.sh -> nx-netfs/remote_storage.sh | 낮음 | nx-netfs 별도 설치 필요 |
|2 | SSH/SFTP/SCP 서버 | G(U에 커밋) | 자동 | Dropbear 2020.81, init.sh 에 dropbear -R 추가 | 낮음 | 공개키 인증. rsync 바이너리는 상류에 있음 |
|2 | WiFi AP 모드 (카메라가 공유기 역할) | PR | 메인 메뉴 WiFi Access Point | apstart.sh, off_apstart.sh, hostapd/udhcpd 설정. SSID NX500-AP | 낮음 | 미병합. 클라이언트 모드 복귀는 재부팅 필요 |
|2 | 이메일/SNS 업로드를 자기 서버로 | G(별도) | 카메라 순정 공유 메뉴 | samsung-nx-emailservice (서버 쪽 Flask) + DNS 리다이렉트 | 없음 | 카메라 개조 불필요. Mastodon 게시, 디렉터리 저장 |
|2 | PTP 모드 | U | 스크립트 | Enable-PTP 문서 | 낮음 | |
|3 | 카메라 내 브라우저 | U | telnet 에서 browser | | 낮음 | |
|2 | 여러 대 동기 제어 | E | PC/Android 앱 | MultiNX (ajavamind), telnet+HTTP | 낮음 | 순수 factory mode SD 패키지 |

### 1.9 색과 필름 시뮬레이션

| 선택 | 기능 | 출처 | 진입 방법 | 구현 | 위험 | 비고 |
| --- | --- | --- | --- | --- | --- | --- |
|1 | FilmLab 필름 레시피 (68종) | W | EV+AEL, NXUI | filmlab.sh, recipes.json: Picture Wizard 7차원을 CUSTOM 슬롯에 기록 | 낮음 | 순정 펌웨어에서는 화면 마법사에서 사용자1 확인 한 번 필요 |
|2 | 레시피 7차원 즉시 반영 | W | | pwsend.arm + A2 펌웨어 | 높음 | p7 파티션에 dd. 범위 밖 권장 |
|1 | 3D LUT 실시간 교체 | W | EV+WiFi, LUT 패널, lut.sh | /dev/mem 으로 등록표 4바이트 + 빈 슬롯 A18 에 표 기록, 반셔터로 반영. 뷰와 결과물 각각 지정 가능 | 중간 | 2026-10-18 공개. 재부팅 시 원복 |
|2 | .cube 변환기 (카메라 내) | W | lut.sh | cube2lut.arm | 없음 | |
|1 | 내장 4종 LUT 전환, LUT 진단 | W | nx-rc 메뉴 | 3dlut_set.sh, 3dlut_stat.sh, iqr_dump.sh 등 | 중간 | 실험용 |
|2 | 사용자1/2/3 이름을 레시피 이름으로 | W | 순정 메뉴 | m2_locale.sh: .mo 파일 bind-mount | 중간 | 실험 단계 |
|2 | 미공개 NX-KS3 LUT 파일 | KS | 없음 | VirtualDi_NX-KS3.cube (mbriney 보존) | | 이를 쓰는 스크립트는 없음 |

### 1.10 개발과 진단 도구

| 선택 | 기능 | 출처 | 구현 | 비고 |
| --- | --- | --- | --- | --- |
|1 | 팝업 메시지/확인/입력 | KS/U | popup_timeout, popup_ok, popup_entry | 스크립트 UI 의 기본 부품 |
|1 | 키 이벤트 감지와 실행 | KS/U | keyscan | 2. 장 참고 |
|1 | 프로세스 메모리/파일 읽기쓰기 | KS/U | poker, poker2 | |
|2 | st app 명령 고속 전송 | G(U에 커밋) | stapp | st 호출 지연 회피 |
|2 | 모델 판별 | U/V | nx-model | |
|2 | 공유 라이브러리 함수 직접 호출 | U | nxcalldyn | prefman 함수 테스트 등 |
|2 | gdb 원격 디버깅 | U | Running-gdb 문서 | |
|2 | PNG 버튼 | U | button_png | KinoSeed 작성 |
|2 | di-camera-app 정적 분석 스크립트 | W | discovery/t1~t5 (Python) | PC 용 |
|2 | di-camera-app 명령 브리지 | W | f.sh, dicam/*.sh | st app film 명령 추가. 실험 단계, restart 시 멈춤 경고 |
|2 | p7 백업/검증/플래시 | W | p7_*.sh | 높음. 범위 밖 |

---

## 2. 스크립트와 바이너리 전수 목록

NX-KS 2.88 패키지는 SD 루트에 install.sh, info.tg, nx_cs.adj, NX-KS2_readme.odt 와 scripts/ 폴더(141개 항목, auto/ 와 ramp/ 하위 12개)로 구성된다. 설치 후 /opt/usr/nx-ks/ 에 복사된다.

### 2.1 NX-KS 2.88 (기능 묶음별)

| 묶음 | 파일 |
| --- | --- |
| 설치와 진입 | install.sh, info.tg, nx_cs.adj (SD 루트), init.sh, auto/a_init.sh, init_auto.tp, loader.sh, uninstall.sh, ver.sh, reboot.sh |
| 메뉴 | loadgui.sh, menu.sh, gui_exit.sh, gui_ini.NX500/NX1, gui_tl.*, gui_func.*, gui_focus.*, gui_profiles.*, gui_settings.*, gui_res.*, gui_br.tp, gui_br_NX1.tp, gui_ramp_ov.tp, br_menu.sh, z_button.sh, off_z_button.sh |
| 키 조합 | EV_EV.sh, EV_OK.sh, EV_AEL.sh, EV_UP.sh, EV_DOWN.sh, EV_LEFT.sh, EV_RIGHT.sh, EV_S1.sh, EV_MOBILE.sh (NX1 설치 시 EV_EV.sh 가 EV_OK.sh 로 바뀜) |
| 비트레이트 | br_set.sh, br_current.sh, br_up.sh, gbr, pokemon, pokemonche |
| 해상도 | resup, res_DCUHD/UHDDC/DC2K/UHD2K/DCHD/UHDHD/VGADC/VGAUHD/VGA2K/HDUHD.sh 와 각각의 off_ 짝 (20개) |
| 녹화 | r-limit.sh, off_r-limit.sh, brec.sh, brb.sh, nrec.sh, camcorder_mode.sh, off_camcorder_mode.sh, zoomzoom.sh |
| 타임랩스 | wakelapse.sh, timelapse.tp, ramping.sh, ramplapse.tp, ramp/init.sh, ramp/set_duration.sh, set_time-gap.sh, set_exp_start.sh, set_exp_end.sh, set_ramp_start.sh, set_ramp_length.sh, set_delay_start.sh |
| 사진 | 1HDR.sh, rolling_shutter.sh, off_rolling_shutter.sh, nolens.sh, off_nolens.sh |
| 포커스 | fstack.sh, fpspeed.sh, refocus.sh, off_refocus.sh, peak.sh, off_peak.sh |
| 프로필 | save_UP.sh, save_DOWN.sh, FullSave.sh, FullLoad.sh, FullSaveNX1.sh, FullLoadNX1.sh |
| 화면 | ov.sh, off_ov.sh, on_ks (PNG 이미지) |
| 전원 | hibernate.sh, sleep.sh, performance.sh, off_performance.sh, swap.sh, off_swap.sh, bt.sh, off_bt.sh |
| 네트워크 | nx-rc.sh, off_nx-rc.sh, nx-rc/ (데몬, xdotool, xev-nx, nx-input-injector, ImageMagick convert, 공유 라이브러리 23개, web_root), rem.sh, rem_set.sh, rem_start.sh, off_rem.sh, remote.cfg |
| 사용자 훅 | cButton.sh, cCheckbox.sh, off_cCheckbox.sh |

바이너리 21개와 소스 위치

| 바이너리 | 역할 | C 소스 |
| --- | --- | --- |
| keyscan | 키 감지, auto/*.sh 실행, 절전 복귀 감지 | 상류 keyscan.c |
| mod_gui | 메뉴 | 상류 mod_gui/mod_gui.c (G 수정본은 소스 없음) |
| popup_timeout, popup_ok, popup_entry | 팝업 | 상류 |
| poker | 메모리/파일 패치 | 상류 poker.c |
| poker2 | 변형 | 없음 |
| focus_stack, focus_buttons | 포커스 | 상류 |
| mod_lapse | 타임랩스 | 상류 |
| shutter_to_rec | 캠코더 모드 | 상류 |
| stapp | st app 고속 | 상류 (G 작성) |
| onscreen_ks, onscreen_235, onscreen_ov, onscreen_rc | 화면 오버레이 | 없음 (상류 onscreen_key.c 가 원형으로 추정) |
| rem_gui | Remote Save 입력 화면 | 없음 |
| blackout | 화면 블랙아웃 | 없음 |
| busybox, telnetd | 서버 | 공개 프로젝트 |

### 2.2 ge0rg 가 추가/수정한 파일

| 파일 | 변경 |
| --- | --- |
| bulb.sh, bulb_menu.sh, stop.sh | 신규 (벌브 타이머) |
| gui_tl.NX500, gui_tl.NX1 | Coming soon 을 Bulb 로 교체 |
| gui_ini.NX500, gui_ini.NX1 | CANCEL, IP 버튼 추가 |
| mod_gui | IP 표시 지원 바이너리 (소스 미공개) |
| focus_stack | stapp 사용 |
| init.sh | MODEL 환경변수, PATH 에 /opt/usr/nx-ks 추가 |
| install.sh | 따옴표 버그 수정 |
| 약 25개 스크립트 | 버전 검사를 MODEL 변수 비교로 교체 (기능 변화 없음) |

### 2.3 미병합 PR (fritzchentastig, ge0rg/nx-ks-mod PR 1)

| 파일 | 내용 |
| --- | --- |
| scripts/apstart.sh, off_apstart.sh | WiFi AP 시작/중지 (wlan.sh softap, hostapd, udhcpd) |
| ap/hostapd_uap.conf, udhcp_uap.conf | AP 설정 |
| gui_ini.NX500 | Hibernate 를 WiFi Access Point 체크박스로 교체 |
| nx-rc/nx-remote-controller-daemon | ge0rg 가 AP 모드 IP 를 읽도록 고친 버전 (ge0rg/nx-remote-controller-mod 커밋 765d562) |

ge0rg 가 리뷰 의견 7개를 남겼고 작성자가 반영했으나 2025-05-25 이후 승인/병합되지 않았다.

### 2.4 NXWA 가 추가한 파일

| 묶음 | 파일 |
| --- | --- |
| 설치/유지 | install.sh (증분 동기화로 재작성), onboard.sh, uninstall_direct.sh, update_nxrc.sh, gen_menu.sh, gui_tpl.NX500/NX1, telnet_toggle.sh |
| FilmLab | filmlab.sh, filmlab/recipes.json, filmlab_page.sh, gui_filmlab*.NX500 (5개), pwsend.arm, EV_AEL.community.sh (원본 보존) |
| NXUI | nxui.sh, nxui/nxui.arm, NUKLEAR-LICENSE |
| LUT | lut.sh, lut/cube2lut.arm, nx_regtabdump.arm, nx_regtabwrite.arm, nx_slotwrite.arm |
| 포커스 | fbuttons.sh |
| 앱 브리지 (실험) | f.sh, dicam/ 7개 (dicam_patch_install/rollback/status, dicam_p5_install/rollback, m2_locale.sh, t2_premount.sh) |
| 분석 (PC) | discovery/t1_strings.py ~ t5_st3dlutparam.py |
| nx-rc 확장 | thumb/ (thumb-cgi, dirlist-cgi, prewarm-cgi, thumb-prewarm.sh, thumb-install.sh), push/ (push.sh, push-cgi, push-install.sh), capdtm/ (capdtm-cgi.sh, capdtm-httpd.sh, capdtm-api, capdtm.conf), EV_MOBILE.sh 재작성, MOBILE_MOBILE.sh, EV_FLAB.sh, EV_FLAB_GUI.sh, flab_ui.sh, flab-verify.sh, flab-wifi.sh |
| LUT/ISP 실험 | 3dlut_ch.sh, 3dlut_set.sh, 3dlut_stat.sh, iqr_dump.sh, lut_help.sh, lut_pick.sh, lut_scan.sh, lutapi_help.sh, lutapi_probe.sh, gui_lutimport.NX500 |
| p7 펌웨어 | p7_backup.sh, p7_checkimg.sh, p7_flash_slp.sh, p7_install_ui.sh, p7_recover_official.sh, p7_restore_baseline.sh, p7_status.sh, p7_verify.sh, gui_p7*.NX500 (5개) |

NXWA 는 2.88 의 기존 파일 60여 개도 수정했다(속도 개선, 경로 정리, 메뉴 중국어화). ge0rg 의 bulb.sh, bulb_menu.sh, stop.sh 는 없고 gui_tl 의 "即将推出"(Coming soon) 자리가 그대로 비어 있다. 메뉴의 LUT 滤镜(LUT 필터) 항목이 Custom Func. 에 추가되었다.

### 2.5 상류에만 있는 도구 (NX-KS 미포함)

shutter_to_key, log_watcher, onscreen_key, button_png, nx-model, nxcalldyn, prefmandumpread.py, ssh-server/, rsync, tools/*.zip (nxinfo, nx_rec_limit_remover, nx_power_save_disabler/enabler, nx500silent, install_lapse), nx-on-wake/, video-bitrate-mods/nx-patch*, SD-card-mod-running-mods/ (BT 훅 설치/제거), downgrade_to_nx1000_FW (NX1000 용).

---

## 3. 진행 중이거나 계획만 있는 것

### 3.1 ge0rg

| 항목 | 상태 |
| --- | --- |
| NX-KS3.x 공개 | README 의 목표 선언뿐. 2025-09-01 이후 커밋 없음 |
| 누락된 중간 버전(2.08~2.87) ZIP 확보 시 이력 재생성 | README 에 예고. 이 때문에 "fork 하기 어렵다"고 경고 |
| 라이선스 정리 | 원본 라이선스 불명확하다고만 기재 |
| PR 1 (WiFi AP) 병합 | 리뷰 반영 후 대기 상태 |
| mod_gui IP 표시 수정의 소스 공개 | 미공개 |

### 3.2 fritzchentastig (PR 작성자, NX300M 커펌 제작자)

| 항목 | 상태 |
| --- | --- |
| WiFi AP 모드 | PR 대기. NX1 은 미검증으로 메뉴 비활성 |
| AP 에서 클라이언트 모드로 재부팅 없이 복귀 | 미해결 |
| "무선 기능의 기반" 확장 | PR 에 향후 계획으로만 언급 |

### 3.3 NXWA (2026-10-16 TASKFLOW, NATIVE_UI_ROADMAP, LUT_ROADMAP 기준)

| 항목 | 내용 | 상태 |
| --- | --- | --- |
| 순정 UI 통합 M1~M4 | FilmLab 을 삼성 순정 메뉴(화면 마법사) 안으로. M1 순정 진입, M2 사용자1/2/3 에 레시피 매핑과 이름 표시, M3 순정 화면에서 한 번 확인으로 적용, M4 순정 목록에서 레시피 탐색 | 2026-10-16 레이블 1개 교체 실기 성공. 나머지 UI-R1~R7 진행 중 |
| .mo 로 사용자 슬롯 이름 변경 | m2_locale.sh | 실기 대기 |
| st app film 명령 브리지 | di-camera-app 바이너리 패치를 bind-mount | 실기 대기, restart 금지 경고 |
| OSD 아이콘 교체 | 순정 화면에 보이는 변화 | 샘플 준비 |
| LUT C1 | p7 이미지의 정적 LUT 풀을 바꾼 펌웨어 패키지 | 오프라인 설계 |
| LUT C2 | st cap mem 디버그 채널로 런타임 풀 쓰기 | 검증 전 |
| LUT C3 | p7 미세 패치로 LUT 기록기 추가 (장기 주선) | 설계 |
| LUT 결과물 반영 | 10-18 실시간 교체로 뷰/결과물 각각 지정 성공 | nxwa.6 에 포함 |
| 사용자 2/3 슬롯 독립 저장 확인 | U6 실험 | 대기 |
| 화면 마법사 메뉴 이름 변경 여부 | D1 결정 대기 | |
| KinoSeed 라이선스 확인 | 발표 전 필수로 표기 | 미해결 |
| ge0rg 연락 | Q5 결정 보류 | 미해결 |
| samsung-nx-hacks 유지보수 인수 | 제안만 | 미실행 |

### 3.4 상류 TODO (2016~2019, 미해결 그대로)

자동 백업, 추가 커널 모듈, 암호화 촬영, USB 오디오, 영상 샤프닝/노이즈 감소 제거, NX500 영상 감마/LUT, 무크롭 4K, 1080p/720p 고프레임, 전 센서 영상. SSH 와 무음 셔터, 녹화 제한 해제는 완료로 체크되어 있다.

### 3.5 그 밖

| 출처 | 항목 |
| --- | --- |
| dvdkon (NX300 계열) | 설정 가능한 조작, Immich 업로드, 라이브뷰 위젯, 전자셔터, 하이라이트 측광, RAW 영상, JPEG 노이즈 감소 약화, 센서 크롭. NX500 과 플랫폼이 달라 아이디어 참고용 |
| mewlips | 원격 컨트롤러 Android 앱 (TODO 로 끝남) |
| Vasile | "다른 프레임워크로 UI 재작성" 예고 후 중단 |

---

## 4. 이전 조사 문서 정정 사항

- 해상도 모드는 NX500 전용이 아니다. NX1 도 gui_res.NX1 에 6종(2.5K 제외)이 있다.
- ge0rg 의 nx-ks-mod 변경은 약 170줄이며 대부분 버전 검사 정리다. 실질 신기능은 벌브 타이머 하나다.
- NXWA 는 ge0rg 의 nx-ks-mod 를 알고 있다(2026-10-08 내부 문서). 코드는 가져오지 않았다.
- NXWA 의 LUT 관련 결론은 2026-10-18 에 다시 바뀌었다. /dev/mem 쓰기와 결과물 LUT 반영이 가능하다고 정정했다.
