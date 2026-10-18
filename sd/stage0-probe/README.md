# 단계 0 진단 패키지

카메라 정보 수집, 설정 전체 백업, 셔터 횟수 조회를 한 번에 하는 SD 카드 패키지다.

안전성

- factory mode(info.tg) 로 실행되므로 카메라 내장 저장소에는 아무것도 쓰지 않는다. 결과는 모두 SD 카드에 저장된다.
- 한 번 실행되면 info.tg 를 info.tg.done 으로 바꾸므로 다음 부팅은 정상 모드다.
- 펌웨어 확인 없이 실행해도 해가 없다. 다만 카운터 위치(prefman 블록 3)는 NX500 기준이다.

사용 방법

1. 사진이 없는 SD 카드를 준비한다 (포맷 권장).
2. 이 폴더(stage0-probe) 안의 내용을 SD 카드 루트에 복사한다. 루트에 info.tg, nx_cs.adj, nx500ex-probe 폴더가 있어야 한다.
3. 카메라 전원을 끄고 배터리를 뺐다가 다시 넣는다.
4. SD 카드를 넣고 전원을 켠다. 화면 왼쪽에 초록 점이 보이고 진행 메시지가 나온다.
5. "DONE" 과 셔터 횟수가 나오면 전원을 끈다. 30초 뒤 메시지는 사라진다.
6. SD 카드를 PC 에 넣고 nx500ex-probe/out-날짜 폴더를 통째로 압축해서 전달한다.

초록 점이 안 보이면 info.tg 가 루트에 없거나 파일 끝 줄바꿈이 깨진 것이다. 윈도우 메모장으로 이 파일들을 열어 저장하지 않는다.

수집 항목

| 파일 | 내용 |
| --- | --- |
| system.txt | 펌웨어 버전, 커널 |
| cpuinfo, meminfo, cmdline, partitions, mount, df | 하드웨어와 저장소 |
| ps.txt, systemd-units.txt | 실행 중인 프로세스와 서비스 |
| input-devices.txt | 키 입력 장치 (keyscan 설계용) |
| existing-mods.txt | NX-KS, nx-on-wake 등 기존 모드 흔적 |
| tools.txt | 카메라에 있는 명령 목록 |
| counters.txt | 셔터, 전원, 플래시 횟수 |
| capdtm.txt | 일부 촬영 설정 값 |
| prefman/FullSave0~10 | 설정 전체 백업. NX-KS 의 FullSave 와 같은 형식 |

prefman 백업은 나중에 설정이 꼬였을 때 복원하는 보험이다. PC 에도 따로 보관한다.
