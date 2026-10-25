# 키 주입 경로와 벌브 (2026-10-26)

30초를 넘는 벌브를 위해 셔터 버튼을 스크립트로 "진짜로" 누르는 방법을 찾은 기록. 결론: 셔터 버튼의 GPIO 선을 레지스터로 직접 눌렀다 떼면 물리 버튼과 같다.

## 1. 세 가지 주입 경로와 결과

| 경로 | 방법 | 커널 키 드라이버 (d5-keys) | evdev (nxkeys, X) | 카메라 앱 | 벌브 |
| --- | --- | --- | --- | --- | --- |
| st key | `st key push/release/click <키>` (카메라 자체 명령, 앱 안에서 처리) | 모름 | 안 보임 (nxwake 로 확인) | 키로 동작함 (재생 진입 등) | 눌림은 되나 떼기가 벌브를 못 끝냄. prefman 으로 BULB 를 쓰면 30초 장노출 |
| evdev 쓰기 | /dev/input/event0, event1 에 input_event 를 write (bin/nxkey) | 모름 (하드웨어 상태 아님) | 보임 (nxwake 가 key 183 수신) | 반응 없음 (재생 진입 안 됨, xinput test 에도 안 찍힘) | 안 됨 |
| GPIO | 버튼 선을 출력 0 으로 (bin/nxgpio) | 인터럽트로 눌림/뗌 기록, pushed_keys 에 비트 | 보임 (key 125) | 물리 버튼과 같음: 반셔터, 촬영, 벌브 | 40초 벌브가 EXIF 40.0초 |

카메라 앱은 벌브 중에 드라이버에 버튼 상태를 묻는다. 커널 로그 (event_log=1) 에 `[d5-keys] [button_press_check] button_name : shutter2_key ... result : released` 가 2초마다 찍힌다. 그래서 하드웨어 상태가 "눌림" 이어야 벌브가 이어진다.

## 2. 하드웨어

- 키 드라이버: /sys/devices/platform/d5-keys (dial_mode, dial_drive, pushed_keys, check_push_key, event_log, keymask, keycode, keydesc ...). pushed_keys 는 GPIO 상태 비트 (반셔터 0x800, 셔터 0x1000).
- 입력 장치: event0 "Drime5 GPIO Keyboard" (S1 125, S2 126, AEL 156, MOBILE 215 등), event1 "Drime5 ADC Keyboard" (십자, OK, MENU, FN, EV, DEL, PB, 모드 다이얼 위치). Xorg 가 둘 다 열고 있다.
- GPIO (/sys/kernel/debug/gpio): shutter1_key = gpio-59, shutter2_key = gpio-27, ael = gpio-31, power_key = gpio-58, wifi = gpio-19, jog1 = gpio-114/115, jog2 = gpio-110/111. 모두 입력, 풀업 (눌림 = 0).
- GPIO 블록은 8선씩 ARM PL061 식. gpio3 (gpio-24~31) 레지스터 0x10003000, gpio7 (gpio-56~63) 0x10020000 (/sys/devices/gpioN/resource). DATA 는 주소 마스크 (base + (1<<선)*4), DIR 은 base+0x400 (1 = 출력), AFSEL base+0x420.
- 누름 = DIR 비트를 1 로 바꾼 뒤 그 선의 DATA 를 0 으로. 뗌 = DIR 비트를 0 으로 (입력, 풀업). DATA 를 먼저 쓰고 DIR 을 바꾸면 반영되지 않았다. 출력 1 은 쓰지 않는다 (버튼을 동시에 누르면 전원과 GND 가 맞붙음).

## 3. 셔터 값과 BULB

