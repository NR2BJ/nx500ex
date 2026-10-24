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

# ---- 필름 레시피용 룩 (recipes.txt 의 12번째 칸. 화면 마법사가 WB, 선명도, 큰 대비와 채도를 맡고 여기서는 색의 모양만) ----
def rl_sepia(x):
    """흑백(화면 마법사 채도 0) 에 갈색 토닝. 실제 세피아 인화는 회색이 Lab b +12 ~ +20"""
    L = luma(x)
    return np.stack([np.minimum(L * 1.02 + 0.02, 1.0), L * 0.91, L * 0.74], -1)
def rl_selenium(x):
    """흑백에 셀레늄 토닝: 그림자가 차가운 자주빛, 검정이 조금 더 깊게"""
    L = luma(x)
    L2 = np.clip(L * 1.04 - 0.02, 0, 1)
    return tint(np.stack([L2, L2, L2], -1), (1 - L2) ** 1.5, (0.035, -0.02, 0.06))
def rl_metropolis(x):
    """LomoChrome Metropolis: 빨강 주황만 남기고 노랑 녹색은 올리브로 탈색, 파랑은 반"""
    def fn(h, s, v):
        deg = h * 360
        if deg < 40 or deg > 335:
            return h, s, v
        if deg <= 170:
            w = min(1, (deg - 40) / 20)             # 주황에서 노랑으로 넘어가며 빠르게 탈색
            return (deg - 8 * w) / 360, s * (1 - 0.65 * w), v
        return h, s * 0.5, v
    return hsv_map(x, fn)
def rl_polaroid600(x):
    """Polaroid 600: 따뜻한 하이라이트, 녹색 쪽 섀도, 바랜 블랙, 좁은 관용도"""
    L = luma(x)
    y = softclip(0.05 + 0.93 * x, 0.8)
    y = tint(y, (1 - L) ** 1.5, (-0.02, 0.03, -0.01))
    return tint(y, L ** 2, (0.06, 0.02, -0.04))
def rl_sx70(x):
    """Polaroid SX-70: 따뜻한 자홍 기운, 몽환적 (들뜬 블랙, 부드러운 하이라이트, 중간 톤 자홍)"""
    L = luma(x)
    y = softclip(0.06 + 0.9 * x, 0.75)
    return tint(y, 4 * L * (1 - L), (0.03, -0.02, 0.02))
def rl_pro160ns(x):
    """Fuji Pro 160NS: 후지 녹색 (녹색만 청록 쪽으로), 하이라이트 롤오프"""
    def fn(h, s, v):
        deg = h * 360
        if 80 <= deg <= 170:
            w = 1 - abs(deg - 125) / 45
            return (deg + 15 * w) / 360, min(1, s * (1 + 0.1 * w)), v
        return h, s, v
    return softclip(hsv_map(x, fn), 0.85)
def rl_crossproc(x):
    """크로스 프로세스: 시안 녹색 섀도, 노랑 하이라이트 (대비와 채도는 화면 마법사)"""
    L = luma(x)
    y = tint(x, (1 - L) ** 1.5, (-0.05, 0.03, 0.04))
    return tint(y, L ** 2, (0.03, 0.02, -0.06))
def rl_faded(x):
    """바랜 인화: 들뜬 블랙 (톤 곡선 바닥 올리기)"""
    return 0.07 + 0.93 * x

RECIPE_LOOKS = [
    ("rl_sepia",      "세피아 토닝 (레시피)",   "흑백 위 갈색 토닝", rl_sepia),
    ("rl_selenium",   "셀레늄 토닝 (레시피)",   "흑백 위 그림자 자주빛", rl_selenium),
    ("rl_metropolis", "Metropolis (레시피)",   "빨강 주황만 남김", rl_metropolis),
    ("rl_polaroid600","Polaroid 600 (레시피)", "스플릿 토닝, 바랜 블랙", rl_polaroid600),
    ("rl_sx70",       "SX-70 (레시피)",        "자홍 기운, 몽환적", rl_sx70),
    ("rl_pro160ns",   "Pro 160NS (레시피)",    "후지 녹색, 롤오프", rl_pro160ns),
    ("rl_crossproc",  "크로스 프로세스 (레시피)","시안 섀도, 노랑 하이라이트", rl_crossproc),
    ("rl_faded",      "바랜 인화 (레시피)",     "들뜬 블랙", rl_faded),
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
