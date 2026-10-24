#!/usr/bin/env python3
"""RGB .cube (또는 파이썬 함수) 를 NX500 3D LUT 뱅크 파일로 바꾼다.

뱅크 형식 (docs/research/2026-10-25-lut-dump-analysis.md): 17x17x17 항목, 항목 4바이트 (Cr, Cb, Y, 0), Cr 이 가장 빠른 축,
격자 i 번째 칸 = i x 255 / 16. 카메라는 화면 마법사 표준에서 표 17 (0x81115200) 을 라이브 뷰와 JPEG 에 쓴다.

변환: 격자점 (Cr, Cb, Y) 마다
  1. --stock 이 있으면 카메라 원래 표 17 을 먼저 거친다 (밝은 곳 채도 억제 등 순정 처리 유지).
  2. BT.601 전범위로 RGB 로 바꾼다. 0~255 를 벗어나는 점(실제 영상에는 없는 색차 조합)은 안쪽으로 자른 점에 .cube 를 적용하고,
     잘라낸 차이는 그 점에서 .cube 의 기울기(유한 차분)로 밀어 더한다. 항등이면 그대로, 흑백이면 색차가 0 으로 유지된다.
  3. .cube 를 삼선형 보간으로 적용하고 YCbCr 로 되돌려 0~255 로 자른다.

사용: python3 cube2bank.py in.cube out.bin [--stock t17.bin]
      python3 cube2bank.py --identity out.bin [--stock t17.bin]
"""
import argparse
import numpy as np

N = 17
E = N ** 3
TB = E * 4

def read_cube(path):
    size = None; rows = []
    dmin = np.array([0.0, 0.0, 0.0]); dmax = np.array([1.0, 1.0, 1.0])
    for line in open(path, encoding="utf-8", errors="replace"):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        t = s.split()
        if t[0] == "LUT_3D_SIZE":
            size = int(t[1])
        elif t[0] == "LUT_1D_SIZE":
            raise SystemExit("1D LUT 는 지원하지 않음")
        elif t[0] == "DOMAIN_MIN":
            dmin = np.array([float(x) for x in t[1:4]])
        elif t[0] == "DOMAIN_MAX":
            dmax = np.array([float(x) for x in t[1:4]])
        elif t[0] in ("TITLE",):
            continue
        else:
            try:
                rows.append([float(x) for x in t[:3]])
            except ValueError:
                continue
    if size is None or len(rows) != size ** 3:
        raise SystemExit(f"cube 크기 불일치: size={size} rows={len(rows)}")
    # .cube 는 R 이 가장 빠르게 돈다 -> [b, g, r, 3]
    cube = np.array(rows, dtype=np.float64).reshape(size, size, size, 3)
    return cube, dmin, dmax

def trilinear(cube, x):
    """cube: [b, g, r, 3] 0..1, x: (..., 3) RGB 0..1 (범위 밖은 잘라서 봄)."""
    S = cube.shape[0]
    p = np.clip(x, 0, 1) * (S - 1)
    i0 = np.clip(np.floor(p).astype(int), 0, S - 2); f = p - i0
    fr, fg, fb = f[..., 0:1], f[..., 1:2], f[..., 2:3]
    r0, g0, b0 = i0[..., 0], i0[..., 1], i0[..., 2]
    def C(dr, dg, db):
        return cube[b0 + db, g0 + dg, r0 + dr]
    return (C(0,0,0)*(1-fr)*(1-fg)*(1-fb) + C(1,0,0)*fr*(1-fg)*(1-fb) + C(0,1,0)*(1-fr)*fg*(1-fb) + C(1,1,0)*fr*fg*(1-fb)
          + C(0,0,1)*(1-fr)*(1-fg)*fb + C(1,0,1)*fr*(1-fg)*fb + C(0,1,1)*(1-fr)*fg*fb + C(1,1,1)*fr*fg*fb)

def ycc_to_rgb(cr, cb, y):
    cb = cb - 128.0; cr = cr - 128.0
    return np.stack([y + 1.402 * cr, y - 0.344136 * cb - 0.714136 * cr, y + 1.772 * cb], -1)

def rgb_to_ycc(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    y = 0.299 * r + 0.587 * g + 0.114 * b
    return (0.713 * (r - y) + 128.0, 0.564 * (b - y) + 128.0, y)   # (Cr, Cb, Y)

def load_bank(path):
    d = open(path, "rb").read()
    if len(d) < TB:
        raise SystemExit(f"뱅크 파일이 짧음: {len(d)}")
    return np.frombuffer(d[:TB], dtype=np.uint8).reshape(N, N, N, 4)[..., :3].astype(np.float64)  # [Y, Cb, Cr, (Cr,Cb,Y)]

def make_bank(func, stock=None):
    """func: RGB 0..1 배열 (..., 3) -> RGB 0..1. stock: load_bank() 결과 또는 None. 반환: 19652 바이트."""
    grid = np.arange(N) * 255.0 / 16.0
    cr = grid[None, None, :]; cb = grid[None, :, None]; y = grid[:, None, None]
    cr, cb, y = np.broadcast_arrays(cr, cb, y)
    if stock is not None:
        cr, cb, y = stock[..., 0], stock[..., 1], stock[..., 2]
    rgb = ycc_to_rgb(cr, cb, y)
    rgb_c = np.clip(rgb, 0, 255)
    resid = (rgb - rgb_c) / 255.0
    x = rgb_c / 255.0
    f0 = func(x)
    out = f0.copy()
    h = 0.02
    for k in range(3):
        if not np.any(resid[..., k]):
            continue
        step = np.where(x[..., k] <= 1 - h, h, -h)
        xk = x.copy(); xk[..., k] = x[..., k] + step
        dk = (func(xk) - f0) / step[..., None]
        out = out + dk * resid[..., k:k + 1]
    out = out * 255.0
    ocr, ocb, oy = rgb_to_ycc(out)
    ent = np.zeros((N, N, N, 4), dtype=np.uint8)
    ent[..., 0] = np.clip(np.rint(ocr), 0, 255)
    ent[..., 1] = np.clip(np.rint(ocb), 0, 255)
    ent[..., 2] = np.clip(np.rint(oy), 0, 255)
    return ent.tobytes()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cube", nargs="?")
    ap.add_argument("out")
    ap.add_argument("--stock", help="카메라 원래 표 17 파일 (19652 바이트). 먼저 거친다")
    ap.add_argument("--identity", action="store_true", help=".cube 없이 항등 표")
    a = ap.parse_args()
    stock = load_bank(a.stock) if a.stock else None
    if a.identity:
        func = lambda x: x
    else:
        cube, dmin, dmax = read_cube(a.cube)
        func = lambda x: trilinear(cube, (x - dmin) / (dmax - dmin))
    data = make_bank(func, stock)
    open(a.out, "wb").write(data)
    print(f"{a.out}: {len(data)} 바이트" + (" (원래 표 17 합성)" if stock is not None else ""))

if __name__ == "__main__":
    main()
