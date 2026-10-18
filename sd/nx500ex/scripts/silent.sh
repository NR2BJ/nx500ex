#!/bin/sh
# 무음 전자셔터. 공장 조정용 셔터 종류 값(ADJUSTSHUTTERTYPE_ROLLING)을 바꾸는 방식이라 순정 기능이 아니다.
# 2026-10-19 실기: 단사는 됨. 노출 브라케팅에서는 한 장만 찍힘. 판독 잡음이 기계 셔터보다 약 37% 큼 (ISO 3200 다크 프레임).
# 재부팅 때 풀리므로 auto 에서 다시 적용된다.
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
st cap capdtm setusr ADJUSTSHUTTERTYPE 0x750001 > /dev/null 2>&1
