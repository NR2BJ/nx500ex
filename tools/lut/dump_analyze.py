#!/usr/bin/env python3
"""3D LUT 뱅크 덤프 분석기.

nxmem 으로 뜬 이미지 처리 RTOS 메모리 덤프(기본 0x810c3500 부터)에서 17x17x17 표를 찾아
형식, 축 순서, 표마다의 성격을 요약한다. 항목은 4바이트 (c0, c1, c2, 0) = (Cr, Cb, Y, 0), c0 이 가장 빠른 축 (2026-10-25 실기 확정).

사용: python3 dump_analyze.py lut_a.bin [--base 0x810c3500] [--cube 폴더] [--verbose]
"""
import sys, hashlib, argparse
import numpy as np

N = 17
E = N ** 3
TB = E * 4            # 19652
BANK = 0x4d00         # 19712

def find_starts(d, tol=64):
    """패딩 바이트가 표 전체에서 0 이고, 가장 빠른 축을 따라 c0 이 (줄 경계 빼고) 거의 단조 증가하는 위치."""
    arr = np.frombuffer(d, dtype=np.uint8)
    ne = len(arr) // 4
    ent = arr[:ne * 4].reshape(ne, 4)
    padz = (ent[:, 3] == 0).astype(np.int64)
    c0 = ent[:, 0].astype(int)
    bad = (np.diff(c0) < 0).astype(np.int64)
    cs_pad = np.concatenate([[0], np.cumsum(padz)])
    cs_bad = np.concatenate([[0], np.cumsum(bad)])
    res = np.arange(ne - 1) % N
    cs_res = [np.concatenate([[0], np.cumsum(bad * (res == r))]) for r in range(N)]
    starts = []
    e = 0
    while e <= ne - E:
        if cs_pad[e + E] - cs_pad[e] == E:
            tot = cs_bad[e + E - 1] - cs_bad[e]
            r = (e + N - 1) % N
            allowed = cs_res[r][e + E - 1] - cs_res[r][e]
            if tot - allowed <= tol:
                rows = c0[e:e + E].reshape(N * N, N)
                g = ent[e:e + E, :3].astype(int).reshape(N, N, N, 3)
                m = mono(g)
                # 줄마다 c0 이 거의 전 범위를 훑고, mid/slow 축도 단조여야 진짜 시작 (줄 단위로 어긋나면 mid 가 0.94 로 떨어짐)
                if (rows[:, -1] - rows[:, 0]).mean() > 150 and m["mid"][1] >= 0.98 and m["slow"][2] >= 0.98:
                    starts.append(e * 4)
                    e += E
                    continue
        e += 1
    return starts

def load(d, off):
    t = np.frombuffer(d[off:off + TB], dtype=np.uint8).reshape(E, 4)[:, :3].astype(int)
    return t.reshape(N, N, N, 3)   # [slow, mid, fast, comp]

def mono(g):
    out = {}
    for name, ax in (("fast", 2), ("mid", 1), ("slow", 0)):
        dif = np.diff(g, axis=ax)
        out[name] = [float((dif[..., c] >= 0).mean()) for c in range(3)]
    return out

def corners(g):
    L = N - 1
    return {
        "검정": g[0, 0, 0], "흰": g[L, L, L],
        "fast": g[0, 0, L], "mid": g[0, L, 0], "slow": g[L, 0, 0],
        "fast+mid": g[0, L, L], "fast+slow": g[L, 0, L], "mid+slow": g[L, L, 0],
    }

def ycc_stats(g):
    """(c0, c1, c2) = (Cr, Cb, Y) 로 보고, 중립축 통과와 Y 대역별 색차 이득, 회전을 잰다."""
    grid = np.linspace(0, 255, N)
    neutral = g[:, 8, 8, :]                       # a=b=128, Y 변화
    rows = []
    for yi in (2, 5, 8, 11, 14):                  # Y = 32, 80, 128, 176, 224
        gains, rots = [], []
        for j in range(N):
            for k in range(N):
                a, b = grid[k] - 128, grid[j] - 128
                r = (a * a + b * b) ** 0.5
                if r < 40 or r > 100:
                    continue
                oa, ob = g[yi, j, k, 0] - 128, g[yi, j, k, 1] - 128
                gains.append(((oa * oa + ob * ob) ** 0.5) / r)
                rots.append((np.degrees(np.arctan2(ob, oa) - np.arctan2(b, a)) + 180) % 360 - 180)
        rows.append((int(grid[yi]), float(np.mean(gains)), float(np.mean(rots)), float(np.std(rots))))
    return neutral, rows

def write_cube(g, path, title):
    """주의: 표 자체를 그대로 쓴다 (YCbCr 표라면 RGB .cube 로 바로 쓸 수 없음). 미리보기는 apply_lut.py 를 쓴다."""
    with open(path, "w") as f:
        f.write(f'TITLE "{title}"\nLUT_3D_SIZE {N}\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\n')
        for rgb in g.reshape(E, 3):
            f.write("%.6f %.6f %.6f\n" % tuple(v / 255.0 for v in rgb))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("--base", type=lambda x: int(x, 0), default=0x810c3500)
    ap.add_argument("--cube")
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()
    d = open(a.dump, "rb").read()
    starts = find_starts(d)
    print(f"덤프 {len(d)} 바이트 ({a.base:08x}..{a.base + len(d):08x}), 표 {len(starts)} 개")
    prev_end = 0
    fams = {}
    for k, off in enumerate(starts):
        g = load(d, off)
        h = hashlib.md5(d[off:off + TB]).hexdigest()[:8]
        c = corners(g)
        fam = (tuple(c["검정"]), tuple(c["흰"]))
        fams.setdefault(fam, []).append(k)
        gap = off - prev_end
        m = mono(g)
        gray = g[np.arange(N), np.arange(N), np.arange(N)]
        print(f"\n표 {k:2d} @ {a.base + off:08x}  앞 틈 {gap:#x}  md5 {h}")
        print("  모서리: " + "  ".join(f"{n} {tuple(int(x) for x in v)}" for n, v in c.items()))
        print(f"  단조 fast {m['fast'][0]:.2f} mid {m['mid'][1]:.2f} slow {m['slow'][2]:.2f}")
        print("  대각 (k,k,k) c0:", " ".join(f"{int(v):3d}" for v in gray[:, 0]))
        print("              c1:", " ".join(f"{int(v):3d}" for v in gray[:, 1]))
        print("              c2:", " ".join(f"{int(v):3d}" for v in gray[:, 2]))
        neutral, bands = ycc_stats(g)
        print("  중립축 (128,128,Y) -> c2:", " ".join(f"{int(v):3d}" for v in neutral[:, 2]))
        print("                     c0:", " ".join(f"{int(v):3d}" for v in neutral[:, 0]))
        print("                     c1:", " ".join(f"{int(v):3d}" for v in neutral[:, 1]))
        if a.verbose:
            for y, gain, rot, sd in bands:
                print(f"  Y={y:3d}: 색차 이득 x{gain:.2f} 회전 {rot:+.0f}도 (편차 {sd:.0f})")
        if a.cube:
            write_cube(g, f"{a.cube}/t{k:02d}_{a.base + off:08x}.cube", f"nx500 table {k} @ {a.base + off:08x}")
        prev_end = off + TB
    print("\n검정/흰 모서리로 나눈 가족:")
    for fam, ks in fams.items():
        print(f"  검정 {fam[0]} 흰 {fam[1]}: 표 {ks}")
    if starts:
        print(f"마지막 표 끝 {a.base + prev_end:08x}")

if __name__ == "__main__":
    main()
