# 인계 메모 (2026-10-24, 클라우드 세션 -> 로컬 세션)

레포 문서에 없는 것만 적는다. 기능 설명은 README.md, sd/nx500ex/README.md, 계획은 docs/plan/roadmap.md, 실기 기록은 docs/research/ 를 본다.

## 1. 작업 디렉터리 상태

- 브랜치 claude/dazzling-thompson-hikteq, 마지막 커밋 c8734c1 (nxmem). 커밋 안 된 변경 없음 (2026-10-24 확인). PR 은 만들지 않기로 함.
- 클라우드 세션의 작업 폴더(scratchpad)는 세션이 끝나면 사라진다. 거기 있던 것과 다시 만드는 법은 5장.

## 2. 지금 하던 작업: 3D LUT (방법 B), 첫 카메라 시험 대기

배경 문서: docs/research/2026-10-23-lut-firmware-analysis.md (방법 A, B 의 근거와 주소).

가설
- 이미지 처리 RTOS (펌웨어 chunk-05, 기준 주소 0x80000000, 가상 = 물리 주소) 메모리 0x810c3500 ~ 0x8118db00 에 3D LUT 뱅크가 0x4d00 간격으로 약 42개 있다.
- 0x4d00 = 17x17x17 항목 x 4바이트(19,652)를 256바이트 단위로 올린 크기 -> 17^3 표, 항목당 4바이트로 추정. 항목 안의 배치(RGB 인지 YCbCr 인지, 순서, 비트)는 모름.
- 고정 뱅크 4개 (선택 함수 0x803837d0): 0x810fd100, 0x81101e00, 0x81106b00, 0x81115200.
- 밝기(Bv)와 색온도로 뱅크를 고르는 함수: 라이브 뷰 0x80383800, 정지 사진 0x80382b30.
- 라이브 뷰 적재: _load 0x8011e20c -> d5_ep_3dl_load_lut (0x80179314 -> 0x804a5c44, 인자 테이블 0..2, 색 형식 0..1), DMA 로 처리 블록 SRAM 에 올림.
- 뱅크를 실행 중에 다시 쓰는 코드는 못 찾음 -> 뱅크는 부팅 때 채워지는 고정 데이터일 것. 덮어쓰고 모드 재진입(st app mode m)이나 반셔터로 다시 적재되면 색이 바뀔 것 (추정).
- 리눅스 커널은 0x86000000 이후라 /dev/mem 으로 이 영역을 읽고 쓸 수 있을 것 (미확인).

첫 시험 (사용자에게 안내했고 결과 대기 중). 모두 읽기만 한다. M 모드, 텔넷:
```
N=/mnt/mmc/nx500ex/bin/nxmem      # 새 바이너리, SD 에 아직 안 옮겼을 수 있음
st cap iq ipc proc sysinfo         # 대비, 채도, 3D LUT 상태 출력 기대 (방법 A 의 읽기 전용 명령)
$N x 0x810fd100 16
$N r 0x810c3500 0xcf300 /mnt/mmc/lut_a.bin     # 뱅크 영역 전체 + 한 칸 (약 830KB)
st app mode m; sleep 2
$N r 0x810c3500 0xcf300 /mnt/mmc/lut_b.bin
# Fn 에서 화면 마법사 비비드, WB 3200K 로 바꾼 뒤
$N r 0x810c3500 0xcf300 /mnt/mmc/lut_c.bin
# 화면 마법사, WB 원래대로
```
결과를 받으면 할 분석
1. a, b, c 가 같은지 (뱅크가 고정 데이터인지).
2. 0x4d00 단위로 잘라 뱅크별 해시, 비슷한 뱅크 묶기. 항목 4바이트를 여러 해석(R,G,B,pad / 10비트 묶음 등)으로 읽어 격자 순서대로 단조 증가하는 해석 찾기 -> 형식 확정.
3. 형식이 나오면 PC 에서 뱅크를 .cube 로 풀어 렌더링해 보고, 어떤 뱅크가 어떤 화면 마법사나 상황용인지 추정.

그다음 순서 (사용자 결정: 방법 B 로 우리 나름대로)
1. 쓰기 가능 확인: 뱅크 하나의 항목 하나를 같은 값으로 다시 쓰기.
2. 지금 쓰이는 뱅크 찾기: 의심 뱅크를 다른 뱅크 내용으로 바꾸고 st app mode m 또는 반셔터 -> 화면, 사진 색이 바뀌는지. 덤프로 복구 (nxmem w).
3. 우리 표 넣기: 항등 표, 눈에 띄는 표(세피아 등) -> 화면과 JPEG 둘 다 반영되는지, 라이브 뷰 경로와 정지 사진 경로가 따로인지 확인.
4. 도구: .cube -> 뱅크 형식 변환기(PC, 카메라), 적용, 해제 스크립트, 부팅 때 다시 적용 (전원을 끄면 사라질 것), 메뉴.
5. 필름 레시피를 "LUT + 선명도 + WB" 로 옮기고 보정 촬영, 비교 촬영 도구로 검증. 화면 마법사 레시피는 대체로 남김.

