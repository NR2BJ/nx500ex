#!/bin/sh
# 예시: AF 보조광 1초
echo 1 > /sys/devices/platform/leds-gpio/leds/af/brightness; sleep 1
echo 0 > /sys/devices/platform/leds-gpio/leds/af/brightness
