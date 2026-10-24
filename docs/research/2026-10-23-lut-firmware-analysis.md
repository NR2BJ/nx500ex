# 색 처리 표(톤 커브, 색 행렬, 3D LUT)를 실행 중에 바꾸는 방법: 펌웨어 분석 (2026-10-23)

목적: 화면 마법사(전역 7가지 값)로 못 내는 필름 특성(색별 변화, 톤 곡선, 토닝)을 위해, 펌웨어를 다시 굽지 않고 색 처리 표를 바꾸는 경로를 찾는다.
자료: NX500 1.12 공식 펌웨어 (NX500_v1.12.bin 을 나눈 조각, rootfs, 카메라 앱, st 명령, 커널) 와 상류 문서 (ottokiksmaler/nx500_nx1_modding 등). 카메라에서는 아직 실행하지 않았다.

## 1. 펌웨어 구성

| 조각 | 내용 |
| --- | --- |
| chunk-05 (약 12MB) | 이미지 처리 RTOS (ARM). 기준 주소 0x80000000. 색 처리 코드는 모두 여기에 있다. 리눅스 쪽(di-camera-app, libcapture-fw-prod.so)에는 LUT, 감마 코드가 없다 |
| chunk-07 | /opt (ext4). pref_adj_iq.bin 은 ISO 게인, AWB 게인 같은 공장 보정값뿐 |
| chunk-09 | 스왑, 하이버네이션 스냅샷 |
| chunk-04 | Cortex-M4 펌웨어 |
| chunk-00, 02, 03 | 리눅스 커널 |

RTOS 는 리눅스 파일시스템의 파일을 읽고 쓸 수 있다 (CCapAdjIf 경유 fopen, 메시지 0xaa06). RTOS 안에 "/mnt/mmc/oic_table/oic_%s.bin", "mnt/mmc/IPC_%04d.raw" 같은 경로가 있다.

## 2. 방법 A: IPC 디버그 파라미터 로더 (JPEG 톤 커브, 색 행렬)

삼성의 디버그용 기능. st 명령으로 켜면, 정지 사진 처리 때마다 SD 폴더의 txt 파일을 읽어 처리 레지스터에 바로 쓴다. RAM 에만 반영되고 끄거나 재부팅하면 원래대로.

명령 (RTOS 명령 처리 0x80385904, 코드에서 도출):

| 명령 | 뜻 |
| --- | --- |
| st cap iq ipc proc sysinfo | 읽기 전용. 대비, 채도, 3D LUT, smart art 상태 |
| st cap iq ipc proc debug | 현재 디버그 설정 |
| st cap iq ipc proc debug mode load / save / off | 파일에서 읽기(2) / RAW 저장(1) / 끔(0) |
| st cap iq ipc proc debug path param <폴더> | 읽을 폴더 (mnt/mmc/<폴더>) |
| st cap iq ipc proc debug path raw <파일> | RAW 대체 (비우면 평소 RAW) |

읽는 파일과 키 (0x803856ac, 형식 해석 0x803c5a10):

| 파일 | 키 | 비고 |
| --- | --- | --- |
| gamma.txt | GAMMA_INDEX (프리셋 번호) 또는 TC_LOW_ANCHOR_X00..X21, Y00..Y21 (22점 톤 커브) | 보간해 15비트 값으로 씀. 기본 곡선 최대값 0x3fff 라 14비트로 추정 |
| color.txt | CC_RGBL_MAT_00..22, CC_RGBH_MAT_00..22 (3x3 두 개), R2Y_MAT_00..22, SE_MAT_00..11 | 값은 11비트 필드. 빠진 키는 쓰레기 값이 되므로 전부 넣어야 함 |
| wb.txt | WB_OFFSET_RR/GR/GB/BB, WB_GAIN2_RR/GR/GB/BB | |
| lcac.txt, cfai.txt, wbee.txt, sra.txt | 색수차, 보간 등 | 필름 레시피와 무관 |

파일 형식: "키 값" 쌍, 구분자는 공백, 탭, 쉼표, =, 줄바꿈. 값은 10진 정수(부호 허용). 쌍은 최대 100개이고 개수 검사가 없어 넘으면 RTOS 메모리가 넘친다 (반드시 100개 이하).

