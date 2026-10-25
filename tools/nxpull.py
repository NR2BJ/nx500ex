#!/usr/bin/env python3
"""nxpull: 카메라의 새 사진을 PC 로 자동으로 가져온다 (웹 원격 nxweb 의 /dcim 과 /dcim/<파일> 을 씀. 카메라 쪽 설정 없음).

사용: python3 tools/nxpull.py [--ip 192.168.1.66] [--dest ~/Pictures/nx500] [--interval 3] [--types jpg,srw,mp4] [--all]
  기본은 스크립트를 켠 뒤에 생긴 파일만 가져온다. --all 이면 카드에 있는 것 (최근 200장) 을 전부.
  파일 크기와 시각이 두 번 연속 같을 때 (쓰기가 끝났을 때) 받고, 받는 동안은 .part 이름으로 두었다가 끝나면 바꾼다.
  카메라가 꺼지거나 WiFi 가 끊기면 기다렸다가 다시 붙는다. Ctrl-C 로 끝낸다.
표준 라이브러리만 쓴다 (Mac, Windows, Linux 의 python3).
"""
import argparse, json, os, sys, time, urllib.request, urllib.error

ap = argparse.ArgumentParser()
ap.add_argument("--ip", default="192.168.1.66")
ap.add_argument("--dest", default=os.path.expanduser("~/Pictures/nx500"))
ap.add_argument("--interval", type=float, default=3.0)
ap.add_argument("--types", default="jpg,srw,mp4")
ap.add_argument("--all", action="store_true", help="켜기 전부터 있던 파일도 가져온다")
a = ap.parse_args()
types = tuple("." + t.strip().lower() for t in a.types.split(",") if t.strip())
base = f"http://{a.ip}"
os.makedirs(a.dest, exist_ok=True)

def get(url, timeout=10):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.read()

def log(*s):
    print(time.strftime("%H:%M:%S"), *s, flush=True)

seen = {}        # 이름 -> (크기, 시각) 마지막으로 본 값
done = set()     # 받은 파일
stable = {}      # 이름 -> 같은 값으로 본 횟수
first = True
connected = None
while True:
    try:
        lst = json.loads(get(base + "/dcim"))
        if connected is not True:
            log(f"카메라 연결됨 {a.ip}, 받을 곳 {a.dest}")
            connected = True
    except (urllib.error.URLError, OSError, ValueError) as e:
        if connected is not False:
            log("카메라에 닿지 않음, 기다리는 중")
            connected = False
        time.sleep(max(a.interval, 3))
        continue
    for f in lst:
        name, size, t = f["n"], f["s"], f["t"]
        if not name.lower().endswith(types) or name in done:
            continue
        if first and not a.all:
            done.add(name)       # 켜기 전 파일은 건너뜀
            continue
        local = os.path.join(a.dest, name.replace("/", os.sep))
        if os.path.exists(local) and os.path.getsize(local) == size:
            done.add(name)
            continue
        if seen.get(name) == (size, t):
            stable[name] = stable.get(name, 0) + 1
        else:
            seen[name] = (size, t)
            stable[name] = 0
        if stable[name] < 1:
            continue             # 아직 쓰는 중일 수 있음: 다음 번에 같으면 받는다
        os.makedirs(os.path.dirname(local), exist_ok=True)
        part = local + ".part"
        t0 = time.time()
        try:
            with urllib.request.urlopen(base + "/dcim/" + name, timeout=60) as r, open(part, "wb") as o:
                got = 0
                while True:
                    chunk = r.read(1 << 16)
                    if not chunk:
                        break
                    o.write(chunk); got += len(chunk)
            if got != size:
                log(f"크기 다름 {name}: {got} / {size}, 다시 시도")
                os.remove(part)
                continue
            os.replace(part, local)
            done.add(name)
            dt = time.time() - t0
            log(f"받음 {name} {size / 1048576:.1f} MB, {dt:.1f} 초 ({size / dt / 1048576:.1f} MB/s)")
        except (urllib.error.URLError, OSError) as e:
            log(f"실패 {name}: {e}")
            if os.path.exists(part):
                os.remove(part)
    first = False
    time.sleep(a.interval)
