# JPEG 처리 변수와 영상 기능 조사 (2026-10-29)

목적: (1) 화면 마법사와 3D LUT 말고 JPEG 결과에 영향을 주는 변수 찾기, (2) 영상 기능을 다시 넣을 때 무엇이 있고 무엇을 새로 만들 만한지.
방법: (1) NX500 1.12 공식 펌웨어 chunk-05 (RTOS) 의 strings 와 문자열 참조만 봄. 카메라 실행 없음. (2) 상류 레포와 포럼 자료 조사.

## 1. JPEG 처리 변수

### 1.1 IPC 디버그 로더가 읽는 파일 (키 이름은 strings 에서 직접 봄, 뜻은 추정)

로더가 여는 txt 는 7개뿐. NR 용 txt 는 없다.

| 파일 | 키 | 뜻 (추정) |
| --- | --- | --- |
| gamma.txt | GAMMA_INDEX, TC_LOW_ANCHOR_X00..21, Y00..21 | 22점 톤 커브 |
| color.txt | CC_RGBL_MAT, CC_RGBH_MAT (3x3 두 개), R2Y_MAT 3x3, SE_MAT_00, 01, 10, 11 | 어두운 쪽과 밝은 쪽 색 행렬, RGB 에서 YCbCr, SE 는 CbCr 2x2 (색상 회전, 채도) |
| wb.txt | WB_OFFSET_RR/GR/GB/BB, WB_GAIN2_RR/GR/GB/BB | 채널별 오프셋, 두 번째 게인 |
| wbee.txt | EE_GAIN_GS/GH/GD/WS/WH/WD, EE_CORING_LV_H/W, EE_BALANCE_P/M, EE_S/D_LIMIT_*, EE_DETAIL_S/D_00..05, EE_CORING_LV_S/D_00..07, EE_GAMMA_COMP_00..18 (81개) | 선명화 전체: 세기, 코어링, 밝은 쪽과 어두운 쪽 테두리, 밝기별 세기 곡선 |
| cfai.txt | CMNyq, CMMEDIAN, CMHLPF, CM_HIGHISO_ONOFF, WLT_HARD_*, COR_RNG_*, CFAI_MTFEdgeGain, EE_LUMABAYER_RAT, EE_GREEN_RAT, 마스크 (약 95개) | 디모자이크, 색 모아레 억제, 웨이블릿 문턱, 코어링 |
| lcac.txt | LCAC_R_SCALE, B_SCALE, CH_CORRECTION_ON, SIG, R/B_SHIFT_P1..P8 | 배율 색수차 보정 |
| sra.txt | 이름만 있고 키 문자열 없음 | 쓰이지 않거나 다른 방식 (모름) |

### 1.2 그 밖의 경로

| 항목 | 바꾸는 길 | 확신도 |
| --- | --- | --- |
| 고감도 NR (OFF/LOW/MID/HIGH, USERDATA_ISONR) | 메뉴 또는 prefman + 모드 재진입 (추정) | 중 |
| NR 디버그 | st cap capt nr [off / ltnr / adnr], st cap back unitest highiso on (도움말 문자열) | 중하 |
| NR 하드웨어 (NANR, CNR, WNR, BNR) | 드라이버 함수 이름만. txt 경로 없음, writel 은 위험 | 하 |
| Smart Range+ | SMARTRANGE_OFF/ON. 열거형에 HDR_LOW/MIDDLE/HIGH 단계 있음 (켜는 길 모름) | 중 (단계는 하) |
| 색공간 | SRGB, ADOBERGB, 숨은 GALAXY (USERDATA_COLORSPACE) | 중 (GALAXY 는 하) |
| 숨은 효과 | eEFFECT_OLDFILM1/2, HALFTONE, SOFTFOCUS, DEFOG, HOLLYWOOD1..4, CUSTOM_RGB (열거형만) | 하 |
| 그레인 생성기 | d5_ep_nog_set_noisegen (std_sigma, gamma), Nog_Still 과 Nog_View (드라이버만) | 하 |
| JPEG 품질 | SUPERFINE, FINE, NORMAL. 사용자 Q 표 경로 없음 | 하 |
| 렌즈 광학 보정 | /mnt/mmc/oic_table/oic_%s.bin (형식 모름) | 하 |

시험 도구 후보: st cap iq ipc proc simul 과 debug path raw 로 같은 RAW 를 다시 처리할 수 있어 보인다 (도움말만 봄). 값 비교에 쓸 만함.

### 1.3 결과 차이가 클 후보

