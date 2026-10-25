#!/usr/bin/env python3
"""LUT 입력 공간 변환: 카메라가 LUT 에 넣는 것은 완성된 sRGB 영상이다. 로그 입력용 LUT (V-Log, S-Log3 ...) 나 선형 입력용 LUT 를
쓰려면 sRGB 값을 그 LUT 가 기대하는 공간으로 먼저 바꿔 넣어야 한다 (영상 쪽의 "709 to LOG" 변환과 같은 일).

파이프라인: sRGB 0..1 -> sRGB 역감마 -> 선형 -> x 2^ev (노출) -> 색 영역 행렬 (sRGB 선형 -> 카메라 색 영역) -> 로그 곡선 -> 0..1 -> LUT
근사인 이유: sRGB JPEG 는 이미 톤이 눌리고 255 에서 잘린 8비트라 로그 영상의 하이라이트 여유가 없다. 흰색 255 가 로그의 "90% 흰색"
자리 (코드 약 0.6) 로 가서 결과 흰색이 조금 가라앉을 수 있다 (ev 로 보정).

곡선 상수는 각 제조사 공개 문서 값이고, 행렬은 colour-science 0.4.7 로 sRGB 선형 -> 각 색 영역 (D65, CAT02) 을 유도한 것이다.
검사: tools/lut/inspace_test.py 가 colour-science 의 값과 비교한다. web/convert.js 가 같은 계산을 한다 (바이트 일치 검사 web_test.js).
"""
import numpy as np

# sRGB 선형 -> 카메라 색 영역 (행 x 열, out = M @ rgb)
MATRICES = {
    "vgamut":  [[0.585228754, 0.322656162, 0.092196105], [0.078525921, 0.819662708, 0.101781757], [0.022766089, 0.114221731, 0.862959434]],
    "sgamut3": [[0.566077827, 0.342778099, 0.091220421], [0.076899864, 0.799089495, 0.123980535], [0.022323259, 0.108616808, 0.869007953]],
    "sgamut3cine": [[0.645723475, 0.259125895, 0.095244182], [0.087472175, 0.759732834, 0.152766788], [0.036930429, 0.129286567, 0.833734666]],
    "bt2020":  [[0.627441372, 0.32929746, 0.043351458], [0.069027617, 0.919580667, 0.011361423], [0.016364235, 0.088017162, 0.895564973]],
    "cinemagamut": [[0.556185756, 0.329189024, 0.114699106], [0.082354907, 0.75750296, 0.160112721], [0.033071262, 0.22582185, 0.741058963]],
    "awg3":    [[0.631362623, 0.270812626, 0.09791522], [0.03675345, 0.793071572, 0.170134952], [0.017338777, 0.148795214, 0.833812095]],
    "awg4":    [[0.565865404, 0.340345904, 0.093864957], [0.08856502, 0.809382288, 0.102025411], [0.017721742, 0.109452414, 0.872772816]],
}

def srgb_to_linear(x):
    x = np.asarray(x, dtype=np.float64)
    return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)

def _log10(v):
    return np.log10(np.maximum(v, 1e-12))

def enc_vlog(x):          # Panasonic V-Log/V-Gamut Reference Manual
    return np.where(x < 0.01, 5.6 * x + 0.125, 0.241514 * _log10(x + 0.00873) + 0.598206)

def enc_slog3(x):         # Sony S-Log3 (10비트 코드값 / 1023)
    return np.where(x >= 0.01125, (420.0 + _log10((x + 0.01) / (0.18 + 0.01)) * 261.5) / 1023.0,
                    (x * (171.2102946929 - 95.0) / 0.01125 + 95.0) / 1023.0)

def enc_flog(x):          # Fujifilm F-Log Data Sheet 1.1
    return np.where(x >= 0.00089, 0.344676 * _log10(0.555556 * x + 0.009468) + 0.790453, 8.735631 * x + 0.092864)

def enc_flog2(x):         # Fujifilm F-Log2 Data Sheet 1.0
    return np.where(x >= 0.000889, 0.245281 * _log10(5.555556 * x + 0.064829) + 0.384316, 8.799461 * x + 0.092864)

def enc_nlog(x):          # Nikon N-Log Specification 1.0.0
    xp = np.maximum(x, 0.0)
    return np.where(xp < 0.328, (650.0 / 1023.0) * np.cbrt(xp + 0.0075), (150.0 / 1023.0) * np.log(np.maximum(xp, 1e-12)) + 619.0 / 1023.0)

