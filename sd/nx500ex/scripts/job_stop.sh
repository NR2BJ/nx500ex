#!/bin/sh
# 진행 중인 촬영 작업 중단
. "${NX500EX:-/mnt/mmc/nx500ex}/scripts/common.sh"
if job_running; then job_stop; popup "작업 중단" 2; else popup "진행 중인 작업 없음" 2; fi
