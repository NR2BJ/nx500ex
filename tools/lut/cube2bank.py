#!/usr/bin/env python3
"""RGB .cube (또는 파이썬 함수) 를 NX500 3D LUT 뱅크 파일로 바꾼다.

뱅크 형식 (docs/research/2026-10-25-lut-dump-analysis.md): 17x17x17 항목, 항목 4바이트 (Cr, Cb, Y, 0), Cr 이 가장 빠른 축.
격자 노드 i 는 입력값 i x 16 (0, 16, ..., 240, 256). 순정 항등 표가 0, 16, ..., 240, 255 (노드 9 가 143 이 아니라 144) 이므로
하드웨어는 위 4비트를 색인, 아래 4비트를 분수로 쓰는 것으로 본다. 노드 16 (256) 은 룩의 기울기로 밖으로 민 값을 둔다.

변환: 격자점 (Cr, Cb, Y) 마다
  1. stock 이 있으면 카메라 원래 표를 먼저 거친다 (밝은 곳 채도 억제 등 순정 처리 유지).
  2. BT.601 전범위로 RGB 로 바꾼다. 0~255 를 벗어나는 점(실제 영상에는 없는 색차 조합)은 안쪽으로 자른 점에 룩을 적용하고,
     잘라낸 차이는 그 점에서 룩의 기울기(유한 차분)로 밀어 더한다. 항등이면 그대로, 흑백이면 색차가 0 으로 유지된다.
  3. YCbCr 로 되돌려 0~255 로 자른다.

사용: python3 cube2bank.py in.cube|in.png(HaldCLUT) out.bin [--stock t17.bin]   (.cube 는 1D, 3D, 1D+3D)
      python3 cube2bank.py --identity out.bin [--stock t17.bin]
"""
import argparse
import numpy as np

N = 17
E = N ** 3
TB = E * 4
BANK = 0x4d00
BASE = 0x810c3500
GRID_A = (0x810c3500, 20)   # 덤프 속 구간 A: 시작, 표 수
GRID_B = (0x81123d00, 22)

# ---- 색 공간 모델 (카메라 = BT.601 전범위, 2026-10-25 실기와 맞음. lut_verify.py 가 다른 후보와 비교한다) ----
MODELS = {
    "601full":  dict(kr=0.299, kb=0.114, yoff=0, yscale=1.0, cscale=1.0),
    "601lim":   dict(kr=0.299, kb=0.114, yoff=16, yscale=219 / 255, cscale=224 / 255),
    "709full":  dict(kr=0.2126, kb=0.0722, yoff=0, yscale=1.0, cscale=1.0),
    "709lim":   dict(kr=0.2126, kb=0.0722, yoff=16, yscale=219 / 255, cscale=224 / 255),
}

def rgb_to_ycc(rgb, model="601full"):
    """RGB 0..255 -> (Cr, Cb, Y) 0..255"""
    m = MODELS[model]; kr, kb = m["kr"], m["kb"]; kg = 1 - kr - kb
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    y = kr * r + kg * g + kb * b
    cr = (r - y) / (2 * (1 - kr)) * m["cscale"] + 128.0
    cb = (b - y) / (2 * (1 - kb)) * m["cscale"] + 128.0
    return (cr, cb, y * m["yscale"] + m["yoff"])

def ycc_to_rgb(cr, cb, y, model="601full"):
    m = MODELS[model]; kr, kb = m["kr"], m["kb"]; kg = 1 - kr - kb
    y = (y - m["yoff"]) / m["yscale"]
    cr = (cr - 128.0) / m["cscale"] * 2 * (1 - kr)
    cb = (cb - 128.0) / m["cscale"] * 2 * (1 - kb)
    r = y + cr; b = y + cb
    g = (y - kr * r - kb * b) / kg
    return np.stack([r, g, b], -1)