1. wbee.txt 선명화 (필름처럼 부드럽게, 테두리 넘침 줄이기)
2. gamma.txt 톤 커브
3. color.txt 행렬 두 개 + SE 2x2 (스플릿 톤, 색상 회전)
4. 고감도 NR 단계와 cfai.txt 코어링 (질감)
5. 그레인 생성기와 숨은 효과 (켜는 길을 찾으면 큼, 지금은 이름만)

## 2. 영상 기능

### 2.1 순정 사실

- 4K/UHD 는 APS-C 위에 1.6~1.77배 더 크롭 (환산 약 2.4~2.75배). 1080p 이하는 추가 크롭 없음.
- 제브라, 피킹 있음. 피킹은 녹화 대기 화면에 안 나오고 4K 에서 없다는 보고. 오디오 미터 있음, 마이크 단자 없음.
- Gamma DR 은 자료가 엇갈림. 실기 메뉴로 확인 필요 (펌웨어에는 동영상 감마 STANDARD, GAMMA_D, GAMMA_V 문자열).

### 2.2 상류에 있는 것 (카탈로그에 이미 대부분 있음)

비트레이트 (실사용 140~160 Mbps 안정, 180 일부, 320 실패), 녹화 제한 해제, 해상도 슬롯 바꾸기, 2.5K (크롭이 아니라 센서 전폭 Super35 화각, 롤링셔터 약 8.6ms, 구형 방식은 H.265 12 Mbps), 캠코더 모드, 스텔스 녹화, onscreen REC 버튼. 비트레이트 영구화는 하이버네이션 이미지를 고치는 방식이라 원칙 2 와 충돌해 제외.

### 2.3 남들이 원했지만 못 한 것

- 무크롭 4K, 전 센서 영상: 센서 읽기 모드와 ISP 대역폭. SD 만으로는 불가로 봄. 대안은 2.5K.
- 진짜 1080p 120: sys_param 으로 나오지만 작성자도 진짜 120 이 아니라고 함.
- 영상 샤프닝/NR 끄기, NX500 영상 감마/LUT: 상류 할 일 목록에 남은 채 개발자들이 떠남.
- RAW, 10비트, 4:2:2, LOG: 하드웨어 인코더가 8비트 4:2:0 이라 불가로 봄.
- USB 오디오: 커널 모듈 필요.

### 2.4 새 기능 후보

| 기능 | 무엇 | 난이도 | 가치 |
| --- | --- | --- | --- |
| 상시 피킹 오버레이 | NV12 Y 에지를 X11 로 그림. 대기 화면과 4K 에서도 | 중 | 높음 |
| 폴스 컬러, 세밀한 제브라 | 휘도 구간별 색칠 | 중 | 높음 |
| 웨이브폼, 히스토그램 | 라이브 뷰 버퍼를 열 단위로 집계 | 중 | 높음 |
| 2.5K 원클릭 | 해상도, 비트레이트, 제한 해제를 한 번에 | 하 | 높음 |
| 셔터 각도 도우미 | fps 로 180도 셔터값 표시와 맞춤 | 하 | 중 |
| 크롭 마크 | 2.39, 4:5, 9:16, 세이프 영역 | 하 | 중 |
| 남은 시간, 배터리 경고, 자동 정지 | 잔량을 보다가 깔끔하게 정지 | 하 | 중 |
| 타임코드 사이드카 | 녹화 시작 시각을 JSON 이나 SRT 로 | 하 | 중 |
| 인터벌 영상 | N 분마다 M 초 녹화 | 하 | 중 |
| 동작 감지 녹화 | 라이브 뷰 프레임 차이로 REC | 중 | 중 |
| 웹 원격 REC 와 상태 | 녹화 시간과 잔량 | 하 | 중 |
| 영상 LUT 와 플랫 프로필 | 3D LUT 뱅크가 영상에도 걸리는지 확인부터 | 상 | 중 |
| 영상 ISP 샤프닝/NR 탐색 | st cap iq 덤프 비교로 레지스터 후보 | 상 | 높음 (성공하면) |

피킹, 제브라, 웨이브폼은 같은 라이브 뷰 버퍼 읽기 (nxweb 에 이미 있음) 와 X11 그리기 (카운트다운 표시와 같은 부품) 를 쓴다.

출처: https://github.com/ottokiksmaler/nx500_nx1_modding , https://www.eoshd.com/comments/topic/21211-nx-1-state-of-the-hack-today-dec-2016/ , https://www.eoshd.com/comments/topic/9046-how-crippled-is-the-samsung-nx500/ , https://www.eoshd.com/comments/topic/19450-nx500-hopes-and-dreams , https://www.videomaker.com/article/c05/18258-samsung-nx500-review/
