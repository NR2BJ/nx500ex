#!/usr/bin/env python3
# 보정 촬영용 색표: 컬러체커 24색 (sRGB 근사, BabelColor D65) 을 검은 바탕에 6x4 로. 모니터에 전체 화면으로 띄워 찍는다.
# 칸 사이를 띄워 analyze 에서 칸 위치를 자동으로 찾는다 (삼각대 없이 찍어 구도가 조금씩 달라도 됨).
# 사용: python3 calib_chart.py [출력.png]
import sys
from PIL import Image, ImageDraw

PATCHES = [
    ('어두운 피부', (115, 82, 68)), ('밝은 피부', (194, 150, 130)), ('하늘', (98, 122, 157)),
    ('잎', (87, 108, 67)), ('푸른 꽃', (133, 128, 177)), ('청록', (103, 189, 170)),
    ('주황', (214, 126, 44)), ('보라빛 파랑', (80, 91, 166)), ('빨강 중간', (193, 90, 99)),
    ('보라', (94, 60, 108)), ('연두', (157, 188, 64)), ('주황 노랑', (224, 163, 46)),
    ('파랑', (56, 61, 150)), ('초록', (70, 148, 73)), ('빨강', (175, 54, 60)),
    ('노랑', (231, 199, 31)), ('자홍', (187, 86, 149)), ('시안', (8, 133, 161)),
    ('흰색', (243, 243, 242)), ('회색 8', (200, 200, 200)), ('회색 6.5', (160, 160, 160)),
    ('회색 5', (122, 122, 121)), ('회색 3.5', (85, 85, 85)), ('검정', (52, 52, 52)),
]
W, H, COLS, ROWS = 1920, 1080, 6, 4
GAP = 40

def draw(path):
    img = Image.new('RGB', (W, H), (0, 0, 0))
    d = ImageDraw.Draw(img)
    cw = (W - GAP * (COLS + 1)) // COLS
    ch = (H - GAP * (ROWS + 1)) // ROWS
    for i, (_, rgb) in enumerate(PATCHES):
        c, r = i % COLS, i // COLS
        x, y = GAP + c * (cw + GAP), GAP + r * (ch + GAP)
        d.rectangle([x, y, x + cw - 1, y + ch - 1], fill=rgb)
    img.save(path)

if __name__ == '__main__':
    draw(sys.argv[1] if len(sys.argv) > 1 else 'calib_chart.png')
