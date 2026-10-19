#!/usr/bin/env python3
# 보정 촬영 분석: calib_chart.png 를 찍은 JPEG 에서 24칸을 찾아 칸마다 평균 색을 재고, 기준 사진과 비교한다.
# 사용: python3 calib_analyze.py <사진 폴더> <jobs.log>   (jobs.log 의 "calib <이름> <값> -> <파일>" 줄로 사진과 설정을 잇는다)
# 칸 찾기: 밝은 칸(최대 채널 > 문턱)의 가로, 세로 투영으로 표 전체 범위를 잡고 6x4 로 나눈다. 칸 가운데 40% 만 잰다 (렌즈 왜곡, 주변 어두워짐 피함).
import sys, os, re, math
import numpy as np
from PIL import Image

COLS, ROWS = 6, 4
NAMES = ['어두운 피부', '밝은 피부', '하늘', '잎', '푸른 꽃', '청록', '주황', '보라빛 파랑', '빨강 중간', '보라', '연두', '주황 노랑',
         '파랑', '초록', '빨강', '노랑', '자홍', '시안', '흰색', '회색 8', '회색 6.5', '회색 5', '회색 3.5', '검정']
GRAYS = range(18, 24)
CHROMA = range(0, 18)

def srgb_to_lab(rgb):
    c = np.asarray(rgb, float) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)

def span(prof, thr):
    idx = np.where(prof > thr)[0]
    return idx[0], idx[-1]

def patches(path, debug=None):
    im = Image.open(path).convert('RGB')
    im.thumbnail((1200, 800))
    a = np.asarray(im).astype(float)
    mask = a.max(axis=2) > 70
    x0, x1 = span(mask.mean(axis=0), 0.15)
    y0, y1 = span(mask.mean(axis=1), 0.15)
    cw, ch = (x1 - x0) / COLS, (y1 - y0) / ROWS
    out = []
    for i in range(COLS * ROWS):
        c, r = i % COLS, i // COLS
        cx, cy = x0 + (c + 0.5) * cw, y0 + (r + 0.5) * ch
        sx, sy = cw * 0.2, ch * 0.2
        box = a[int(cy - sy):int(cy + sy), int(cx - sx):int(cx + sx)]
        out.append(box.reshape(-1, 3).mean(axis=0))
    if debug:
        from PIL import ImageDraw
        d = ImageDraw.Draw(im)
        for i in range(COLS * ROWS):
            c, r = i % COLS, i // COLS
            cx, cy = x0 + (c + 0.5) * cw, y0 + (r + 0.5) * ch
            d.rectangle([cx - cw * 0.2, cy - ch * 0.2, cx + cw * 0.2, cy + ch * 0.2], outline=(255, 255, 255))
        im.save(debug)
    return np.array(out)

def main():
    folder, log = sys.argv[1], sys.argv[2]
    shots = []
    for line in open(log, encoding='utf-8'):
        m = re.search(r'calib (\S+) ([-\d ]+) -> (\S+)', line)
        if m:
            shots.append((m.group(1), m.group(2).split(), m.group(3)))
    rgb = {n: patches(os.path.join(folder, f), os.path.join(folder, 'dbg_' + n + '.png') if n == 'base' else None) for n, v, f in shots}
    lab = {n: srgb_to_lab(v) for n, v in rgb.items()}
    def chroma(l): return np.hypot(l[:, 1], l[:, 2])
    def hue(l): return np.degrees(np.arctan2(l[:, 2], l[:, 1]))
    base = lab['base']
    print('기준 사진 칸 (sRGB 평균, Lab)')
    for i in range(24):
        print('  %-8s RGB %5.0f %5.0f %5.0f   L %5.1f a %6.1f b %6.1f' % ((NAMES[i],) + tuple(rgb['base'][i]) + tuple(base[i])))
    print()
    for n, v, f in shots:
        if n == 'base' or n.startswith('mono'):
            continue
        l = lab[n]
        dc = (chroma(l)[list(CHROMA)] / chroma(base)[list(CHROMA)]).mean()
        dh = (((hue(l) - hue(base) + 180) % 360) - 180)[list(CHROMA)]
        g = l[list(GRAYS)]; gb = base[list(GRAYS)]
        print('%-6s %-30s 채도 비 %.2f  색상각 변화 평균 %+5.1f도 (범위 %+.1f..%+.1f)  회색 a %+5.1f b %+5.1f  회색 L 변화 %s' % (
            n, ' '.join(v), dc, dh.mean(), dh.min(), dh.max(), (g[:, 1] - gb[:, 1]).mean(), (g[:, 2] - gb[:, 2]).mean(),
            ' '.join('%+.1f' % x for x in g[:, 0] - gb[:, 0])))
    print()
    print('흑백: 칸별 밝기 L (빨강, 초록, 파랑, 노랑, 하늘, 피부 밝음)')
    for n, v, f in shots:
        if n.startswith('mono'):
            l = lab[n]
            print('  %-10s %s  채도 평균 %.1f' % (n, '  '.join('%s %.1f' % (NAMES[i], l[i, 0]) for i in (14, 13, 12, 15, 2, 1)), chroma(l).mean()))

main()