주의
- nxmem 은 4바이트 단위로만 접근한다. 처음 읽기에서 카메라가 멈추면 전원을 껐다 켜고 접근 방식을 바꾼다 (O_SYNC 빼기, 작은 범위 등).
- 쓰기는 반드시 덤프를 먼저 뜬 뒤. 잘못 쓰면 카메라가 멈출 수 있으나 재부팅으로 복구 (RAM 만 바뀜).
- 방법 A (st cap iq ipc proc debug, SD 의 gamma.txt, color.txt) 는 사용자가 "굳이 할 필요 없다" 고 해 보류. 쓰게 되면: 파일 하나에 키-값 쌍 100개 이하 (넘으면 RTOS 메모리 넘침), color.txt 는 키를 빠짐없이.

## 3. 클린룸 원칙 (사용자 결정)

- WApaperplane (NXWA, 지금 이름 metol) 과 nx500-filmsim 을 더는 참고하지 않는다. 레포 출처에도 넣지 않는다 (필름 레시피 출처에서 이미 뺌, tools/filmlab -> tools/film, FilmLab 이름 안 씀).
- 3D LUT 는 우리 덤프와 펌웨어 분석만으로 밝히고, 문서에도 그 근거만 적는다.
- 클라우드 세션은 WA 의 LUT 방식 세부를 이미 봤다. 로컬 세션은 WA 저장소를 열지 말 것. 조사 기록 문서(2026-10-17 survey, 2026-10-18 catalog, stage1-test 일부)의 NXWA 언급은 당시 조사 기록이라 그대로 둠.
- 레포의 prefman 위치, varlist 출처는 상류 ottokiksmaler 문서(Prefman_tool.md, ST_CAP_CAPDTM.md)로 적음. varlist 값 환산식은 실기로 맞춘 것으로 적음.

## 4. 카메라 실기에서 확인한 사실 중 문서에 없거나 흩어진 것

- 필름 레시피 적용: prefman 쓰기 + st app mode m 으로 1~2초 안에 화면 마법사, WB 모두 반영. 값만 쓰면 반영 안 됨. 키 주입(Fn, 터치, OK)은 느려서 버림.
- 보정 촬영과 비교 촬영은 장당 약 5.5초. 손으로 들고 찍어도 같은 레시피의 회색 a/b 가 0.5, 채도 비가 0.02 안에서 재현됨.
- 순정 다중 노출: SMART 모드에만 있음, 5장까지, JPEG 만, 셔터, 조리개, 감도 조절 불가 (2026-10-23 사용자 확인). P/A/S/M 에서 켜는 시험(st cap capdtm setusr MULTIEXPOSURE MULTIEXPOSURE_ON)은 안 해 봄.
- WiFi: 전원을 끄기 전에 켜 둬도 다시 켜면 꺼져 있음.
- 재생 화면 묶기: 다음 전원 켜기부터 보임 (인터벌로 RAW, RAW+JPEG, JPEG 확인). HDR, 스태킹은 같은 코드라 될 것으로 보지만 실기 확인은 인터벌만.
- nxkeys: EV 두 번(메뉴)은 매일 쓰며 동작. 길게 누르기, 두 번 누르기의 키 설정 실기 확인은 기록이 없음 (로드맵에 "실기 확인 대기").
- 사용자가 SD 에 옮긴 상태: 필름 레시피 41개(최신 recipes.txt, SX-70 B 93 포함), 촬영 도구 메뉴, rshot, series, calib 는 카메라에서 돌려 봄. bin/nxmem 은 아직 안 옮겼을 수 있음.

## 5. 클라우드 작업 폴더에 있던 것 (사라짐)

- 펌웨어 추출본: NX500_v1.12.bin (nxfiles.nx.tc), ge0rg/samsung-nx-hacks 의 tools/slp-firmware.py 로 10조각 분리, chunk-06 을 lzop -d 로 풀면 ext4 rootfs, debugfs -R "rdump / out" 으로 파일 추출. 빌드의 ROOT 와 펌웨어 분석에 필요.
- LUT 펌웨어 분석 산출물: chunk-05 주석 디스어셈블(objdump -b binary -m arm --adjust-vma=0x80000000), 문자열 목록, IPC 디버그 키 목록. 주소는 2장과 분석 문서에 다 옮겼다. 다시 필요하면 위 방법으로 재생성.
- 모의 시험 환경(mock): st, prefman, key, reapply_mode, shoot 를 셸 함수로 흉내 낸 가짜 common.sh 와 상태 파일 폴더. 스크립트를 /mnt/mmc/DCIM 경로만 바꿔 복사해 PC 에서 돌림. 필요하면 다시 만든다 (prefman get/set 을 파일로, st cap capdtm varlist 를 저장된 값으로 출력하는 정도).
- 사진 받는 법: 사용자가 cp.nr2bj.com/share/<id>/ 링크를 줌. `curl "<링크>?ls"` 가 파일 목록 JSON, `curl -o SAM_xxxx.JPG "<링크>SAM_xxxx.JPG"` 로 받음. jobs.log 는 대화에 첨부.
- 분석: python3 tools/film/recipe_analyze.py <사진 폴더> <jobs.log> [--scene], calib_analyze.py 도 같음 (numpy, Pillow 필요).