def enc_clog3(x):         # Canon Log 3 (입력은 반사율 / 0.9 의 IRE 식 값)
    v = x / 0.9
    return np.where(v < -0.014, -(0.36726845 * _log10(1 - 14.98325 * v) + 0.12783901),
                    np.where(v <= 0.014, 1.9754798 * v + 0.12512219, 0.36726845 * _log10(14.98325 * v + 1) + 0.12240537))

def enc_logc3(x):         # ARRI LogC3 EI 800
    return np.where(x > 0.010591, 0.247190 * _log10(5.555556 * x + 0.052272) + 0.385537, 5.367655 * x + 0.092809)

def enc_logc4(x):         # ARRI LogC4
    a = (2.0 ** 18 - 16.0) / 117.45
    b = (1023.0 - 95.0) / 1023.0
    c = 95.0 / 1023.0
    s = 7.0 * np.log(2.0) * 2.0 ** (7.0 - 14.0 * c / b) / (a * b)
    t = (2.0 ** (14.0 * (-c / b) + 6.0) - 64.0) / a
    return np.where(x >= t, (np.log2(np.maximum(a * x + 64.0, 1e-12)) - 6.0) / 14.0 * b + c, (x - t) / s)

def enc_pq(x):            # SMPTE ST 2084, 선형 1.0 = 100 nit
    y = np.maximum(x, 0.0) * 100.0 / 10000.0
    m1 = 2610.0 / 16384.0; m2 = 2523.0 / 4096.0 * 128.0
    c1 = 3424.0 / 4096.0; c2 = 2413.0 / 4096.0 * 32.0; c3 = 2392.0 / 4096.0 * 32.0
    ym = y ** m1
    return ((c1 + c2 * ym) / (1.0 + c3 * ym)) ** m2

def enc_hlg(x):           # ITU-R BT.2100 HLG OETF, 장면 선형 1.0 = 1000 nit 로 두고 sRGB 흰색 (100 nit) 을 0.1 에 둠
    e = np.maximum(x, 0.0) * 0.1
    return np.where(e <= 1.0 / 12.0, np.sqrt(3.0 * e), 0.17883277 * np.log(np.maximum(12.0 * e - 0.28466892, 1e-12)) + 0.55991073)

# id -> (이름, 색 영역 행렬 키 또는 None, 곡선 함수 또는 None)
SPACES = {
    "srgb":       ("sRGB / Rec.709 완성 영상 (기본)", None, None),
    "linear":     ("선형 sRGB (linear)", None, "linear"),
    "vlog":       ("Panasonic V-Log / V-Gamut", "vgamut", enc_vlog),
    "slog3cine":  ("Sony S-Log3 / S-Gamut3.Cine", "sgamut3cine", enc_slog3),
    "slog3":      ("Sony S-Log3 / S-Gamut3", "sgamut3", enc_slog3),
    "flog":       ("Fujifilm F-Log / F-Gamut", "bt2020", enc_flog),
    "flog2":      ("Fujifilm F-Log2 / F-Gamut", "bt2020", enc_flog2),
    "nlog":       ("Nikon N-Log / BT.2020", "bt2020", enc_nlog),
    "clog3":      ("Canon Log 3 / Cinema Gamut", "cinemagamut", enc_clog3),
    "logc3":      ("ARRI LogC3 EI800 / Wide Gamut 3", "awg3", enc_logc3),
    "logc4":      ("ARRI LogC4 / Wide Gamut 4", "awg4", enc_logc4),
    "hlg":        ("HLG / BT.2020 (참고용)", "bt2020", enc_hlg),
    "pq":         ("PQ ST 2084 / BT.2020 (참고용, 흰색 100 nit)", "bt2020", enc_pq),
}

def to_space(x, space, ev=0.0):
    """x: sRGB 0..1 (..., 3) -> 그 LUT 의 입력 공간 0..1 (자르지 않음, 호출 쪽에서 LUT 가 자른다)"""
    if space == "srgb":
        return x
    name, gamut, enc = SPACES[space]
    lin = srgb_to_linear(np.clip(x, 0.0, 1.0)) * (2.0 ** ev)
    if gamut is not None:
        m = np.array(MATRICES[gamut])
        lin = lin @ m.T
    if enc == "linear":
        return lin
    return enc(lin)

