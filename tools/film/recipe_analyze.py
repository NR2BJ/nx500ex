#!/usr/bin/env python3
# 레시피 비교 촬영 분석 (sd/nx500ex/scripts/rshot.sh 의 결과).
# 사용: python3 recipe_analyze.py <사진 폴더> <jobs.log> [--scene]
#   jobs.log 의 마지막 "rshot start" 뒤 "rshot <이름> <값> -> <파일>" 줄로 사진과 레시피를 잇는다. 첫 장 base 는 중립(기준).
#   색표(calib_chart.png)를 찍었으면: 레시피마다 기준 대비 회색 기울기(밝은 쪽, 중간, 어두운 쪽), 색 계열별 채도 비, 피부, 하늘, 잎의
#   색상각 변화, 톤(회색 L, 대비), 날아간 칸을 표로 내고, 잰 색을 레시피별 한 줄씩 칠한 swatches.png 를 만든다.
#   --scene (실제 장면): 수치는 건너뛰고 비교 시트만 만든다.
#   어느 쪽이든 사진들을 이름표와 함께 나란히 놓은 sheet.jpg 를 사진 폴더에 만든다.
import sys, os, re
import numpy as np
from PIL import Image, ImageDraw
from calib_analyze import patches, srgb_to_lab, NAMES

GROUPS = {'피부': (0, 1), '빨강': (6, 8, 14, 16), '노랑': (11, 15), '녹색': (3, 10, 13), '파랑': (2, 7, 12, 17)}
TONES = {'밝은 쪽': (18, 19), '중간': (20, 21), '어두운 쪽': (22, 23)}
HUES = {'피부': 1, '하늘': 2, '잎': 3}

def shots_from_log(log):
    shots = []
    for line in open(log, encoding='utf-8'):
        if re.search(r' rshot start ', line):
            shots = []
        m = re.search(r' rshot (\S+) ([-\w ]+?) -> (\S+)', line)
        if m:
            shots.append((m.group(1), m.group(2).split(), m.group(3)))
    return shots

def cast(a, b):
    # 회색 기울기를 말로: a+ 자홍, a- 녹색, b+ 노랑(따뜻), b- 파랑(차가움). 1.5 미만은 중립
    w = []
    if b >= 1.5: w.append('따뜻')
    if b <= -1.5: w.append('차가움')
    if a >= 1.5: w.append('자홍')
    if a <= -1.5: w.append('녹색')
    return ','.join(w) or '중립'

def sheet(folder, shots, out, cols=4, tw=480):
    th = tw * 2 // 3
    rows = (len(shots) + cols - 1) // cols
    im = Image.new('RGB', (cols * tw, rows * (th + 22)), (20, 20, 20))
    d = ImageDraw.Draw(im)
    for i, (n, v, f) in enumerate(shots):
        t = Image.open(os.path.join(folder, f))
        t.draft('RGB', (tw * 2, th * 2))
        t = t.convert('RGB').resize((tw, th))
        x, y = (i % cols) * tw, (i // cols) * (th + 22)
        im.paste(t, (x, y + 22))
        d.text((x + 4, y + 5), '%s  %s' % (n, ' '.join(v)), fill=(230, 230, 230))
    im.save(out, quality=90)

def main():
    folder, log = sys.argv[1], sys.argv[2]
    shots = shots_from_log(log)
    if not shots or shots[0][0] != 'base':
        sys.exit('jobs.log 에 rshot base 로 시작하는 촬영이 없음')
    sheet(folder, shots, os.path.join(folder, 'sheet.jpg'))
    print('비교 시트:', os.path.join(folder, 'sheet.jpg'))
    if '--scene' in sys.argv:
        return
    lab, rgb = {}, {}
    for n, v, f in shots:
        rgb[n] = patches(os.path.join(folder, f))
        lab[n] = srgb_to_lab(rgb[n])
    base = lab['base']
    ch = lambda l: np.hypot(l[:, 1], l[:, 2])
    hue = lambda l: np.degrees(np.arctan2(l[:, 2], l[:, 1]))
    print()
    print('회색 기울기 (기준 대비 a/b, a+ 자홍 a- 녹색 b+ 노랑 b- 파랑. 기준 자체의 회색 a/b (모니터, 조명 탓): %s)' %
          ' '.join('%+.1f/%+.1f' % (base[i, 1], base[i, 2]) for i in range(18, 24)))
    for n, v, f in shots[1:]:
        l = lab[n]
        parts = []
        for t, idx in TONES.items():
            da = (l[list(idx), 1] - base[list(idx), 1]).mean(); db = (l[list(idx), 2] - base[list(idx), 2]).mean()
            parts.append('%s %+5.1f/%+5.1f %-6s' % (t, da, db, cast(da, db)))
        print('  %-14s %s' % (n, '  '.join(parts)))
    print()
    print('채도 비 (기준 = 1.00) 와 색상각 변화 (+ 는 빨강 -> 노랑 -> 녹색 -> 파랑 방향)')
    for n, v, f in shots[1:]:
        l = lab[n]
        r = ch(l) / np.maximum(ch(base), 1)
        dh = ((hue(l) - hue(base) + 180) % 360) - 180
        print('  %-14s 전체 %.2f  %s  |  %s' % (n, r[:18].mean(),
              '  '.join('%s %.2f' % (g, r[list(i)].mean()) for g, i in GROUPS.items()),
              '  '.join('%s %s' % (h, '%+.0f도' % dh[i] if ch(l)[i] >= 3 else '-') for h, i in HUES.items())))
    print()
    print('톤 (회색 칸 L: 흰색 8 6.5 5 3.5 검정, 대비 = 회색 8 - 회색 3.5, 날아감 = 채널 250 이상 또는 5 이하인 칸)')
    for n, v, f in shots:
        l = lab[n]; g = l[18:24, 0]
        clip = int(((rgb[n] >= 250) | (rgb[n] <= 5)).any(axis=1).sum())
        print('  %-14s %s  대비 %.1f (기준 대비 %+.1f)  날아감 %d칸' % (n, ' '.join('%5.1f' % x for x in g), g[1] - g[4],
              (g[1] - g[4]) - (base[19, 0] - base[22, 0]), clip))
    # 잰 색을 레시피별 한 줄로 칠한 그림 (레시피끼리 눈으로 비교)
    sw, lw = 40, 160
    im = Image.new('RGB', (lw + 24 * sw, len(shots) * sw), (0, 0, 0))
    d = ImageDraw.Draw(im)
    for k, (n, v, f) in enumerate(shots):
        d.text((4, k * sw + 14), n, fill=(230, 230, 230))
        for i in range(24):
            c = tuple(int(x) for x in rgb[n][i])
            d.rectangle([lw + i * sw, k * sw + 2, lw + (i + 1) * sw - 3, (k + 1) * sw - 3], fill=c)
    im.save(os.path.join(folder, 'swatches.png'))
    print()
    print('색 줄표:', os.path.join(folder, 'swatches.png'), '(칸 순서:', ', '.join(NAMES) + ')')

if __name__ == '__main__':
    main()
