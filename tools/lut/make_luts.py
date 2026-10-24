#!/usr/bin/env python3
"""시험용 LUT 묶음을 뱅크 파일로 만들고 메뉴 화면을 생성한다.

출력: sd/nx500ex/lut/<id>.bin (표 17 자리 하나, 19652 바이트, 저장소에 둠),
      sd/nx500ex/lut/<id>_a.bin, <id>_b.bin (42개 표 전부. 구간 A 0x810c3500 부터 20개, 구간 B 0x81123d00 부터 22개.
      lut.sh 가 쓴다. 크기가 커서 저장소에는 두지 않고 이 스크립트로 다시 만든다),
      sd/nx500ex/lut/luts.txt (id|이름|설명), scripts/gui_lut*.NX500,
      dumps/lut/preview/<id>.png 와 preview_sheet.png (PC 미리보기, 확정된 (Cr, Cb, Y) 해석).
모든 표는 카메라 원래 표 (dumps/lut/lut_a.bin) 를 먼저 거친 뒤 룩을 더한다 (순정 처리 유지).
정지 사진은 밝기, 색온도에 따라 다른 표를 고르므로 (2026-10-25 실기: 표 17 만 바꾸면 화면만 바뀌고 사진은 그대로인 경우 있음)
42개 표 전부에 같은 룩을 입힌다.
사용: cd ~/Documents/pixi && pixi run -e toy python ~/Documents/nx500ex/tools/lut/make_luts.py
"""
import os, sys, colorsys
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import cube2bank as C
import apply_lut as A

SD = os.path.join(ROOT, "sd", "nx500ex")
LUTDIR = os.path.join(SD, "lut")
SCRIPTS = os.path.join(SD, "scripts")
DUMP = os.path.join(ROOT, "dumps", "lut", "lut_a.bin")
PREVIEW = os.path.join(ROOT, "dumps", "lut", "preview")
STOCK_ADDR = 0x81115200
BASE = 0x810c3500
GRID_A = (0x810c3500, 20)   # 시작, 표 수
GRID_B = (0x81123d00, 22)
BANK = 0x4d00
PER_PAGE = 8

# ---- 색 도구 (0..1 RGB 배열) ----
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
    """knee 위를 부드럽게 눌러 1.0 에 닿게"""
    y = x.copy()
    m = x > knee
    y[m] = knee + (1 - knee) * (1 - np.exp(-(x[m] - knee) / (1 - knee)))
    return y

def hsv_map(x, fn):
    """픽셀마다 (h, s, v) -> (h, s, v) 함수 적용"""
    flat = np.clip(x.reshape(-1, 3), 0, 1)
    out = np.empty_like(flat)
    for i, (r, g, b) in enumerate(flat):
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        h, s, v = fn(h, s, v)
        out[i] = colorsys.hsv_to_rgb(h % 1.0, min(max(s, 0), 1), min(max(v, 0), 1))
    return out.reshape(x.shape)

def tint(x, L, rgb):
    return x + np.array(rgb) * L[..., None]

# ---- 룩 정의: (id, 이름(메뉴 12자 안팎), 설명, 함수) ----
def look_identity(x):
    return x

def look_gray(x):
    return sat(x, 0.0)

def look_vivid(x):
    return scurve(sat(x, 1.5), 1.15)

def look_sepia(x):
    L = luma(x)
    L = scurve(L, 1.1)
    return np.stack([L * 1.0, L * 0.88, L * 0.70], -1) + np.stack([0.06 * (1 - L), 0.02 * (1 - L), -0.02 * (1 - L)], -1)

def look_selenium(x):
    L = scurve(luma(x), 1.15)
    base = np.stack([L, L, L], -1)
    return tint(base, (1 - L) ** 1.5, (0.03, -0.02, 0.06))

def look_split(x):
    L = luma(x)
    y = sat(x, 0.9)
    y = tint(y, (1 - L) ** 1.5, (-0.04, 0.0, 0.08))     # 그림자 차갑게
    y = tint(y, L ** 2, (0.08, 0.03, -0.05))             # 하이라이트 따뜻하게
    return y

def look_metropolis(x):
    def fn(h, s, v):
        deg = h * 360
        keep = (deg < 40) or (deg > 335)
        return h, s * (1.0 if keep else 0.3), v
    y = hsv_map(x, fn)
    return scurve(sat(y, 0.9), 1.2)

def look_crossproc(x):
    r = scurve(x[..., 0], 1.35)
    g = scurve(x[..., 1], 1.15)
    b = 0.12 + 0.72 * x[..., 2]
    y = np.stack([r, g, b], -1)
    return sat(y, 1.25)

def look_faded(x):
    y = 0.09 + 0.84 * x
    return sat(contrast(y, 0.92), 0.85)

def look_fujigreen(x):
    def fn(h, s, v):
        deg = h * 360
        if 70 <= deg <= 170:
            w = 1 - abs(deg - 120) / 50
            return (deg + 18 * w) / 360, min(1, s * (1 + 0.15 * w)), v
        return h, s, v
    return hsv_map(x, fn)

def look_polaroid(x):
    y = 0.06 + 0.9 * x
    y = softclip(y, 0.75)
    y = tint(y, np.ones(y.shape[:-1]), (0.04, 0.0, -0.03))
    return sat(y, 0.88)