def read_cube(path):
    """.cube 를 읽는다. 돌려주는 것: dict(lut1d=(S1,3) 또는 None, dmin1, dmax1, cube=[b,g,r,3] 또는 None, dmin, dmax).
    1D 만, 3D 만, 1D + 3D (1D 를 먼저 채널마다 적용하고 3D) 를 지원한다. 1D 와 3D 가 같이 있으면 표 데이터는 1D 가 먼저 온다
    (Resolve 등의 관례). DOMAIN_MIN/MAX 는 각 표 직전에 적힌 것이 그 표의 것."""
    size1 = size3 = None; rows = []
    dom = {"1d": [np.zeros(3), np.ones(3)], "3d": [np.zeros(3), np.ones(3)]}
    cur = None
    for line in open(path, encoding="utf-8", errors="replace"):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        t = s.split()
        if t[0] == "LUT_3D_SIZE":
            size3 = int(t[1]); cur = "3d"
        elif t[0] == "LUT_1D_SIZE":
            size1 = int(t[1]); cur = "1d"
        elif t[0] == "DOMAIN_MIN":
            dom[cur or ("1d" if size3 is None and size1 is not None else "3d")][0] = np.array([float(x) for x in t[1:4]])
        elif t[0] == "DOMAIN_MAX":
            dom[cur or ("1d" if size3 is None and size1 is not None else "3d")][1] = np.array([float(x) for x in t[1:4]])
        elif t[0] in ("TITLE", "LUT_1D_INPUT_RANGE", "LUT_3D_INPUT_RANGE"):
            continue
        else:
            try:
                rows.append([float(x) for x in t[:3]])
            except ValueError:
                continue
    n1 = size1 or 0; n3 = size3 ** 3 if size3 else 0
    if (size1 is None and size3 is None) or len(rows) != n1 + n3:
        raise SystemExit(f"cube 크기 불일치: 1D={size1} 3D={size3} rows={len(rows)} (필요 {n1 + n3})")
    arr = np.array(rows, dtype=np.float64)
    lut1d = arr[:n1] if size1 else None
    cube = arr[n1:].reshape(size3, size3, size3, 3) if size3 else None   # [b, g, r, 3]
    return dict(lut1d=lut1d, dmin1=dom["1d"][0], dmax1=dom["1d"][1], cube=cube, dmin=dom["3d"][0], dmax=dom["3d"][1])

def apply_1d(lut1d, x):
    """lut1d: (S, 3) 0..1. x: (..., 3) 0..1. 채널마다 선형 보간"""
    S = lut1d.shape[0]
    p = np.clip(x, 0, 1) * (S - 1)
    i0 = np.clip(np.floor(p).astype(int), 0, S - 2); f = p - i0
    out = np.empty_like(x)
    for c in range(3):
        out[..., c] = lut1d[i0[..., c], c] * (1 - f[..., c]) + lut1d[i0[..., c] + 1, c] * f[..., c]
    return out

def trilinear_cube(cube, x):
    """cube: [b, g, r, 3] 0..1, x: (..., 3) RGB 0..1 (범위 밖은 잘라서 봄)"""
    S = cube.shape[0]
    p = np.clip(x, 0, 1) * (S - 1)
    i0 = np.clip(np.floor(p).astype(int), 0, S - 2); f = p - i0
    fr, fg, fb = f[..., 0:1], f[..., 1:2], f[..., 2:3]
    r0, g0, b0 = i0[..., 0], i0[..., 1], i0[..., 2]
    def Cc(dr, dg, db):
        return cube[b0 + db, g0 + dg, r0 + dr]
    return (Cc(0,0,0)*(1-fr)*(1-fg)*(1-fb) + Cc(1,0,0)*fr*(1-fg)*(1-fb) + Cc(0,1,0)*(1-fr)*fg*(1-fb) + Cc(1,1,0)*fr*fg*(1-fb)
          + Cc(0,0,1)*(1-fr)*(1-fg)*fb + Cc(1,0,1)*fr*(1-fg)*fb + Cc(0,1,1)*(1-fr)*fg*fb + Cc(1,1,1)*fr*fg*fb)

def cube_func(path):
    c = read_cube(path)
    def f(x):
        if c["lut1d"] is not None:
            x = apply_1d(c["lut1d"], (x - c["dmin1"]) / (c["dmax1"] - c["dmin1"]))
        if c["cube"] is not None:
            x = trilinear_cube(c["cube"], (x - c["dmin"]) / (c["dmax"] - c["dmin"]))
        return x
    return f

