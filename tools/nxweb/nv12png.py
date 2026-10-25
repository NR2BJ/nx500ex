#!/usr/bin/env python3
"""nxweb 의 /lv 응답 (NV12 720x480, 또는 저화질 259200 바이트) 을 PNG 로. 라이브 뷰 주소가 맞는지 PC 에서 확인하는 용도.
사용: python nv12png.py <lv.bin> <out.png> [full|video]   (기본 full 레인지)"""
import sys, numpy as np
from PIL import Image
W, H = 720, 480
raw = np.fromfile(sys.argv[1], dtype=np.uint8)
rng = sys.argv[3] if len(sys.argv) > 3 else "full"
if raw.size == W * H * 3 // 2:
    Y = raw[:W * H].reshape(H, W).astype(np.float32)
    UV = raw[W * H:].reshape(H // 2, W // 2, 2)
elif raw.size == W * H // 4 * 3:
    Y = raw[:W * H // 4].reshape(H // 2, W // 2).astype(np.float32).repeat(2, 0).repeat(2, 1)
    UV = raw[W * H // 4:].reshape(H // 2, W // 2, 2)
else:
    sys.exit(f"크기가 이상함: {raw.size}")
U = UV[:, :, 0].astype(np.float32).repeat(2, 0).repeat(2, 1) - 128
V = UV[:, :, 1].astype(np.float32).repeat(2, 0).repeat(2, 1) - 128
if rng == "video":
    Y = 1.164 * (Y - 16)
R = Y + 1.596 * V; G = Y - 0.391 * U - 0.813 * V; B = Y + 2.018 * U
img = np.clip(np.dstack([R, G, B]), 0, 255).astype(np.uint8)
Image.fromarray(img).save(sys.argv[2])
print(sys.argv[2], "Y 평균 %.1f, 최소 %d, 최대 %d" % (Y.mean(), raw[:W*H].min(), raw[:W*H].max()))
