#!/usr/bin/env python3
"""룩 정의 (RGB 0..1 배열 -> RGB 0..1). make_luts.py (메뉴 룩, 검증 룩), lut_verify.py 가 같이 쓴다."""
import colorsys
import numpy as np

def luma(x):
    return 0.299 * x[..., 0] + 0.587 * x[..., 1] + 0.114 * x[..., 2]

def sat(x, k):
    L = luma(x)[..., None]
    return L + (x - L) * k

def contrast(x, k, pivot=0.5):
    return pivot + (x - pivot) * k

def scurve(x, k):
    """k > 1 이면 대비 증가, 중간 회색 고정의 부드러운 S 곡선"""
    return 0.5 + 0.5 * np.sign(x - 0.5) * np.abs(2 * x - 1) ** (1.0 / k)

def softclip(x, knee=0.8):
    y = x.copy()
    m = x > knee
    y[m] = knee + (1 - knee) * (1 - np.exp(-(x[m] - knee) / (1 - knee)))
    return y

def hsv_map(x, fn):
    flat = np.clip(x.reshape(-1, 3), 0, 1)
    out = np.empty_like(flat)
    for i, (r, g, b) in enumerate(flat):
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        h, s, v = fn(h, s, v)
        out[i] = colorsys.hsv_to_rgb(h % 1.0, min(max(s, 0), 1), min(max(v, 0), 1))
    return out.reshape(x.shape)

def tint(x, L, rgb):
    return x + np.array(rgb) * L[..., None]

def gamma(x, g, ch=None):
    y = np.clip(x, 0, 1).copy()
    if ch is None:
        return y ** g
    y[..., ch] = y[..., ch] ** g
    return y

# ---- 메뉴 룩 ----
def look_identity(x): return x
def look_gray(x): return sat(x, 0.0)
def look_vivid(x): return scurve(sat(x, 1.5), 1.15)
def look_sepia(x):
    L = scurve(luma(x), 1.1)
    return np.stack([L, L * 0.88, L * 0.70], -1) + np.stack([0.06 * (1 - L), 0.02 * (1 - L), -0.02 * (1 - L)], -1)
def look_selenium(x):
    L = scurve(luma(x), 1.15)
    return tint(np.stack([L, L, L], -1), (1 - L) ** 1.5, (0.03, -0.02, 0.06))
def look_split(x):
    L = luma(x); y = sat(x, 0.9)
    y = tint(y, (1 - L) ** 1.5, (-0.04, 0.0, 0.08))
    return tint(y, L ** 2, (0.08, 0.03, -0.05))
def look_metropolis(x):
    def fn(h, s, v):
        deg = h * 360
        return h, s * (1.0 if (deg < 40 or deg > 335) else 0.3), v
    return scurve(sat(hsv_map(x, fn), 0.9), 1.2)
def look_crossproc(x):
    y = np.stack([scurve(x[..., 0], 1.35), scurve(x[..., 1], 1.15), 0.12 + 0.72 * x[..., 2]], -1)
    return sat(y, 1.25)
def look_faded(x): return sat(contrast(0.09 + 0.84 * x, 0.92), 0.85)
def look_fujigreen(x):
    def fn(h, s, v):
        deg = h * 360
        if 70 <= deg <= 170:
            w = 1 - abs(deg - 120) / 50
            return (deg + 18 * w) / 360, min(1, s * (1 + 0.15 * w)), v
        return h, s, v
    return hsv_map(x, fn)
def look_polaroid(x):
    y = softclip(0.06 + 0.9 * x, 0.75)
    return sat(tint(y, np.ones(y.shape[:-1]), (0.04, 0.0, -0.03)), 0.88)

# (id, 메뉴 이름(한글 12자 안팎), 설명, 함수)
LOOKS = [
    ("identity",   "항등 (확인용)",   "순정 표와 같아야 함", look_identity),
    ("gray",       "흑백 (확인용)",   "색차 0. 표가 쓰이는지 바로 보임", look_gray),
    ("vivid",      "비비드 1.5",      "채도 1.5 배, 대비 조금", look_vivid),
    ("sepia",      "세피아",          "흑백 + 따뜻한 갈색", look_sepia),
    ("selenium",   "셀레늄 토닝",     "흑백 + 그림자 보랏빛", look_selenium),
    ("split",      "스플릿 토닝",     "그림자 차갑게, 하이라이트 따뜻하게", look_split),
    ("metropolis", "메트로폴리스",    "빨강 주황만 남기고 나머지 채도 0.3", look_metropolis),
    ("crossproc",  "크로스 프로세스", "파랑 들뜸, 빨강 대비, 채도 1.25", look_crossproc),
    ("faded",      "바랜 인화",       "검정 들뜸, 대비와 채도 낮춤", look_faded),
    ("fujigreen",  "후지 녹색",       "녹색을 청록 쪽으로 18도", look_fujigreen),
    ("polaroid",   "폴라로이드",      "따뜻하고 부드러운 하이라이트", look_polaroid),
]

# ---- 검증 룩 (lutcal.sh 가 순서대로 찍고 lut_verify.py 가 예측과 비교한다. 순정 표를 합성하지 않은 순수 룩) ----
def cal_hue30(x):
    return hsv_map(x, lambda h, s, v: (h + 30 / 360, s, v))
def cal_sat16(x): return sat(x, 1.6)
def cal_sat05(x): return sat(x, 0.5)
def cal_rgam(x): return gamma(x, 0.7, 0)
def cal_bgam(x): return gamma(x, 1.5, 2)
def cal_gam(x): return gamma(x, 0.75)
def cal_ggam(x): return gamma(x, 1.3, 1)

CAL = [
    ("cal_id",    "항등", look_identity),
    ("cal_hue30", "색상 +30도", cal_hue30),
    ("cal_sat16", "채도 1.6", cal_sat16),
    ("cal_sat05", "채도 0.5", cal_sat05),
    ("cal_rgam",  "R 감마 0.7", cal_rgam),
    ("cal_ggam",  "G 감마 1.3", cal_ggam),
    ("cal_bgam",  "B 감마 1.5", cal_bgam),
    ("cal_gam",   "전체 감마 0.75", cal_gam),
]
