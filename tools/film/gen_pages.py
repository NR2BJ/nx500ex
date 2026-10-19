#!/usr/bin/env python3
# 필름 레시피 메뉴 화면 만들기: sd/nx500ex/scripts/film/recipes.txt -> scripts/gui_film*.NX500
# 사용: python3 tools/film/gen_pages.py   (recipes.txt 를 바꾼 뒤 다시 실행)
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'sd', 'nx500ex', 'scripts')
CATS = [('neg', '컬러 네거티브'), ('slide', '슬라이드'), ('mono', '흑백'), ('cine', '영화'), ('style', '즉석, 스타일')]
PER_PAGE = 8   # 메뉴 한 화면의 항목 수 (nxmenu)

recipes = {}
for line in open(os.path.join(ROOT, 'film', 'recipes.txt'), encoding='utf-8'):
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    f = line.split('|')
    recipes.setdefault(f[1], []).append((f[0], f[2]))

for name in os.listdir(ROOT):
    if name.startswith('gui_film') and name.endswith('.NX500'):
        os.remove(os.path.join(ROOT, name))

def write(name, lines):
    with open(os.path.join(ROOT, name + '.NX500'), 'w', encoding='utf-8') as f:
        f.write('# 자동 생성 (tools/film/gen_pages.py)\n' + '\n'.join(lines) + '\n')

top = ['back|gui_ini']
for cat, label in CATS:
    items = recipes[cat]
    pages = []
    while items:
        n = len(items) if len(items) <= PER_PAGE else PER_PAGE - 1
        pages.append(items[:n])
        items = items[n:]
    for i, page in enumerate(pages):
        lines = ['back|' + ('gui_film' if i == 0 else 'gui_film_%s%d' % (cat, i))]
        lines += ['button|%s|film.sh %s' % (lab, rid) for rid, lab in page]
        if i + 1 < len(pages):
            lines.append('page|다음 >|gui_film_%s%d' % (cat, i + 2))
        write('gui_film_%s%d' % (cat, i + 1), lines)
    top.append('page|%s >|gui_film_%s1' % (label, cat))
top += ['button|레시피 끄기|film.sh off', 'checkbox|화이트 밸런스 유지|film_nowb.sh', 'page|촬영 도구 >|gui_film_tools']
write('gui_film', top)
write('gui_film_tools', ['back|gui_film', 'button|비교 촬영 (목록)|rshot.sh list', 'button|비교 촬영 (전체)|rshot.sh all',
                         'button|보정 촬영 (색표)|calib.sh'])
