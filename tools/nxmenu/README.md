# nxmenu

nx500ex 의 메뉴 프로그램. NX-KS mod_gui (ottokiksmaler/nx500_nx1_modding, AGPL-3.0) 의 화면 구성과 키 처리를 바탕으로 새로 작성했다. 화면 파일 형식은 nxmenu.c 머리말에 있다.

## mod_gui 대신 만든 이유 (2026-10-19 실기)

| mod_gui 증상 | 원인 | nxmenu |
| --- | --- | --- |
| 항목을 누르면 항상 닫힘 | 명령 실행 뒤 무조건 종료 | 체크박스, 화면 이동은 열린 채. 입력 창 항목은 숨겼다가 다시 보임 |
| 하위 화면에서 이전 화면이 비치고 뒤로/닫기 위치와 동작이 어긋남, 칸 크기가 다른 화면이 튀어나옴 | 같은 창의 표를 지우고 다시 그리며, 버튼 높이를 960 / 버튼 수 로 화면마다 바꿈 | 화면마다 창을 새로 만들고 지난 창을 지움. 모든 화면 2열 x 5행 고정, 마지막 행은 뒤로/닫기 |
| "< 뒤로" 가 빈칸 | 라벨을 EFL 마크업으로 해석해 < 를 태그 시작으로 봄 | < > & 를 바꿔 넣음 |
| 빠르게 화면을 옮기면 화면이 까매지고 멈춤 | 화면마다 mod_gui 를 새로 띄우던 방식(menu.sh)에서 12번째 실행 무렵부터 Xorg 가 화면 버퍼(720x480x4) 할당에 계속 실패 (dlog) | 한 프로세스, 창 하나에서 내용만 바꿈. 동시에 하나만 실행 |
| (nxmenu 첫 판) 메뉴를 열자 Xorg 가 죽고 화면이 다시 뜨기까지 오래 걸림 | 창이 화면 전체(720x480)를 덮어 창 관리자가 카메라 앱을 완전히 가려짐으로 보고 일시정지, 그때 카메라 앱의 화면 캡처 중 Xorg SIGSEGV (pixman) | 창 높이 470. 아래 10 픽셀은 카메라 화면이 보인다 |

## 빌드

필요: Ubuntu 의 gcc-arm-linux-gnueabi, NX500 1.12 펌웨어에서 추출한 루트 파일 시스템 (glibc 2.13, EFL 1.7.99). EFL 헤더 대신 efl_min.h 의 최소 선언을 쓰고, 펌웨어의 라이브러리와 직접 링크한다.

```
ROOT=/path/to/rootfs sh build.sh      # -> sd/nx500ex/bin/nxmenu, nxpopup, nxkeys, nxgroup, nxmem
```

nxgroup 은 화면 없는 파일 도구라 PC 에서도 그대로 빌드해 시험할 수 있다 (gcc -o nxgroup nxgroup.c; nxgroup -l 사진.SRW). 동작은 nxgroup.c 머리말.

build.sh 는 결과물이 카메라 glibc 에 없는 버전 심볼을 요구하면 실패한다.

## PC 에서 화면 시험

qemu-user 와 Xvfb 로 카메라의 라이브러리를 그대로 써서 그려 볼 수 있다 (popup_* 은 이 방식으로는 그려지지 않았다).

```
Xvfb :5 -screen 0 720x480x24 &
DISPLAY=:5 EVAS_FONT_DPI=72 ELM_PROFILE=mobile ELM_ENGINE=software_x11 qemu-arm -L $ROOT ./nxmenu <scripts 폴더> gui_ini &
xdotool mousemove 180 235 click 1       # 누르기
xwd -root -display :5 | convert xwd:- shot.png
```
