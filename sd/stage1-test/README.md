# 단계 1 검증용 SD 구성

설치 패키지로 래퍼를 설치한 뒤, 이 폴더의 nx500ex 폴더를 SD 루트에 복사한다. 경로 전체가 동작하는지 확인하는 최소 구성이다.

```
nx500ex/
    boot.sh                 래퍼가 부름. keyscan 시작, log/boot.log 에 시각 기록
    bin/keyscan             NX-KS 2.55, 2.88, NXWA 가 써 온 것과 같은 바이너리 (md5 3bb2322589883308c488f72af0f6dffc)
    scripts/auto/00_hello.sh  켤 때마다 AF 보조광 1초
    scripts/EV_S1.sh        EV 를 누른 채 반셔터: AF 보조광 두 번 깜빡임
```

keyscan 은 Otto Kiksmaler 가 작성했고 상류 저장소(ottokiksmaler/nx500_nx1_modding)의 keyscan.c 가 소스다. 라이선스는 AGPL-3.0 이다.

## 확인 순서

| 번호 | 할 일 | 기대 결과 |
| --- | --- | --- |
| 1 | 설치 패키지 실행, 블루투스 ON | INSTALL OK |
| 2 | nx500ex 폴더를 SD 에 복사하고 배터리를 뺐다 넣은 뒤 전원 ON | 몇 초 뒤 AF 보조광이 1초 켜짐 |
| 3 | 전원 스위치 OFF, 다시 ON 을 5번 반복. 켤 때부터 불이 들어올 때까지 대략 몇 초인지 메모 | 매번 불이 켜짐 |
| 4 | EV 를 누른 채 반셔터 | 보조광 두 번 깜빡임 |
| 5 | 블루투스를 메뉴에서 OFF 한 뒤 EV+반셔터 | 반응 없음이 예상 (모드도 함께 꺼짐) |
| 6 | SD 를 PC 에 넣고 nx500ex 폴더 안에 빈 파일 DISABLE 을 만든 뒤 콜드 부팅 | 불 안 켜짐 (안전 모드) |
| 7 | 다른 SD 카드(nx500ex 폴더 없음)로 켜기 | 순정과 같이 동작 |
| 8 | 제거 패키지 실행 | UNINSTALL OK |

결과와 함께 SD 의 nx500ex/log/boot.log 와 nx500ex-state 폴더의 로그를 전달한다. 3번에서 매번 불이 켜지지 않으면, 켤 때마다 bluetoothd 가 다시 시작된다는 가정이 틀린 것이다. 그때는 keyscan 하나만 내장으로 옮기는 방안으로 간다.