## 6. 크로스 컴파일 환경

- 클라우드는 Ubuntu 24.04, gcc-arm-linux-gnueabi 13.3 (apt), ROOT=펌웨어 rootfs. `ROOT=<rootfs> sh tools/nxmenu/build.sh` 가 sd/nx500ex/bin/ 에 nxmenu, nxpopup, nxkeys, nxgroup, nxmem 을 만든다.
- build.sh 는 Ubuntu 의 arm-linux-gnueabi-* 이름과 GNU ld 를 가정한다. Mac 의 clang 으로는 안 된다. Mac 에서는 Docker 가 가장 간단: `docker run --rm -v "$PWD":/w -v <rootfs>:/root_fs -w /w ubuntu:24.04 sh -c "apt-get update && apt-get install -y gcc-arm-linux-gnueabi && ROOT=/root_fs sh tools/nxmenu/build.sh"` (Apple Silicon 에서 arm64 이미지에 gcc-arm-linux-gnueabi 패키지가 없으면 --platform linux/amd64 로. 시험 안 해 봄).
- 링크는 rootfs 의 glibc 2.13 과 EFL 라이브러리로 한다 (-nodefaultlibs). 빌드 뒤 카메라 glibc 에 없는 심볼 버전이 있으면 build.sh 가 실패시킨다. -U_TIME_BITS -U_FILE_OFFSET_BITS 필수 (Ubuntu 기본 64비트 time).
- glibc 2.13 에는 fstat 심볼이 없음 (__fxstat). nxmem 은 fseek/ftell 로 바꿈.
- rootfs 추출에는 lzop, e2fsprogs(debugfs) 필요 (Mac 은 brew install lzop e2fsprogs).

## 7. 실패한 시도와 이유

- 화면 마법사 토닝(세피아, 셀레늄): 게인이 채도보다 먼저 적용돼 채도를 낮추면 게인 색도 같이 빠짐. 채도 0 이면 게인 무시. 레시피에서 뺌.
- 흑백 컬러 필터 효과(R, B 게인): 흑백에서 작동 안 함.
- 키 주입으로 화면 마법사, WB 설정: 느리고 불안정 -> prefman + 모드 재진입.
- st cap capdtm setusr INTERVAL: Invalid argument (외부 변경 거부). 재생 목록 즉시 갱신 방법 없음.
- 순정 스크린샷(save_screen_enable.txt + EV+OK): 동작 안 함.
- 펌웨어 분석 중 chunk-05 의 데이터 표를 통째로 출력하려던 시도가 안전 필터에 막힘. 같은 방식으로 다시 하지 말 것 (필요한 값만 뽑아 요약).

## 8. 사용자가 내린 결정

- 응답은 한국어만. 문서에 볼드 금지, 일본식 괄호 금지, 괄호는 () 만. 단계적으로 구체적으로.
- PR 만들지 않음. 커밋은 이 브랜치에.
- 필름 레시피: 41개로 마무리, 더 추가하지 않음. WB 는 필름 밸런스 고정 (주광 5500K, 텅스텐 3200K, 흑백과 스타일 5500K). CineStill, Eterna 3200K 유지 여부는 실제 장면 확인 때 판단. 실제 장면 확인은 나중에.
- 다음 큰 작업은 3D LUT, 방법 B, WA 참고 없이.
- 다중 노출은 나중.
- 레포 출처에 WA 를 넣지 않음.

## 9. 다음 할 일 순서

1. 3D LUT 첫 시험 결과(lut_a/b/c.bin, sysinfo, x 출력) 받아 분석 -> 형식, 고정 여부 (2장).
2. 쓰기 시험, 쓰이는 뱅크 찾기, 우리 표 넣기.
3. LUT 도구와 메뉴, 레시피 LUT 화.
4. 그 뒤 로드맵 나중 할 일: 메뉴에서 WiFi 켜기, 제거기 실기, 다중 노출(P/A/S/M 시험), 체감 지연, 메뉴가 열린 동안의 키, 필름 레시피 실제 장면 확인, 웹 원격, SSH.