def read_haldclut(path):
    """HaldCLUT PNG (한 변 = 레벨^3 의 정사각형 또는 레벨^3 x 레벨^3 격자). R 이 가장 빠르게 돌고 G, B 순. 반환 [b, g, r, 3] 0..1"""
    from PIL import Image
    im = Image.open(path).convert("RGB")
    w, h = im.size
    n = w * h
    size = round(n ** (1 / 3))
    if size ** 3 != n:
        raise SystemExit(f"HaldCLUT 크기가 아님: {w}x{h}")
    a = np.asarray(im, dtype=np.float64).reshape(n, 3) / 255.0
    return a.reshape(size, size, size, 3)   # 색인 = r + size*g + size*size*b -> [b, g, r]

def hald_func(path):
    cube = read_haldclut(path)
    return lambda x: trilinear_cube(cube, x)

def look_func(path):
    """확장자로 .cube 와 HaldCLUT(.png) 을 가른다"""
    return hald_func(path) if path.lower().endswith((".png", ".tif", ".tiff")) else cube_func(path)

def load_bank(data_or_path):
    """19652 바이트 (또는 그 이상) -> [Y, Cb, Cr, (Cr, Cb, Y)] float"""
    d = open(data_or_path, "rb").read() if isinstance(data_or_path, str) else data_or_path
    if len(d) < TB:
        raise SystemExit(f"뱅크가 짧음: {len(d)}")
    return np.frombuffer(d[:TB], dtype=np.uint8).reshape(N, N, N, 4)[..., :3].astype(np.float64)

def apply_func_extrap(func, rgb):
    """rgb 0..255 (범위 밖 가능) 에 룩 적용. 범위 밖은 안쪽 점의 값 + 기울기 x 차이. 반환 0..255 스케일 (자르지 않음)"""
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
    return out * 255.0

def make_bank(func, stock=None, model="601full"):
    """func: RGB 0..1 (..., 3) -> RGB 0..1. stock: load_bank() 결과 또는 None. 반환: 19652 바이트"""
    grid = np.arange(N) * 16.0
    cr = grid[None, None, :]; cb = grid[None, :, None]; y = grid[:, None, None]
    cr, cb, y = np.broadcast_arrays(cr, cb, y)
    if stock is not None:
        cr, cb, y = stock[..., 0], stock[..., 1], stock[..., 2]
    out = apply_func_extrap(func, ycc_to_rgb(cr, cb, y, model))
    ocr, ocb, oy = rgb_to_ycc(out, model)
    ent = np.zeros((N, N, N, 4), dtype=np.uint8)
    ent[..., 0] = np.clip(np.rint(ocr), 0, 255)
    ent[..., 1] = np.clip(np.rint(ocb), 0, 255)
    ent[..., 2] = np.clip(np.rint(oy), 0, 255)
    return ent.tobytes()

def make_regions(func, dump, compose=True, model="601full"):
    """덤프(0x810c3500 부터) 의 42개 표 자리에 룩을 넣은 구간 A, B 바이트를 돌려준다.
    compose=True 면 표마다 자기 원래 표 위에 룩을 얹고, False 면 순수 룩 (검증용)."""
    out = []
    for start, count in (GRID_A, GRID_B):
        buf = bytearray()
        for k in range(count):
            off = start + k * BANK - BASE
            st = load_bank(dump[off:off + TB]) if compose else None
            buf += make_bank(func, st, model)
            if k + 1 < count:
                buf += dump[off + TB:off + BANK]
        out.append(bytes(buf))
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cube", nargs="?")
    ap.add_argument("out")
    ap.add_argument("--stock", help="카메라 원래 표 파일 (19652 바이트). 먼저 거친다")
    ap.add_argument("--identity", action="store_true", help=".cube 없이 항등 표")
    a = ap.parse_args()
    stock = load_bank(a.stock) if a.stock else None
    func = (lambda x: x) if a.identity else look_func(a.cube)
    data = make_bank(func, stock)
    open(a.out, "wb").write(data)
    print(f"{a.out}: {len(data)} 바이트" + (" (원래 표 합성)" if stock is not None else ""))

if __name__ == "__main__":
    main()