- prefman 0xa340 의 셔터 idx (1스톱 = 16, 1초 = 0, 1/50 ≈ 91, BULB = -96) 를 직접 쓰고 `st app mode m` 으로 다시 들어가면 값은 바뀌지만 앱은 BULB 를 30초 장노출로 다룬다 (GPIO 로 40초 눌러도 EXIF 30.0초).
- `st key jog jog1_ccw` (앞 다이얼 반시계) 를 1/3스톱씩 돌려 idx 가 -96 이 되면 화면에 Bulb 와 스톱워치 (00' 00") 가 뜨고 진짜 벌브가 된다. 1/50 에서 BULB 까지 27번 (약 10초, 화면에서 한 칸씩 도는 것이 보임). common.sh 의 jog_shutter_to.
- 빠른 길: prefman 으로 30초 (-80) 를 쓰고 `st app mode m` 으로 다시 들어간 뒤 다이얼 한 클릭이면 바로 BULB. 복귀는 반대로 BULB 에서 한 클릭 (30초) 뒤 prefman 으로 원래 값 (BULB 상태에서는 prefman 쓰기가 안 먹음). bulb.sh 가 이 방식.
- 노출 시작 판정: 셔터를 누른 뒤 라이브 뷰 버퍼 4곳 (nxmem 으로 첫 두 줄 1440 바이트) 이 0.4초 간격으로 같으면 노출이 시작된 것 (셔터 뒤 0.5초 안에 마지막 프레임이 쓰이고 그 뒤 멈춤). AF 가 못 잡으면 S2 를 눌러도 라이브 뷰가 계속 움직인다. common.sh 의 lv_moving (비교는 busybox md5sum, cmp 는 작업 환경에 없음).
- 장노출 노이즈 제거가 켜져 있으면 노출 시간만큼 더 걸린 뒤 파일이 생긴다.

## 4. 도구

- bin/nxgpio (tools/nxgpio): `nxgpio <블록 주소> <선> press|release|read`.
- bin/nxkey (tools/nxkey): evdev 쓰기. 카메라 앱에는 안 먹히지만 우리 nxkeys/nxwake 시험에 쓴다.
- bin/nxwake (tools/nxwake): 키가 눌릴 때까지 기다림 (화면 끄기).
- common.sh: hw_s1, hw_s2, hw_release_all, jog_shutter_to. scripts/bulb.sh 가 쓴다.

## 5. 벌브 중단과 시험 때 헷갈린 것

- 벌브 중 아무 키나 누르면 끝내는 감시는 nxwake 를 누르기 전에 띄워 두고 우리 키 (125, 126) 를 NXWAKE_IGNORE 로 무시한다. 입력 장치를 새로 여는 것은 GPIO 로 누른 셔터에 영향이 없다 (누른 채 열어도 DIR 비트 그대로).
- 시험 중 "벌브가 1초 만에 끝난다" 고 보였던 것은 카메라 문제가 아니었다. bulb.sh 는 시작까지 약 6초 (드라이브, BULB 전환, 반셔터) 가 걸리는데 시험 키를 시작 10초 뒤에 넣어 실제로는 셔터를 누른 지 2초 만에 중단시킨 것이었고, 노출은 셔터 뒤 약 1.5초에 시작하므로 EXIF 1.0초가 됐다. 사용자 조작도, 키 잡음도 없었다 (드라이버 로그와 nxwake 기록으로 확인). 20, 30, 60초 벌브와 2.6초 중단 모두 정상.

## 6. 주의

- GPIO 를 누른 채 스크립트가 죽으면 버튼이 눌린 채로 남는다. 모든 스크립트는 trap 으로 release 한다. 전원을 껐다 켜도 레지스터는 초기화된다.
- 블랙아웃 (화면 끄기) 창이 떠 있어도 재생 키 (st key pb) 와 GPIO 셔터는 들어간다. 그러나 다이얼 클릭 (st key jog) 은 검은 창이 떠 있는 동안 먹지 않았다 (실기: 창 걷은 뒤 바로 됨). 그래서 bulb.sh 는 BULB 전환이 안 되면 "화면 끄기 중이면 먼저 걷으세요" 라고 알린다. 한때 촬영이 안 됐던 원인은 검은 창이 아니라 카메라가 몇 cm 앞을 보고 있어 AF 가 못 잡았거나 재생 화면 등 다른 상태였던 것으로 보인다. 확실치 않은 추정은 적지 않는다.
