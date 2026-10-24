#!/usr/bin/env python3
"""덤프 속 17^3 표 하나를 이미지에 적용해 본다 (PC 미리보기).

해석 선택:
  --space ycc  : 표의 (c0, c1, c2) = (Cb, Cr, Y). 이미지를 BT.601 전범위 YCbCr 로 바꿔 표를 거치고 RGB 로 되돌린다.
  --space ycc-swap : (c0, c1, c2) = (Cr, Cb, Y)
  --space rgb  : (c0, c1, c2) = (R, G, B)
사용: python3 apply_lut.py lut_a.bin 0x81101e00 in.png out.png --space ycc
"""
import sys, argparse
import numpy as np
from PIL import Image

N = 17; E = N ** 3; TB = E * 4
BASE = 0x810c3500

def load_table(dump, addr, base=BASE):
    d = open(dump, "rb").read()
    off = addr - base
    return np.frombuffer(d[off:off + TB], dtype=np.uint8).reshape(E, 4)[:, :3].astype(np.float32).reshape(N, N, N, 3)

def trilinear(g, x):
    """x: (..., 3) 0..255, 축 순서 (fast, mid, slow). g: [slow, mid, fast, 3]."""
    p = np.clip(x, 0, 255) / 255.0 * (N - 1)
    i0 = np.floor(p).astype(int); i0 = np.clip(i0, 0, N - 2); f = p - i0
    f0, f1, f2 = f[..., 0:1], f[..., 1:2], f[..., 2:3]
    a0, a1, a2 = i0[..., 0], i0[..., 1], i0[..., 2]
    def G(da, db, dc):
        return g[a2 + dc, a1 + db, a0 + da]
    out = (G(0,0,0)*(1-f0)*(1-f1)*(1-f2) + G(1,0,0)*f0*(1-f1)*(1-f2) + G(0,1,0)*(1-f0)*f1*(1-f2) + G(1,1,0)*f0*f1*(1-f2)
         + G(0,0,1)*(1-f0)*(1-f1)*f2 + G(1,0,1)*f0*(1-f1)*f2 + G(0,1,1)*(1-f0)*f1*f2 + G(1,1,1)*f0*f1*f2)
    return out

def rgb_to_ycc(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    y = 0.299 * r + 0.587 * g + 0.114 * b
    cb = 128 + (b - y) * 0.564
    cr = 128 + (r - y) * 0.713
    return np.stack([y, cb, cr], -1)

def ycc_to_rgb(ycc):
    y = ycc[..., 0]
    cb = ycc[..., 1] - 128
    cr = ycc[..., 2] - 128
    r = y + 1.402 * cr
    g = y - 0.344 * cb - 0.714 * cr
    b = y + 1.772 * cb
    return np.stack([r, g, b], -1)

def apply(g, img, space):
    rgb = np.asarray(img.convert("RGB")).astype(np.float32)
    if space == "rgb":
        out = trilinear(g, rgb)
    else:
        ycc = rgb_to_ycc(rgb)
        y, cb, cr = ycc[..., 0], ycc[..., 1], ycc[..., 2]
        x = np.stack([cb, cr, y], -1) if space == "ycc" else np.stack([cr, cb, y], -1)
        o = trilinear(g, x)
        if space == "ycc":
            ycc2 = np.stack([o[..., 2], o[..., 0], o[..., 1]], -1)
        else:
            ycc2 = np.stack([o[..., 2], o[..., 1], o[..., 0]], -1)
        out = ycc_to_rgb(ycc2)
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump"); ap.add_argument("addr", type=lambda x: int(x, 0))
    ap.add_argument("inp"); ap.add_argument("out")
    ap.add_argument("--space", choices=["ycc", "ycc-swap", "rgb"], default="ycc")
    ap.add_argument("--base", type=lambda x: int(x, 0), default=BASE)
    a = ap.parse_args()
    g = load_table(a.dump, a.addr, a.base)
    apply(g, Image.open(a.inp), a.space).save(a.out)

if __name__ == "__main__":
    main()