LOOKS = [
    ("identity",   "항등 (확인용)",   "순정 표 17 과 같아야 함", look_identity),
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

def write_pages(ids):
    for name in os.listdir(SCRIPTS):
        if name.startswith("gui_lut") and name.endswith(".NX500"):
            os.remove(os.path.join(SCRIPTS, name))
    items = [(i, n) for i, n, _, _ in ids]
    pages = []
    while items:
        n = len(items) if len(items) <= PER_PAGE - 1 else PER_PAGE - 2
        pages.append(items[:n]); items = items[n:]
    for k, page in enumerate(pages):
        lines = ["# 자동 생성 (tools/lut/make_luts.py)", "back|" + ("gui_ini" if k == 0 else "gui_lut" if k == 1 else f"gui_lut{k}")]
        lines += [f"button|{lab}|lut.sh {rid}" for rid, lab in page]
        if k == 0:
            lines.append("button|LUT 끄기|lut.sh off")
        if k + 1 < len(pages):
            lines.append(f"page|다음 >|gui_lut{k + 2}")
        fname = "gui_lut" if k == 0 else f"gui_lut{k + 1}"
        with open(os.path.join(SCRIPTS, fname + ".NX500"), "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")

def test_image():
    W = 680
    img = Image.new("RGB", (W, 420), (128, 128, 128)); dr = ImageDraw.Draw(img)
    for row, (s, v) in enumerate([(1, 1), (0.6, 1), (1, 0.6), (0.35, 0.9)]):
        for x in range(W):
            r, g, b = colorsys.hsv_to_rgb(x / W, s, v)
            dr.line([(x, row * 40), (x, row * 40 + 39)], fill=(int(r * 255), int(g * 255), int(b * 255)))
    for i in range(17):
        v = int(i * 255 / 16); dr.rectangle([i * 40, 160, i * 40 + 39, 199], fill=(v, v, v))
    patches = [(224, 172, 140), (200, 140, 110), (150, 100, 80), (135, 180, 230), (90, 130, 70), (200, 60, 50), (240, 200, 60), (60, 80, 160), (250, 250, 250), (20, 20, 20)]
    for i, c in enumerate(patches):
        dr.rectangle([i * 68, 200, i * 68 + 67, 259], fill=c)
    chart = Image.open(os.path.join(ROOT, "tools", "film", "calib_chart.png")).convert("RGB")
    chart = chart.resize((W, int(chart.height * W / chart.width)))
    img.paste(chart.crop((0, 0, W, 160)), (0, 260))
    return img

def main():
    os.makedirs(LUTDIR, exist_ok=True); os.makedirs(PREVIEW, exist_ok=True)
    d = open(DUMP, "rb").read()
    off = STOCK_ADDR - BASE
    stock = np.frombuffer(d[off:off + C.TB], dtype=np.uint8).reshape(C.N, C.N, C.N, 4)[..., :3].astype(np.float64)
    open(os.path.join(LUTDIR, "stock17.bin"), "wb").write(d[off:off + C.TB])
    img = test_image()
    tiles = [("src", img)]
    lines = ["# id|메뉴 이름|설명 (tools/lut/make_luts.py 가 만든다. 표는 lut/<id>.bin, 카메라 원래 표 17 을 먼저 거침)"]
    def region(fn, start, count):
        """구간의 표 count 개를 각각 자기 원래 표 위에 룩을 얹어 이어 붙인다 (표 사이 60바이트 패딩은 덤프 그대로)"""
        out = bytearray()
        for k in range(count):
            off = start + k * BANK - BASE
            st = np.frombuffer(d[off:off + C.TB], dtype=np.uint8).reshape(C.N, C.N, C.N, 4)[..., :3].astype(np.float64)
            out += C.make_bank(fn, st)
            if k + 1 < count:
                out += d[off + C.TB:off + BANK]
        return bytes(out)
    for rid, name, desc, fn in LOOKS:
        data = C.make_bank(fn, stock)
        open(os.path.join(LUTDIR, rid + ".bin"), "wb").write(data)
        open(os.path.join(LUTDIR, rid + "_a.bin"), "wb").write(region(fn, *GRID_A))
        open(os.path.join(LUTDIR, rid + "_b.bin"), "wb").write(region(fn, *GRID_B))
        lines.append(f"{rid}|{name}|{desc}")
        g = np.frombuffer(data, dtype=np.uint8).reshape(C.E, 4)[:, :3].astype(np.float32).reshape(C.N, C.N, C.N, 3)
        out = A.apply(g, img, "crcby")
        out.save(os.path.join(PREVIEW, rid + ".png"))
        tiles.append((rid, out))
        print(f"{rid:11s} {name}")
    with open(os.path.join(LUTDIR, "luts.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    write_pages(LOOKS)
    cols = 3; W = img.width; H = img.height
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (W + 10), rows * (H + 30)), (40, 40, 40)); dr = ImageDraw.Draw(sheet)
    for i, (name, im) in enumerate(tiles):
        x = (i % cols) * (W + 10); y = (i // cols) * (H + 30)
        dr.text((x + 4, y + 6), name, fill=(255, 255, 255)); sheet.paste(im, (x, y + 24))
    sheet.save(os.path.join(ROOT, "dumps", "lut", "preview_sheet.png"))
    print("메뉴 화면과 미리보기 생성 끝")

if __name__ == "__main__":
    main()
