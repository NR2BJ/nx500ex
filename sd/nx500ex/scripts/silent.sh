#!/bin/sh
# 무음 전자셔터 (단사 전용, 1/30 보다 느린 셔터 불가). 재부팅 때 풀리므로 auto 에서 다시 적용된다.
st cap capdtm setusr ADJUSTSHUTTERTYPE 0x750001 > /dev/null 2>&1
