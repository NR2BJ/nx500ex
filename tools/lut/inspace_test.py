#!/usr/bin/env python3
"""inspace.py 의 로그 곡선과 행렬을 colour-science 와 비교한다. 사용: pixi run -e toy python tools/lut/inspace_test.py"""
import os, sys, warnings
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
warnings.filterwarnings("ignore")
import colour
from colour import RGB_COLOURSPACES as CS, matrix_RGB_to_RGB
import inspace as I

x = np.array([0.0, 0.001, 0.01, 0.05, 0.18, 0.5, 0.9, 1.0])
pairs = [("vlog", I.enc_vlog, colour.models.log_encoding_VLog), ("slog3", I.enc_slog3, colour.models.log_encoding_SLog3),
         ("flog", I.enc_flog, colour.models.log_encoding_FLog), ("flog2", I.enc_flog2, colour.models.log_encoding_FLog2),
         ("nlog", I.enc_nlog, colour.models.log_encoding_NLog), ("clog3", I.enc_clog3, colour.models.log_encoding_CanonLog3),
         ("logc3", I.enc_logc3, colour.models.log_encoding_ARRILogC3), ("logc4", I.enc_logc4, colour.models.log_encoding_ARRILogC4)]
bad = 0
for name, mine, ref in pairs:
    d = np.abs(mine(x) - ref(x)).max()
    print(f"{name:7s} 최대 차 {d:.2e} {'OK' if d < 2e-6 else 'FAIL'}")
    bad |= d >= 2e-6
m_pq = np.abs(I.enc_pq(np.array([1.0])) - colour.models.eotf_inverse_ST2084(np.array([100.0]))).max()
print(f"pq      흰색 100nit 차 {m_pq:.2e} {'OK' if m_pq < 2e-6 else 'FAIL'}"); bad |= m_pq >= 2e-6
m_hlg = np.abs(I.enc_hlg(np.array([0.5, 1.0])) - colour.models.oetf_BT2100_HLG(np.array([0.05, 0.1]))).max()
print(f"hlg     차 {m_hlg:.2e} {'OK' if m_hlg < 2e-6 else 'FAIL'}"); bad |= m_hlg >= 2e-6
for key, csname in [("vgamut", "V-Gamut"), ("sgamut3", "S-Gamut3"), ("sgamut3cine", "S-Gamut3.Cine"), ("bt2020", "ITU-R BT.2020"),
                    ("cinemagamut", "Cinema Gamut"), ("awg3", "ARRI Wide Gamut 3"), ("awg4", "ARRI Wide Gamut 4")]:
    ref = matrix_RGB_to_RGB(CS["sRGB"], CS[csname], chromatic_adaptation_transform="CAT02")
    d = np.abs(np.array(I.MATRICES[key]) - ref).max()
    print(f"행렬 {key:12s} 최대 차 {d:.2e} {'OK' if d < 1e-8 else 'FAIL'}"); bad |= d >= 1e-8
print("전체:", "FAIL" if bad else "OK")
sys.exit(1 if bad else 0)
