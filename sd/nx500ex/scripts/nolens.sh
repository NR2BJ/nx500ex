#!/bin/sh
# 렌즈가 인식되지 않아도 셔터 허용 (어댑터 렌즈, 접점 불량)
prefman set 0 0xc2dd l 1 > /dev/null 2>&1
