#!/bin/sh
# EV+반셔터: 약 5초 셀프타이머. 바디 램프가 점점 빨리 깜빡인 뒤 촬영 (브라케팅, 연사 설정 그대로)
# keyscan 이 기다리지 않도록 백그라운드로 실행한다.
(
  for i in 1 2 3 4 5; do st cap capt light on body; st cap capt light off body; sleep 0.5; done
  for i in 1 2 3; do st cap capt light on body; st cap capt light off body; sleep 0.1; done
  st cap capt light on body; sleep 1; st cap capt light off body
  st key push s1; st key push s2; st key release s2; st key release s1
) > /dev/null 2>&1 &
