#!/usr/bin/env python3
"""LUT 묶음을 뱅크 파일로 만들고 메뉴 화면을 생성한다.

출력 (sd/nx500ex/lut/):
  <id>_a.bin, <id>_b.bin   42개 표 전부 (구간 A 0x810c3500 부터 20개, 구간 B 0x81123d00 부터 22개). lut.sh 가 쓴다.
                           표마다 자기 원래 표 (dumps/lut/lut_a.bin) 위에 룩을 얹어 순정의 상황별 처리를 유지한다.
                           커서 저장소에는 두지 않고 이 스크립트로 다시 만든다.
  <id>.bin                 표 17 자리 하나 (참고, 미리보기용)
  luts.txt                 메뉴 룩 목록 id|이름|설명 (add_cube.py 가 뒤에 덧붙인다)
  cal_*.bin, cal_*_a/_b    검증 룩 (looks.py CAL, 순정 표 합성 없음). lutcal.sh 가 cal.txt 순서로 찍는다
scripts/gui_lut*.NX500 (luts.txt 로 생성), dumps/lut/preview/<id>.png, preview_sheet.png.
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
import looks

SD = os.path.join(ROOT, "sd", "nx500ex")
LUTDIR = os.path.join(SD, "lut")
SCRIPTS = os.path.join(SD, "scripts")
DUMP = os.path.join(ROOT, "dumps", "lut", "lut_a.bin")
PREVIEW = os.path.join(ROOT, "dumps", "lut", "preview")
STOCK_ADDR = 0x81115200
PER_PAGE = 8

def read_list(path):
    out = []
    for line in open(path, encoding="utf-8"):
        s = line.strip()
        if s and not s.startswith("#"):
            f = s.split("|")
            out.append((f[0], f[1], f[2] if len(f) > 2 else ""))
    return out

def gen_menu():
    """luts.txt -> gui_lut, gui_lut2, ... (한 화면 8칸: 첫 화면은 룩 6 + 끄기 + 다음, 나머지는 룩 7 + 다음)"""
    for name in os.listdir(SCRIPTS):
        if name.startswith("gui_lut") and name.endswith(".NX500"):
            os.remove(os.path.join(SCRIPTS, name))
    items = [(i, n) for i, n, _ in read_list(os.path.join(LUTDIR, "luts.txt"))]
    pages = []
    first = True
    while items:
        room = PER_PAGE - 1 if first else PER_PAGE        # 첫 화면은 "LUT 끄기" 자리
        n = len(items) if len(items) <= room else room - 1   # 넘치면 "다음 >" 자리
        pages.append(items[:n]); items = items[n:]; first = False
    for k, page in enumerate(pages):
        back = "gui_ini" if k == 0 else "gui_lut" if k == 1 else f"gui_lut{k}"
        lines = ["# 자동 생성 (tools/lut/make_luts.py, lut/luts.txt)", "back|" + back]
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

def write_look(rid, fn, dump, compose, preview_img=None):
    """룩 하나를 <id>.bin, <id>_a.bin, <id>_b.bin 으로. preview_img 가 있으면 미리보기도"""
    off = STOCK_ADDR - C.BASE
    stock = C.load_bank(dump[off:off + C.TB]) if compose else None
    data = C.make_bank(fn, stock)
    open(os.path.join(LUTDIR, rid + ".bin"), "wb").write(data)
    a, b = C.make_regions(fn, dump, compose)
    open(os.path.join(LUTDIR, rid + "_a.bin"), "wb").write(a)
    open(os.path.join(LUTDIR, rid + "_b.bin"), "wb").write(b)
    if preview_img is not None:
        g = np.frombuffer(data, dtype=np.uint8).reshape(C.E, 4)[:, :3].astype(np.float32).reshape(C.N, C.N, C.N, 3)
        out = A.apply(g, preview_img, "crcby")
        out.save(os.path.join(PREVIEW, rid + ".png"))
        return out

def main():
    os.makedirs(LUTDIR, exist_ok=True); os.makedirs(PREVIEW, exist_ok=True)
    dump = open(DUMP, "rb").read()
    off = STOCK_ADDR - C.BASE
    open(os.path.join(LUTDIR, "stock17.bin"), "wb").write(dump[off:off + C.TB])
    img = test_image()
    tiles = [("src", img)]
    lines = ["# id|메뉴 이름|설명 (tools/lut/make_luts.py 가 만들고 add_cube.py 가 덧붙인다. 표는 lut/<id>_a.bin, _b.bin, 순정 표 합성)"]
    for rid, name, desc, fn in looks.LOOKS:
        tiles.append((rid, write_look(rid, fn, dump, True, img)))
        lines.append(f"{rid}|{name}|{desc}")
        print(f"{rid:11s} {name}")
    # 이미 add_cube.py 로 더한 룩은 유지
    old = os.path.join(LUTDIR, "luts.txt")
    if os.path.exists(old):
        known = {l.split("|")[0] for l in lines}
        for rid, name, desc in read_list(old):
            if rid not in known and os.path.exists(os.path.join(LUTDIR, rid + "_a.bin")):
                lines.append(f"{rid}|{name}|{desc}")
    with open(old, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    cal_lines = ["# 검증 룩 순서 (lutcal.sh 가 이 순서로 찍는다). 순정 표 합성 없음"]
    for rid, name, fn in looks.CAL:
        write_look(rid, fn, dump, False)
        cal_lines.append(f"{rid}|{name}")
        print(f"{rid:11s} {name} (검증)")
    with open(os.path.join(LUTDIR, "cal.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(cal_lines) + "\n")
    gen_menu()
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
