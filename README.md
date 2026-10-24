# nx500ex

Samsung NX500 (펌웨어 1.12) 기능 확장. 기능은 모두 SD 카드에서 실행되고, 블루투스를 켜면 켜지고 끄면 꺼진다. 카드를 빼면 순정과 같다.

내장 플래시에는 블루투스가 켜질 때 SD 의 스크립트를 부르는 래퍼 한 파일만 둔다. 제거기로 순정 상태로 되돌린다.

## 기능

| 분류 | 기능 |
| --- | --- |
| 촬영 | 무음 셔터, 렌즈 없이 촬영, 셀프타이머, 장노출(30초까지), 인터벌, HDR 5장, 포커스 스태킹, 작업 중 화면 끄기, 재생 화면에서 작업 사진 묶기 |
| 색 | 필름 레시피 43개 (화면 마법사 사용자 1 과 화이트 밸런스, 필요한 것은 3D LUT 까지), 3D LUT 110개 (이미지 처리 메모리의 색 표 42개를 직접 바꿈. 자체 룩 11, 공개 필름 에뮬레이션 99: 코닥, 후지, 아그파, 일포드, 롤라이, 로모, 폴라로이드, 스타일, 영화 인화) |
| 설정 | UP/DOWN 프로필, 전체 설정 백업/복원, 셔터 횟수, 텔넷/FTP |
| 조작 | 한글 메뉴 (EV 두 번), 키 설정 (EV 조합, 두 번 누르기, 길게 누르기) |

사용법은 sd/nx500ex/README.md 에 있다. 타사 .cube, HaldCLUT 를 카메라용 표로 바꾸는 웹 변환기는 https://nr2bj.github.io/nx500ex/ (설치 없이 브라우저 안에서 변환, 전송 없음. 소스는 web/).

## 폴더

| 위치 | 내용 |
| --- | --- |
| sd/nx500ex/ | 실사용 SD 패키지 (메뉴, 기능 스크립트, 바이너리) |
| sd/stage1-install/, sd/stage1-uninstall/ | 내장 래퍼 설치, 완전 제거 |
| sd/stage0-probe/, sd/stage1-test/ | 진단, 검증용 SD 구성 |
| tools/nxmenu/ | nxmenu (메뉴), nxpopup (알림), nxkeys (키 감지), nxgroup (재생 화면 묶기), nxmem (메모리 조사) 소스와 빌드 스크립트 |
| tools/film/ | 필름 레시피 메뉴 화면 생성기, 보정 색표, 보정 촬영과 비교 촬영 분석 도구 |
| tools/lut/ | 3D LUT 덤프 분석기, .cube 와 HaldCLUT -> 뱅크 변환기 (cube2bank), 룩 정의와 생성기 (looks, make_luts), 타사 .cube 추가 (add_cube), 공개 필름 에뮬레이션 모음 들여오기 (import_haldclut), 검증 촬영 분석 (lut_verify), 미리보기 (apply_lut) |
| dumps/lut/ | 카메라에서 뜬 LUT 뱅크 덤프와 분석 결과 |
| docs/plan/ | 로드맵, 설계 |
| docs/research/ | 조사와 실기 검증 기록 |
| web/ | LUT 변환기 웹 페이지 (GitHub Pages, .github/workflows/pages.yml 로 배포). convert.js 는 tools/lut/cube2bank.py 와 바이트 단위로 같은 계산 (tools/lut/web_test.js 로 검사) |

문서

- docs/research/2026-10-17-nx500-mod-survey.md : 기존 모딩 생태계 조사 (NX-KS 2.88 전체 기능, ge0rg 변경점, 기타 제작자 작업, 실행 방식 비교)
- docs/research/2026-10-18-feature-and-script-catalog.md : NX-KS 2.88, ge0rg, NXWA, 상류의 기능과 스크립트 전수 목록
- docs/research/2026-10-18-probe-result.md : 진단 결과
- docs/research/2026-10-18-stage1-test.md : 실기 검증 기록 (단계 1부터 지금까지)
- docs/research/2026-10-19-firmware-bt-analysis.md : 공식 펌웨어 분석 (블루투스 켜기/끄기, SD 언마운트 실제 동작)
- docs/research/2026-10-23-lut-firmware-analysis.md : 색 처리 표(톤 커브, 색 행렬, 3D LUT)를 실행 중에 바꾸는 경로 펌웨어 분석
- docs/research/2026-10-25-lut-dump-analysis.md : 3D LUT 뱅크 덤프 분석과 쓰기 시험 (표 42개 위치, (Cr, Cb, Y) 8비트 형식, 표준은 표 17, 반셔터 때 적재)
- docs/plan/roadmap.md : 로드맵
- docs/plan/stage1-design.md : 단계 1 설계
- docs/plan/undecided-explained.md : 보류 항목 설명과 추천

