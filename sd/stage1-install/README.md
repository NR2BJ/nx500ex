# 설치 패키지 (v2)

내장에 블루투스 시작 스크립트 래퍼를 설치한다. 내장 변경은 두 가지뿐이다.

1. /usr/etc/bluetooth/bt-stack-up.sh 의 이름을 bt-stack-up.sh.orig 로 바꾼다. 내용, 권한, 수정 날짜는 그대로다.
2. 같은 자리에 약 600바이트짜리 래퍼를 둔다. 래퍼는 원본을 먼저 그대로 실행한 뒤 SD 의 nx500ex/boot.sh 를 띄운다.

bluetoothd 와 /opt/usr 는 건드리지 않는다. 블루투스를 끄고 켜는 동작은 순정과 같다.

v1 (bluetoothd 이름을 바꾸던 방식) 을 쓰지 않는 이유는 docs/research/2026-10-19-firmware-bt-analysis.md 참고. 요약하면 블루투스를 끌 때 카메라가 `killall bluetoothd` 로 데몬을 끄는데, 이름이 바뀐 원본은 꺼지지 않아 순정과 다르게 동작했다.

## 설치 조건

- NX500 펌웨어 1.12 가 아니면 멈춘다.
- bluetoothd 가 순정이 아니면(v1 설치, NX-KS 등) 멈춘다. v1 이 깔려 있으면 제거 패키지를 먼저 실행한다.
- bt-stack-up.sh 가 공식 펌웨어 1.12 의 원본(cksum 1579358536, 1205 바이트)이 아니면 멈춘다.
- 이미 v2 가 설치되어 있으면 래퍼만 새 것으로 바꾼다. 두 번 실행해도 제거되지 않는다.
- 쓰고 나서 검증하고, 실패하면 설치 전 상태로 되돌린다.

## 사용 방법

1. 이 폴더의 내용(info.tg, nx_cs.adj, nxex_inst.sh, nx500ex-install 폴더)을 SD 루트에 복사한다. 같은 이름의 파일은 모두 덮어쓴다.
2. 배터리를 뺐다 넣고, 카드를 넣고 전원을 켠다.
3. INSTALL OK 와 DONE 이 나오면 전원을 끈다.
4. 정상 모드로 켜서 카메라 메뉴에서 블루투스를 켠다.

설치 전 상태는 SD 의 nx500ex-state/record.txt 에, 진행 기록과 검증 항목별 결과는 nx500ex-state/install-날짜.log 에 남는다. record.txt 는 제거할 때 폴더 날짜 복원에 쓰이므로 지우지 않는다.

## 경로 길이 제한

nx_cs.adj 의 shell script 경로가 길면 카메라가 실행하지 않는다. 31자는 동작했고 34자는 동작하지 않았다 (2026-10-18 실기). 그래서 루트에 짧은 이름의 nxex_inst.sh 를 두고, 그것이 폴더 안의 install.sh 를 부른다.