적용 범위: 정지 사진 경로(CBackend_Ipc_Still, CS_Still)만 이 설정을 읽는다. 라이브 뷰용 파라미터에는 걸리지 않아 화면에는 안 보이고 JPEG 에만 반영될 것으로 본다 (추정).

모르는 것: "mnt/mmc/..." 상대 경로가 /mnt/mmc 로 풀리는지, 행렬의 고정소수점 배율(1.0 = 256? 512?), 톤 커브 값 범위, IPC 모드 번호의 뜻.

필름 레시피에 주는 것: 22점 톤 커브(들뜬 블랙, 하이라이트 롤오프, 필름 특성 곡선), 3x3 색 행렬 두 개(어두운 쪽과 밝은 쪽을 다르게 하면 스플릿 토닝에 가까운 효과 가능성, 색 사이 섞기). 색별 선택 채도는 3D LUT 가 필요하다.

## 3. 방법 B: 3D LUT 뱅크 (라이브 뷰와 JPEG)

- 처리 단계: CBackend_3dlut_View, CBackend_3dlut_Still, 정지 사진 처리 단계 "RECIPE PAGE 3DLUT".
- RAM 0x810c3500 ~ 0x8118db00 에 LUT 뱅크가 0x4d00 간격으로 있다 (0x4d00 은 17x17x17 x 4바이트를 256바이트 단위로 맞춘 크기와 맞음, 추정).
- 뱅크 고르기: 고정 4개 (0x803837d0: 0x810fd100, 0x81101e00, 0x81106b00, 0x81115200), 밝기와 색온도에 따라 고르는 함수 (라이브 뷰 0x80383800, 정지 사진 0x80382b30).
- 적재: 라이브 뷰 _load (0x8011e20c) 가 고른 주소를 d5_ep_3dl_load_lut 에 넘겨 DMA 로 처리 블록에 올린다. 뱅크를 실행 중에 다시 쓰는 코드는 없어 보인다.
- RTOS 는 가상 주소 = 물리 주소. 리눅스 커널은 0x86000000 이후라 겹치지 않는다. 리눅스에서 /dev/mem 으로 읽고 쓸 수 있을 가능성 (st 의 readl, writel, dump 와 busybox devmem).
- 모르는 것: 지금 모드가 어느 뱅크를 쓰는지, 캐시 일관성, 다시 적재되는 시점. 항목 형식은 덤프 분석으로 밝혔다 (docs/research/2026-10-25-lut-dump-analysis.md: YCbCr, 8비트 x 3 + 0, 42개 표가 두 구간).

## 4. 그 밖

- 화면 전용 감마 (DRM drime5_drm_crtc_load_lut, Xorg drmModeCrtcSetGamma): LCD 에만, 사진에는 영향 없음.
- 스마트 필터 (SelectiveColor, Miniature, Vignetting, WaterColor, FishEye), 동영상 감마 (STANDARD, GAMMA_D, GAMMA_V) 는 순정 설정.

## 5. 카메라 시험 순서 (텔넷)

방법 A
1. 읽기: `st cap iq ipc proc`, `st cap iq ipc proc sysinfo`, `st cap iq ipc proc debug`
2. 파일 입출력 확인: `st cap iq ipc proc debug mode save` 후 한 장, /mnt/mmc/IPC_0000.raw 가 생기는지, `st cap iq ipc proc debug mode off`
3. 가장 작은 쓰기: /mnt/mmc/t1/gamma.txt 에 `GAMMA_INDEX 0` 한 줄, `debug path param t1`, `debug mode load`, 한 장, `debug mode off`. 그다음 다른 번호로 변화 확인
4. 22점 톤 커브: 기본에 가까운 곡선부터
5. color.txt: 모든 키를 넣고 단위 행렬, 배율 후보 하나씩

방법 B (방법 A 확인 뒤)
1. 읽기: `busybox devmem 0x810fd100 32` 로 읽히는지, 뱅크 범위를 SD 로 덤프해 뱅크별 비교, 모드 재진입 뒤 다시 덤프
2. 같은 값 다시 쓰기로 쓰기 가능 여부
3. 뱅크 하나를 다른 뱅크 내용으로 바꾸고 `st app mode m`, 색 변화 확인, 덤프로 복구

분석 산출물(주석 단 디스어셈블, 키 목록)은 저장소 밖 작업 폴더에 있다. 필요하면 키 목록만 tools/film 으로 옮긴다.
