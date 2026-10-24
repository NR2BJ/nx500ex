#!/usr/bin/env python3
"""LUT 검증: lutcal.sh 로 찍은 색표 사진으로 카메라의 YCbCr 변환 모델을 확정한다.

사용: python3 lut_verify.py <사진 폴더> <jobs.log> [--out 폴더]
  jobs.log 의 "lutcal <id> -> <파일>" 줄로 사진을 잇는다. cal_id (항등) 사진의 24칸 색을 입력으로,
  각 검증 룩의 뱅크 (sd/nx500ex/lut/cal_<id>.bin, 순정 합성 없음) 를 후보 모델마다 적용해 예측하고
  실제 사진의 24칸과 Lab 거리(ΔE76)로 비교한다. 가장 작은 모델이 카메라의 변환이다.
후보 모델: 601full, 601lim, 709full, 709lim (cube2bank.MODELS). 격자는 노드 i = i x 16 트라이리니어.
"""
import os, sys, re, argparse
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(ROOT, "tools", "film"))
import cube2bank as C
from calib_analyze import patches, srgb_to_lab, NAMES

LUTDIR = os.path.join(ROOT, "sd", "nx500ex", "lut")

def interp_bank(g, cr, cb, y):
    """g: [Y, Cb, Cr, 3] 노드 i = i*16. 입력 0..255 -> 출력 (Cr, Cb, Y)"""
    def idx(v):
        p = np.clip(v, 0, 255) / 16.0
        i0 = np.clip(np.floor(p).astype(int), 0, C.N - 2)
        return i0, p - i0
    ic, fc = idx(cr); ib, fb = idx(cb); iy, fy = idx(y)
    fc, fb, fy = fc[..., None], fb[..., None], fy[..., None]
    def G(dy, db, dc):
        return g[iy + dy, ib + db, ic + dc]
    return (G(0,0,0)*(1-fy)*(1-fb)*(1-fc) + G(0,0,1)*(1-fy)*(1-fb)*fc + G(0,1,0)*(1-fy)*fb*(1-fc) + G(0,1,1)*(1-fy)*fb*fc
          + G(1,0,0)*fy*(1-fb)*(1-fc) + G(1,0,1)*fy*(1-fb)*fc + G(1,1,0)*fy*fb*(1-fc) + G(1,1,1)*fy*fb*fc)

def predict(bank, rgb, model):
    cr, cb, y = C.rgb_to_ycc(rgb, model)
    o = interp_bank(bank, cr, cb, y)
    return np.clip(C.ycc_to_rgb(o[..., 0], o[..., 1], o[..., 2], model), 0, 255)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder"); ap.add_argument("log"); ap.add_argument("--out")
    a = ap.parse_args()
    shots = []
    for line in open(a.log, encoding="utf-8"):
        m = re.search(r"lutcal (\S+) -> (\S+)", line)
        if m:
            shots.append((m.group(1), m.group(2)))
    if not shots or shots[0][0] != "cal_id":
        raise SystemExit("jobs.log 에 lutcal 줄이 없거나 첫 장이 cal_id 가 아님")
    out = a.out or a.folder
    meas = {}
    for rid, f in shots:
        p = os.path.join(a.folder, f)
        if not os.path.exists(p):
            print(f"{rid}: 사진 없음 {f}"); continue
        meas[rid] = patches(p, os.path.join(out, "dbg_" + rid + ".png") if rid == "cal_id" else None)
    base = meas["cal_id"]
    print("기준 (cal_id) 칸: 가장 밝은 칸 RGB", base.max(axis=0).round(0), "(Y 200 넘으면 순정 밝은 곳 억제가 끼어 비교가 흐려짐)")
    models = list(C.MODELS)
    table = {}
    for rid, _ in shots[1:]:
        if rid not in meas:
            continue
        bank = C.load_bank(os.path.join(LUTDIR, rid + ".bin"))
        actual = srgb_to_lab(meas[rid])
        row = {}
        for m in models:
            pred = srgb_to_lab(predict(bank, base, m))
            de = np.linalg.norm(pred - actual, axis=1)
            row[m] = (de.mean(), de.max(), int(de.argmax()))
        table[rid] = row
    print("\n룩마다 모델별 ΔE76 평균 (최대, 최대인 칸)")
    print("%-10s" % "룩" + "".join("%-26s" % m for m in models))
    for rid, row in table.items():
        print("%-10s" % rid + "".join("%5.2f (%5.1f %s)      " % (row[m][0], row[m][1], NAMES[row[m][2]][:4]) for m in models))
    avg = {m: np.mean([row[m][0] for row in table.values()]) for m in models}
    best = min(avg, key=avg.get)
    print("\n모델별 전체 평균 ΔE:", "  ".join(f"{m} {v:.2f}" for m, v in avg.items()))
    print(f"가장 맞는 모델: {best}")
    # 같은 사진을 두 번 찍었을 때의 잡음 수준 참고: 항등 룩 예측(= 기준 그대로) 과 기준의 차는 0 이므로 생략
    print(f"\n{best} 에서 칸별 오차 (룩: 실제 vs 예측 RGB)")
    for rid, _ in shots[1:]:
        if rid not in meas:
            continue
        bank = C.load_bank(os.path.join(LUTDIR, rid + ".bin"))
        pred = predict(bank, base, best)
        de = np.linalg.norm(srgb_to_lab(pred) - srgb_to_lab(meas[rid]), axis=1)
        worst = np.argsort(de)[::-1][:3]
        print("  %-10s 평균 %.2f  최악 3칸: %s" % (rid, de.mean(), ", ".join(
            "%s 실제 %s 예측 %s (ΔE %.1f)" % (NAMES[i], meas[rid][i].round(0).astype(int), pred[i].round(0).astype(int), de[i]) for i in worst)))

if __name__ == "__main__":
    main()