## 주의

카메라 내부를 바꾸는 비공식 개조다. 이 저장소의 내용은 보증 없이 제공되며, 카메라 고장이나 데이터 손실에 대한 책임은 쓰는 사람에게 있다. 내장 변경 전에는 설정 백업과 공식 펌웨어 파일을 준비해 둔다.

## 라이선스

GNU Affero General Public License v3.0 (LICENSE). 아래 출처의 AGPL-3.0 코드와 바이너리를 포함하거나 바탕으로 하므로 저장소 전체를 같은 라이선스로 공개한다. sd/nx500ex/lut 의 회사별 LUT 는 CC BY-SA 4.0 (별도 표기). 수정본을 배포하거나 네트워크로 제공할 때는 소스를 함께 공개해야 한다.

busybox, telnetd 바이너리는 GPL-2.0 이다.

## 출처와 감사

이 프로젝트는 아래 사람들의 연구와 코드 위에 있다.

| 출처 | 가져오거나 참고한 것 |
| --- | --- |
| ottokiksmaler/nx500_nx1_modding (Otto 와 상류 기여자: vasile-gh, KinoSeed, Georg Lukas 등) | 키 감지(keyscan.c, nxkeys 의 바탕), 메뉴(mod_gui, nxmenu 의 바탕), 알림(popup_timeout, nxpopup 의 바탕), popup_ok, popup_entry, poker, blackout. st 명령, prefman (화면 마법사, 화이트 밸런스 위치 포함), st cap capdtm varlist, 키 이벤트, 펌웨어 구조 문서 |
| NX-KS 2.88 (KinoSeed) | 무음 셔터, 렌즈 없이 촬영, 프로필, 셔터 횟수 등 기능 스크립트의 원리와 prefman 위치. 포함된 바이너리 빌드 (popup 류, poker, blackout, busybox, telnetd). 블루투스로 모드를 시작하는 방식 |
| ge0rg/nx-ks-mod (Georg Lukas) | NX-KS 이력 복원과 유지보수, stapp 바이너리, 벌브 타이머, IP 표시 |
| mewlips/nx-remote-controller-mod, ajavamind/Multi-NX-Camera-Control, mbriney/nx500_nx1_modding, ge0rg/samsung-nx-hacks | 조사 참고 (원격 제어, 여러 대 제어, 배포본 보존, 모델 정보) |
| nxfiles.nx.tc | NX-KS 배포본과 공식 펌웨어 미러 |
| NatronGitHub/clut (Pat David 의 필름 에뮬레이션, Marc Roovers 의 PictureFX, Juan Melara 의 인화 필름 HaldCLUT, CC BY-SA 4.0) | sd/nx500ex/lut 의 회사별 3D LUT 99개의 원본. 변환 결과도 CC BY-SA 4.0 (sd/nx500ex/lut/LICENSE-haldclut.txt) |

각 파일의 머리말과 sd/nx500ex/README.md 의 바이너리 출처 표에 파일별 출처를 적었다.

## 상표

Samsung, NX500 은 삼성전자의 상표다. 필름 레시피의 이름(Portra, Ektar, Tri-X, Velvia, Provia, Acros, HP5, Delta, XP2, FP4, Phoenix, CineStill, Vision3, LomoChrome, Polaroid, Instax 등)은 Eastman Kodak, Fujifilm, Harman Technology (Ilford), CineStill, Lomography, Polaroid 등 각 회사의 상표이며, 레시피는 그 필름의 느낌을 흉내 낸 설정값일 뿐 각 회사와 관계없다.