# 파일 이름이나 .cube 태그로 입력 공간 추정
def guess_space(filename, cube_text=None):
    import re
    if cube_text:
        m = re.search(r"^\s*#\s*LUMIXPHOTOSTYLE\s+(\S+)", cube_text, re.M | re.I)
        if m:
            return "vlog" if "LOG" in m.group(1).upper() else "srgb"
    n = filename.lower()
    for pat, sp in [(r"s-?log3|slog3", "slog3cine"), (r"s-?log2|slog2", "slog3cine"), (r"v-?log", "vlog"), (r"f-?log2", "flog2"), (r"f-?log", "flog"),
                    (r"n-?log", "nlog"), (r"c-?log3|clog3|canon.?log", "clog3"), (r"logc4|log-?c4", "logc4"), (r"logc|log-?c|alexa|arri", "logc3"),
                    (r"hlg", "hlg"), (r"\bpq\b|st2084|2084", "pq"), (r"linear|_lin[_.]|acescg", "linear")]:
        if re.search(pat, n):
            return sp
    return "srgb"

# ---- LUT 내용으로 입력 공간 판별 ----
# 회색 램프를 각 후보 공간으로 바꿔 LUT 에 넣었을 때 출력 밝기가 입력 램프와 가장 비슷한 공간이 그 LUT 의 입력 공간이다.
# 로그용 LUT 에 sRGB 를 그대로 넣으면 (sRGB 0.3 은 로그로 2~3 스톱 아래) 대비가 폭주해 오차가 크다. 로그끼리는 곡선이 비슷해 구분이 약하므로
# 1위와 2위 차이로 확신도를 같이 돌려준다. 이름 힌트가 있으면 그쪽을 우선한다 (페이지에서).
DETECT_SPACES = ["srgb", "vlog", "slog3cine", "flog", "flog2", "nlog", "clog3", "logc3", "logc4", "linear"]

# 색 패치 (피부, 하늘, 잎, 빨강, 노랑, 파랑, 자홍, 청록): 색 영역이 다르면 회색은 맞아도 색이 어긋나므로 로그끼리 구분에 쓴다 (가중치 0.5)
DETECT_PATCHES = np.array([[224, 172, 140], [135, 180, 230], [90, 130, 70], [200, 60, 50], [240, 200, 60], [60, 80, 160], [180, 90, 160], [60, 170, 170]], dtype=np.float64) / 255.0
DETECT_GRAY = np.linspace(0.08, 1.0, 12)

def detect_space(func_of_space, spaces=DETECT_SPACES):
    """func_of_space(space) -> 룩 함수 (sRGB 0..1 -> RGB 0..1). 반환: [(space, 오차), ...] 오차 오름차순.
    오차 = 회색 램프 밝기의 RMS 오차 + 0.5 x 색 패치 RGB 의 RMS 오차 (+0.5 회색이 뒤집힐 때)"""
    xs = DETECT_GRAY
    gray = np.stack([xs, xs, xs], -1)
    out = []
    for sp in spaces:
        f = func_of_space(sp)
        y = np.clip(f(gray), 0, 1)
        Y = 0.2126 * y[:, 0] + 0.7152 * y[:, 1] + 0.0722 * y[:, 2]
        err = float(np.sqrt(np.mean((Y - xs) ** 2)))
        if np.any(np.diff(Y) < -0.02):
            err += 0.5
        pc = np.clip(f(DETECT_PATCHES), 0, 1)
        err += 0.5 * float(np.sqrt(np.mean((pc - DETECT_PATCHES) ** 2)))
        out.append((sp, err))
    out.sort(key=lambda t: t[1])
    return out

def detect_summary(ranked):
    """(최선 공간, 확신 '높음'/'낮음', 설명)"""
    best, e1 = ranked[0]
    second, e2 = ranked[1] if len(ranked) > 1 else (None, e1 + 1)
    margin = e2 - e1
    if best == "srgb":
        return best, ("높음" if margin > 0.03 else "낮음"), f"회색 램프 오차 {e1:.3f}, 다음 후보 {second} {e2:.3f}"
    # 로그끼리는 가까우므로 '로그 계열' 임은 확실해도 어느 로그인지는 낮음일 수 있다
    srgb_err = dict(ranked).get("srgb", 1.0)
    sure_log = srgb_err - e1 > 0.05
    conf = "높음" if (sure_log and margin > 0.02) else "낮음"
    return best, conf, f"회색 램프 오차 {e1:.3f} (sRGB 로 넣으면 {srgb_err:.3f}), 다음 후보 {second} {e2:.3f}"
