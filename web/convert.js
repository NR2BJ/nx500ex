// nx500ex LUT 변환기 핵심 계산. 브라우저와 node 에서 같이 쓴다 (서버 없음, 모든 계산은 이 파일 안).
// tools/lut/cube2bank.py 와 바이트 단위로 같은 결과를 내도록 연산 순서까지 맞췄다 (tools/lut/web_test.js 로 검사).
//
// 뱅크 형식 (docs/research/2026-10-25-lut-dump-analysis.md): 17x17x17 항목, 항목 4바이트 (Cr, Cb, Y, 0), Cr 이 가장 빠른 축.
// 격자 노드 i = 입력 i x 16 (0 ... 240, 256). 카메라 YCbCr 은 BT.601 전범위 (색표 검증 ΔE 1.25).
// 표 42개 (구간 A 20개, 구간 B 22개) 마다 카메라 원래 표 위에 룩을 얹는다.
(function (root) {
  'use strict';
  const N = 17, E = N * N * N, TB = E * 4, BANK = 0x4d00;
  const GRID_A = 20, GRID_B = 22;
  const SIZE_A = (GRID_A - 1) * BANK + TB;   // 394180
  const SIZE_B = (GRID_B - 1) * BANK + TB;   // 433604
  const KR = 0.299, KB = 0.114, KG = 1 - KR - KB;

  // numpy.rint 와 같은 "반은 짝수로" 반올림
  function rint(v) {
    const f = Math.floor(v), d = v - f;
    if (d > 0.5) return f + 1;
    if (d < 0.5) return f;
    return (f % 2 === 0) ? f : f + 1;
  }
  function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

  // ---- .cube 읽기 (1D, 3D, 1D + 3D) ----
  function parseCube(text) {
    let size1 = null, size3 = null, cur = null;
    const dom = { '1d': [[0, 0, 0], [1, 1, 1]], '3d': [[0, 0, 0], [1, 1, 1]] };
    const rows = [];
    const lines = text.split(/\r?\n/);
    for (let line of lines) {
      const s = line.trim();
      if (!s || s[0] === '#') continue;
      const t = s.split(/\s+/);
      const key = t[0].toUpperCase();
      if (key === 'LUT_3D_SIZE') { size3 = parseInt(t[1], 10); cur = '3d'; }
      else if (key === 'LUT_1D_SIZE') { size1 = parseInt(t[1], 10); cur = '1d'; }
      else if (key === 'DOMAIN_MIN' || key === 'DOMAIN_MAX') {
        const which = cur || ((size3 === null && size1 !== null) ? '1d' : '3d');
        dom[which][key === 'DOMAIN_MIN' ? 0 : 1] = [parseFloat(t[1]), parseFloat(t[2]), parseFloat(t[3])];
      }
      else if (key === 'TITLE' || key === 'LUT_1D_INPUT_RANGE' || key === 'LUT_3D_INPUT_RANGE') continue;
      else {
        const a = parseFloat(t[0]), b = parseFloat(t[1]), c = parseFloat(t[2]);
        if (Number.isFinite(a) && Number.isFinite(b) && Number.isFinite(c)) rows.push([a, b, c]);
      }
    }
    const n1 = size1 || 0, n3 = size3 ? size3 * size3 * size3 : 0;
    if (size1 === null && size3 === null) throw new Error('LUT_1D_SIZE 도 LUT_3D_SIZE 도 없음: .cube 파일이 아님');
    if (rows.length !== n1 + n3) throw new Error(`표 크기 불일치: 1D ${size1} 3D ${size3} 에 ${n1 + n3} 줄이 필요한데 ${rows.length} 줄`);
    if (size3 !== null && (size3 < 2 || size3 > 256)) throw new Error(`LUT_3D_SIZE ${size3} 는 지원 범위(2~256) 밖`);
    if (size1 !== null && (size1 < 2 || size1 > 65536)) throw new Error(`LUT_1D_SIZE ${size1} 는 지원 범위 밖`);
    const lut1d = size1 ? rows.slice(0, n1) : null;
    const cube = size3 ? rows.slice(n1) : null;   // 색인 = r + S*g + S*S*b (R 이 가장 빠름)
    return { lut1d, size1, dmin1: dom['1d'][0], dmax1: dom['1d'][1], cube, size3, dmin: dom['3d'][0], dmax: dom['3d'][1] };
  }

  // HaldCLUT: 픽셀 RGB 0..255 배열 (길이 n*3), n = level^3 -> cube 와 같은 구조
  function haldFromPixels(rgb, n) {
    const size = Math.round(Math.cbrt(n));
    if (size * size * size !== n) throw new Error(`HaldCLUT 크기가 아님: 픽셀 ${n} 개 (한 변 = 레벨^3 인 정사각형이어야 함)`);
    const cube = new Array(n);
    for (let i = 0; i < n; i++) cube[i] = [rgb[i * 3] / 255.0, rgb[i * 3 + 1] / 255.0, rgb[i * 3 + 2] / 255.0];
    return { lut1d: null, cube, size3: size, dmin: [0, 0, 0], dmax: [1, 1, 1] };
  }

  // 1D: 채널마다 선형 보간. x 0..1 (3개) -> 0..1
  function apply1d(lut, S, x) {
    const out = [0, 0, 0];
    for (let c = 0; c < 3; c++) {
      const p = clamp(x[c], 0, 1) * (S - 1);
      let i0 = Math.floor(p); if (i0 < 0) i0 = 0; if (i0 > S - 2) i0 = S - 2;
      const f = p - i0;
      out[c] = lut[i0][c] * (1 - f) + lut[i0 + 1][c] * f;
    }
    return out;
  }
  // 3D 삼선형. cube 색인 r + S*g + S*S*b. python trilinear_cube 와 같은 항 순서
  function trilinear(cube, S, x) {
    const pr = clamp(x[0], 0, 1) * (S - 1), pg = clamp(x[1], 0, 1) * (S - 1), pb = clamp(x[2], 0, 1) * (S - 1);
    let r0 = Math.floor(pr), g0 = Math.floor(pg), b0 = Math.floor(pb);
    if (r0 < 0) r0 = 0; if (r0 > S - 2) r0 = S - 2;
    if (g0 < 0) g0 = 0; if (g0 > S - 2) g0 = S - 2;
    if (b0 < 0) b0 = 0; if (b0 > S - 2) b0 = S - 2;
    const fr = pr - r0, fg = pg - g0, fb = pb - b0;
    const C = (dr, dg, db) => cube[(r0 + dr) + S * (g0 + dg) + S * S * (b0 + db)];
    const c000 = C(0, 0, 0), c100 = C(1, 0, 0), c010 = C(0, 1, 0), c110 = C(1, 1, 0);
    const c001 = C(0, 0, 1), c101 = C(1, 0, 1), c011 = C(0, 1, 1), c111 = C(1, 1, 1);
    const out = [0, 0, 0];
    for (let k = 0; k < 3; k++) {
      out[k] = c000[k] * (1 - fr) * (1 - fg) * (1 - fb) + c100[k] * fr * (1 - fg) * (1 - fb) + c010[k] * (1 - fr) * fg * (1 - fb) + c110[k] * fr * fg * (1 - fb)
             + c001[k] * (1 - fr) * (1 - fg) * fb + c101[k] * fr * (1 - fg) * fb + c011[k] * (1 - fr) * fg * fb + c111[k] * fr * fg * fb;
    }
    return out;
  }
  // ---- 입력 공간 (tools/lut/inspace.py 와 같은 상수와 식). 카메라는 완성 sRGB 를 LUT 에 넣으므로 로그/선형 입력용 LUT 는 먼저 그 공간으로 바꾼다 ----
  const MATRICES = {
    vgamut: [[0.585228754, 0.322656162, 0.092196105], [0.078525921, 0.819662708, 0.101781757], [0.022766089, 0.114221731, 0.862959434]],
    sgamut3: [[0.566077827, 0.342778099, 0.091220421], [0.076899864, 0.799089495, 0.123980535], [0.022323259, 0.108616808, 0.869007953]],
    sgamut3cine: [[0.645723475, 0.259125895, 0.095244182], [0.087472175, 0.759732834, 0.152766788], [0.036930429, 0.129286567, 0.833734666]],
    bt2020: [[0.627441372, 0.32929746, 0.043351458], [0.069027617, 0.919580667, 0.011361423], [0.016364235, 0.088017162, 0.895564973]],
    cinemagamut: [[0.556185756, 0.329189024, 0.114699106], [0.082354907, 0.75750296, 0.160112721], [0.033071262, 0.22582185, 0.741058963]],
    awg3: [[0.631362623, 0.270812626, 0.09791522], [0.03675345, 0.793071572, 0.170134952], [0.017338777, 0.148795214, 0.833812095]],
    awg4: [[0.565865404, 0.340345904, 0.093864957], [0.08856502, 0.809382288, 0.102025411], [0.017721742, 0.109452414, 0.872772816]],
  };
  const log10 = (v) => Math.log10(Math.max(v, 1e-12));
  const ENC = {
    vlog: (x) => x < 0.01 ? 5.6 * x + 0.125 : 0.241514 * log10(x + 0.00873) + 0.598206,
    slog3: (x) => x >= 0.01125 ? (420.0 + log10((x + 0.01) / (0.18 + 0.01)) * 261.5) / 1023.0 : (x * (171.2102946929 - 95.0) / 0.01125 + 95.0) / 1023.0,
    flog: (x) => x >= 0.00089 ? 0.344676 * log10(0.555556 * x + 0.009468) + 0.790453 : 8.735631 * x + 0.092864,
    flog2: (x) => x >= 0.000889 ? 0.245281 * log10(5.555556 * x + 0.064829) + 0.384316 : 8.799461 * x + 0.092864,
    nlog: (x) => { const xp = Math.max(x, 0); return xp < 0.328 ? (650.0 / 1023.0) * Math.cbrt(xp + 0.0075) : (150.0 / 1023.0) * Math.log(Math.max(xp, 1e-12)) + 619.0 / 1023.0; },
    clog3: (x) => { const v = x / 0.9; return v < -0.014 ? -(0.36726845 * log10(1 - 14.98325 * v) + 0.12783901) : (v <= 0.014 ? 1.9754798 * v + 0.12512219 : 0.36726845 * log10(14.98325 * v + 1) + 0.12240537); },
    logc3: (x) => x > 0.010591 ? 0.247190 * log10(5.555556 * x + 0.052272) + 0.385537 : 5.367655 * x + 0.092809,
    logc4: (x) => { const a = (Math.pow(2, 18) - 16.0) / 117.45, b = (1023.0 - 95.0) / 1023.0, c = 95.0 / 1023.0; const s = 7.0 * Math.log(2.0) * Math.pow(2.0, 7.0 - 14.0 * c / b) / (a * b); const t = (Math.pow(2.0, 14.0 * (-c / b) + 6.0) - 64.0) / a; return x >= t ? (Math.log2(Math.max(a * x + 64.0, 1e-12)) - 6.0) / 14.0 * b + c : (x - t) / s; },
    pq: (x) => { const y = Math.max(x, 0) * 100.0 / 10000.0; const m1 = 2610.0 / 16384.0, m2 = 2523.0 / 4096.0 * 128.0, c1 = 3424.0 / 4096.0, c2 = 2413.0 / 4096.0 * 32.0, c3 = 2392.0 / 4096.0 * 32.0; const ym = Math.pow(y, m1); return Math.pow((c1 + c2 * ym) / (1.0 + c3 * ym), m2); },
    hlg: (x) => { const e = Math.max(x, 0) * 0.1; return e <= 1.0 / 12.0 ? Math.sqrt(3.0 * e) : 0.17883277 * Math.log(Math.max(12.0 * e - 0.28466892, 1e-12)) + 0.55991073; },
  };
  // id: [이름, 색 영역, 곡선]
  const SPACES = {
    srgb: ['sRGB / Rec.709 완성 영상 (기본)', null, null],
    linear: ['선형 sRGB (linear)', null, 'linear'],
    vlog: ['Panasonic V-Log / V-Gamut', 'vgamut', 'vlog'],
    slog3cine: ['Sony S-Log3 / S-Gamut3.Cine', 'sgamut3cine', 'slog3'],
    slog3: ['Sony S-Log3 / S-Gamut3', 'sgamut3', 'slog3'],
    flog: ['Fujifilm F-Log / F-Gamut', 'bt2020', 'flog'],
    flog2: ['Fujifilm F-Log2 / F-Gamut', 'bt2020', 'flog2'],
    nlog: ['Nikon N-Log / BT.2020', 'bt2020', 'nlog'],
    clog3: ['Canon Log 3 / Cinema Gamut', 'cinemagamut', 'clog3'],
    logc3: ['ARRI LogC3 EI800 / Wide Gamut 3', 'awg3', 'logc3'],
    logc4: ['ARRI LogC4 / Wide Gamut 4', 'awg4', 'logc4'],
    hlg: ['HLG / BT.2020 (참고용)', 'bt2020', 'hlg'],
    pq: ['PQ ST 2084 / BT.2020 (참고용, 흰색 100 nit)', 'bt2020', 'pq'],
  };
  const srgbToLinear = (v) => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  function toSpace(x, space, ev) {
    if (!space || space === 'srgb') return x;
    const def = SPACES[space]; if (!def) throw new Error('모르는 입력 공간 ' + space);
    const gain = Math.pow(2.0, ev || 0);
    let lin = [srgbToLinear(clamp(x[0], 0, 1)) * gain, srgbToLinear(clamp(x[1], 0, 1)) * gain, srgbToLinear(clamp(x[2], 0, 1)) * gain];
    if (def[1]) { const m = MATRICES[def[1]]; lin = [m[0][0] * lin[0] + m[0][1] * lin[1] + m[0][2] * lin[2], m[1][0] * lin[0] + m[1][1] * lin[1] + m[1][2] * lin[2], m[2][0] * lin[0] + m[2][1] * lin[1] + m[2][2] * lin[2]]; }
    if (def[2] === 'linear') return lin;
    const f = ENC[def[2]];
    return [f(lin[0]), f(lin[1]), f(lin[2])];
  }
  function guessSpace(filename, cubeText) {
    if (cubeText) { const m = cubeText.match(/^\s*#\s*LUMIXPHOTOSTYLE\s+(\S+)/mi); if (m) return m[1].toUpperCase().includes('LOG') ? 'vlog' : 'srgb'; }
    const n = (filename || '').toLowerCase();
    const pats = [[/s-?log3|slog3/, 'slog3cine'], [/s-?log2|slog2/, 'slog3cine'], [/v-?log/, 'vlog'], [/f-?log2/, 'flog2'], [/f-?log/, 'flog'], [/n-?log/, 'nlog'], [/c-?log3|clog3|canon.?log/, 'clog3'], [/logc4|log-?c4/, 'logc4'], [/logc|log-?c|alexa|arri/, 'logc3'], [/hlg/, 'hlg'], [/\bpq\b|st2084|2084/, 'pq'], [/linear|_lin[_.]|acescg/, 'linear']];
    for (const [re, sp] of pats) if (re.test(n)) return sp;
    return 'srgb';
  }

  // LUT 내용으로 입력 공간 판별 (inspace.py detect_space 와 같음): 회색 램프와 색 패치를 각 후보 공간으로 넣어 결과가 입력과 가장 비슷한 공간
  const DETECT_SPACES = ['srgb', 'vlog', 'slog3cine', 'flog', 'flog2', 'nlog', 'clog3', 'logc3', 'logc4', 'linear'];
  const DETECT_PATCHES = [[224, 172, 140], [135, 180, 230], [90, 130, 70], [200, 60, 50], [240, 200, 60], [60, 80, 160], [180, 90, 160], [60, 170, 170]].map(p => p.map(v => v / 255.0));
  const DETECT_GRAY = Array.from({ length: 12 }, (_, i) => 0.08 + (1.0 - 0.08) * i / 11);
  function detectSpace(lut) {
    const out = [];
    for (const sp of DETECT_SPACES) {
      const f = makeLookFunc(lut, sp, 0);
      let se = 0, flip = false, prevY = -1;
      for (const x of DETECT_GRAY) {
        const y = f([x, x, x]).map(v => clamp(v, 0, 1));
        const Y = 0.2126 * y[0] + 0.7152 * y[1] + 0.0722 * y[2];
        se += (Y - x) * (Y - x);
        if (prevY >= 0 && Y - prevY < -0.02) flip = true;
        prevY = Y;
      }
      let err = Math.sqrt(se / DETECT_GRAY.length) + (flip ? 0.5 : 0);
      let ce = 0;
      for (const p of DETECT_PATCHES) { const y = f(p).map(v => clamp(v, 0, 1)); for (let c = 0; c < 3; c++) ce += (y[c] - p[c]) * (y[c] - p[c]); }
      err += 0.5 * Math.sqrt(ce / (DETECT_PATCHES.length * 3));
      out.push([sp, err]);
    }
    out.sort((a, b) => a[1] - b[1]);
    return out;
  }
  function detectSummary(ranked) {
    const [best, e1] = ranked[0]; const [second, e2] = ranked[1] || [null, e1 + 1];
    const margin = e2 - e1;
    const srgbErr = (ranked.find(r => r[0] === 'srgb') || [null, 1])[1];
    if (best === 'srgb') return { best, conf: margin > 0.03 ? '높음' : '낮음', why: `회색 램프 오차 ${e1.toFixed(3)}, 다음 후보 ${second} ${e2.toFixed(3)}` };
    const sureLog = srgbErr - e1 > 0.05;
    return { best, conf: (sureLog && margin > 0.02) ? '높음' : '낮음', why: `오차 ${e1.toFixed(3)} (sRGB 로 넣으면 ${srgbErr.toFixed(3)}), 다음 후보 ${second} ${e2.toFixed(3)}` };
  }

  // 흰색 자동 맞춤: 로그 입력용 LUT 는 흰색 1.0 이 로그의 90% 흰색 자리로 가서 결과가 가라앉는다. 결과 흰색의 밝기가 목표 (0.97) 에 닿는
  // 가장 작은 노출 보정을 0 ~ 3 스톱에서 찾는다 (inspace.py auto_ev 와 같음)
  // 흰색 자동 맞춤 (inspace.auto_ev 와 같음): 흰색을 255 로 밀어붙이면 하이라이트를 일부러 눌러 둔 룩이 부서지므로,
  // LUT 자체의 회색 응답에서 무릎 (출력이 자기 최대의 90% 에 처음 닿는 입력 코드) 을 찾아 우리 흰색 (선형 1.0) 이 거기로 가는 노출을 고른다
  function decodeSpace(space, code) {
    const def = SPACES[space];
    if (!def[2]) return srgbToLinear(code);
    if (def[2] === 'linear') return code;
    const f = ENC[def[2]];
    let lo = 0, hi = 64;
    for (let i = 0; i < 60; i++) { const mid = (lo + hi) / 2; if (f(mid) < code) lo = mid; else hi = mid; }
    return (lo + hi) / 2;
  }
  function autoEv(lut, space, knee) {
    knee = knee || 0.9;
    const raw = makeLookFunc(lut, 'srgb', 0);
    const ys = [];
    for (let i = 0; i <= 100; i++) { const x = i / 100; const y = raw([x, x, x]).map(v => clamp(v, 0, 1)); ys.push(0.2126 * y[0] + 0.7152 * y[1] + 0.0722 * y[2]); }
    const top = Math.max(...ys);
    let idx = ys.findIndex(v => v >= knee * top); if (idx < 0) idx = 100;
    const xk = idx / 100;
    if (top >= 0.95) return { ev: 0, xk, top };   // 흰색에 닿는 LUT (순수 변환 등) 는 표준 노출이 맞다
    const lin = decodeSpace(space, xk);
    if (lin <= 0) return { ev: 0, xk, top };
    let ev = Math.log2(lin / 1.0); ev = Math.min(2, Math.max(-1, ev)); ev = Math.round(ev * 8) / 8;
    return { ev, xk, top };
  }

  // ---- 다른 표 형식 ----
  function numLines(text) {
    const out = [];
    for (const line of text.split(/\r?\n/)) { const t = line.trim(); if (!t || t[0] === '#') continue; out.push(t.split(/\s+/)); }
    return out;
  }
  function scaleOf(maxv) { for (const m of [255, 1023, 4095, 16383, 65535]) if (maxv <= m) return m; return maxv; }
  function parse3dl(text) {
    const rows = numLines(text); const entries = []; let bits = null;
    for (const t of rows) {
      if (t[0].toLowerCase() === 'mesh' && t.length >= 3) { bits = parseInt(t[2], 10); continue; }
      const v = t.map(parseFloat); if (v.some(a => !Number.isFinite(a))) continue;
      if (v.length === 3) entries.push(v);
    }
    const n = entries.length, S = Math.round(Math.cbrt(n));
    if (S * S * S !== n) throw new Error(`.3dl 항목 수 ${n} 이 정육면체가 아님`);
    let maxv = 0; for (const e of entries) for (const a of e) if (a > maxv) maxv = a;
    const scale = bits ? Math.pow(2, bits) - 1 : scaleOf(maxv);
    const cube = new Array(n);
    // 빨강이 가장 느림: 항목 (r*S + g)*S + b -> 우리 색인 r + S*g + S*S*b
    for (let r = 0; r < S; r++) for (let g = 0; g < S; g++) for (let b = 0; b < S; b++) { const e = entries[(r * S + g) * S + b]; cube[r + S * g + S * S * b] = [e[0] / scale, e[1] / scale, e[2] / scale]; }
    return { lut1d: null, cube, size3: S, dmin: [0, 0, 0], dmax: [1, 1, 1], prelut: null };
  }
  function parseVlt(text) {
    const rows = numLines(text); const entries = [];
    for (const t of rows) { if (t[0].toUpperCase() === 'LUT_3D_SIZE') continue; if (t.length < 3) continue; const v = [parseFloat(t[0]), parseFloat(t[1]), parseFloat(t[2])]; if (v.every(Number.isFinite)) entries.push(v); }
    const n = entries.length, S = Math.round(Math.cbrt(n));
    if (S * S * S !== n) throw new Error(`.vlt 항목 수 ${n} 이 정육면체가 아님`);
    let maxv = 0; for (const e of entries) for (const a of e) if (a > maxv) maxv = a;
    const scale = maxv > 1.0 ? scaleOf(maxv) : 1.0;
    return { lut1d: null, cube: entries.map(e => [e[0] / scale, e[1] / scale, e[2] / scale]), size3: S, dmin: [0, 0, 0], dmax: [1, 1, 1], prelut: null };
  }
  function parseCsp(text) {
    const rows = numLines(text); let i = 0;
    if (rows.length && rows[0][0].toUpperCase().startsWith('CSPLUT')) i = 1;
    if (i < rows.length && rows[i][0].toUpperCase() === '3D') i++;
    else if (i < rows.length && rows[i][0].toUpperCase() === '1D') throw new Error('.csp 1D 는 지원하지 않음');
    if (i < rows.length && rows[i][0].toUpperCase() === 'BEGIN') { while (i < rows.length && rows[i][0].toUpperCase() !== 'END') i++; i++; }
    const prelut = [];
    for (let c = 0; c < 3; c++) { const n = parseInt(rows[i][0], 10); i++; const xs = rows[i].slice(0, n).map(parseFloat); i++; const ys = rows[i].slice(0, n).map(parseFloat); i++; prelut.push([xs, ys]); }
    const sx = parseInt(rows[i][0], 10), sy = parseInt(rows[i][1], 10), sz = parseInt(rows[i][2], 10); i++;
    const cube = [];
    for (let k = 0; k < sx * sy * sz && i + k < rows.length; k++) cube.push([parseFloat(rows[i + k][0]), parseFloat(rows[i + k][1]), parseFloat(rows[i + k][2])]);
    if (cube.length !== sx * sy * sz || sx !== sy || sy !== sz) throw new Error(`.csp 격자 ${sx} ${sy} ${sz} 와 항목 수 ${cube.length} 불일치`);
    return { lut1d: null, cube, size3: sx, dmin: [0, 0, 0], dmax: [1, 1, 1], prelut };
  }
  function interp(xs, ys, v) {   // numpy.interp 와 같음 (범위 밖은 끝값)
    const n = xs.length;
    if (v <= xs[0]) return ys[0];
    if (v >= xs[n - 1]) return ys[n - 1];
    let lo = 0, hi = n - 1;
    while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (xs[mid] <= v) lo = mid; else hi = mid; }
    const t = (v - xs[lo]) / (xs[hi] - xs[lo]);
    return ys[lo] + t * (ys[hi] - ys[lo]);
  }
  function parseLut(name, text) {
    const ext = (name || '').toLowerCase().split('.').pop();
    if (ext === '3dl') return parse3dl(text);
    if (ext === 'vlt') return parseVlt(text);
    if (ext === 'csp') return parseCsp(text);
    const c = parseCube(text); c.prelut = null; return c;
  }

  // 룩 함수 만들기 (sRGB 0..1 -> RGB 0..1). space 는 SPACES 의 id, ev 는 노출 보정 (스톱)
  function makeLookFunc(lut, space, ev) {
    return function (x0) {
      let v = toSpace(x0, space, ev);
      if (lut.prelut) v = [interp(lut.prelut[0][0], lut.prelut[0][1], v[0]), interp(lut.prelut[1][0], lut.prelut[1][1], v[1]), interp(lut.prelut[2][0], lut.prelut[2][1], v[2])];
      if (lut.lut1d) {
        const dmin = lut.dmin1, dmax = lut.dmax1;
        v = apply1d(lut.lut1d, lut.size1, [(v[0] - dmin[0]) / (dmax[0] - dmin[0]), (v[1] - dmin[1]) / (dmax[1] - dmin[1]), (v[2] - dmin[2]) / (dmax[2] - dmin[2])]);
      }
      if (lut.cube) {
        const dmin = lut.dmin, dmax = lut.dmax;
        v = trilinear(lut.cube, lut.size3, [(v[0] - dmin[0]) / (dmax[0] - dmin[0]), (v[1] - dmin[1]) / (dmax[1] - dmin[1]), (v[2] - dmin[2]) / (dmax[2] - dmin[2])]);
      }
      return v;
    };
  }

  // ---- 색 공간 (BT.601 전범위). python 과 같은 연산 순서 ----
  function yccToRgb(cr, cb, y) {
    const yy = (y - 0) / 1.0;
    const crr = (cr - 128.0) / 1.0 * 2 * (1 - KR);
    const cbb = (cb - 128.0) / 1.0 * 2 * (1 - KB);
    const r = yy + crr, b = yy + cbb;
    const g = (yy - KR * r - KB * b) / KG;
    return [r, g, b];
  }
  function rgbToYcc(r, g, b) {
    const y = KR * r + KG * g + KB * b;
    const cr = (r - y) / (2 * (1 - KR)) * 1.0 + 128.0;
    const cb = (b - y) / (2 * (1 - KB)) * 1.0 + 128.0;
    return [cr, cb, y * 1.0 + 0];
  }

  // 범위 밖 격자점: 안쪽으로 자른 점의 룩 값 + 룩의 기울기 x 잘린 차이 (python apply_func_extrap 와 같음)
  function applyExtrap(func, rgb) {
    const rgbC = [clamp(rgb[0], 0, 255), clamp(rgb[1], 0, 255), clamp(rgb[2], 0, 255)];
    const resid = [(rgb[0] - rgbC[0]) / 255.0, (rgb[1] - rgbC[1]) / 255.0, (rgb[2] - rgbC[2]) / 255.0];
    const x = [rgbC[0] / 255.0, rgbC[1] / 255.0, rgbC[2] / 255.0];
    const f0 = func(x);
    const out = [f0[0], f0[1], f0[2]];
    const h = 0.02;
    for (let k = 0; k < 3; k++) {
      if (resid[k] === 0) continue;
      const step = x[k] <= 1 - h ? h : -h;
      const xk = [x[0], x[1], x[2]]; xk[k] = x[k] + step;
      const fk = func(xk);
      for (let c = 0; c < 3; c++) out[c] = out[c] + ((fk[c] - f0[c]) / step) * resid[k];
    }
    return [out[0] * 255.0, out[1] * 255.0, out[2] * 255.0];
  }

  // 표 하나: stock 은 Uint8Array(19652) (원래 표) 또는 null. 반환 Uint8Array(19652)
  function makeBank(func, stock) {
    const out = new Uint8Array(TB);
    let i = 0;
    for (let iy = 0; iy < N; iy++) for (let ib = 0; ib < N; ib++) for (let ic = 0; ic < N; ic++) {
      let cr, cb, y;
      if (stock) { cr = stock[i * 4]; cb = stock[i * 4 + 1]; y = stock[i * 4 + 2]; }
      else { cr = ic * 16.0; cb = ib * 16.0; y = iy * 16.0; }
      const rgb = yccToRgb(cr, cb, y);
      const o = applyExtrap(func, rgb);
      const ycc = rgbToYcc(o[0], o[1], o[2]);
      out[i * 4] = clamp(rint(ycc[0]), 0, 255);
      out[i * 4 + 1] = clamp(rint(ycc[1]), 0, 255);
      out[i * 4 + 2] = clamp(rint(ycc[2]), 0, 255);
      out[i * 4 + 3] = 0;
      i++;
    }
    return out;
  }

  // 구간 A, B 전체. stockAB: Uint8Array(SIZE_A + SIZE_B) = 카메라 원래 표 (web/stock.bin). 반환 { a, b }
  function makeRegions(func, stockAB, onProgress) {
    if (stockAB.length !== SIZE_A + SIZE_B) throw new Error('stock.bin 크기가 다름');
    const regions = [];
    let base = 0, done = 0;
    for (const [count, size] of [[GRID_A, SIZE_A], [GRID_B, SIZE_B]]) {
      const out = new Uint8Array(size);
      for (let k = 0; k < count; k++) {
        const off = k * BANK;
        const st = stockAB.subarray(base + off, base + off + TB);
        out.set(makeBank(func, st), off);
        if (k + 1 < count) out.set(stockAB.subarray(base + off + TB, base + off + BANK), off + TB);
        done++;
        if (onProgress) onProgress(done, GRID_A + GRID_B);
      }
      regions.push(out);
      base += size;
    }
    return { a: regions[0], b: regions[1] };
  }

  // 미리보기: 뱅크 하나 (Uint8Array 19652, (Cr,Cb,Y,0)) 를 RGB 픽셀에 적용 (카메라와 같은 BT.601 전범위, 노드 i x 16 보간)
  function applyBankToPixels(bank, pix) {
    const g = (iy, ib, ic, c) => bank[((iy * N + ib) * N + ic) * 4 + c];
    const n = pix.length / 4;
    const out = new Uint8ClampedArray(pix.length);
    for (let p = 0; p < n; p++) {
      const r = pix[p * 4], gg = pix[p * 4 + 1], b = pix[p * 4 + 2];
      const ycc = rgbToYcc(r, gg, b);
      const idx = (v) => { const q = clamp(v, 0, 255) / 16.0; let i0 = Math.floor(q); if (i0 > N - 2) i0 = N - 2; return [i0, q - i0]; };
      const [ic, fc] = idx(ycc[0]), [ib, fb] = idx(ycc[1]), [iy, fy] = idx(ycc[2]);
      const o = [0, 0, 0];
      for (let c = 0; c < 3; c++) {
        o[c] = g(iy, ib, ic, c) * (1 - fy) * (1 - fb) * (1 - fc) + g(iy, ib, ic + 1, c) * (1 - fy) * (1 - fb) * fc + g(iy, ib + 1, ic, c) * (1 - fy) * fb * (1 - fc) + g(iy, ib + 1, ic + 1, c) * (1 - fy) * fb * fc
             + g(iy + 1, ib, ic, c) * fy * (1 - fb) * (1 - fc) + g(iy + 1, ib, ic + 1, c) * fy * (1 - fb) * fc + g(iy + 1, ib + 1, ic, c) * fy * fb * (1 - fc) + g(iy + 1, ib + 1, ic + 1, c) * fy * fb * fc;
      }
      const rgb = yccToRgb(o[0], o[1], o[2]);
      out[p * 4] = rgb[0] + 0.5; out[p * 4 + 1] = rgb[1] + 0.5; out[p * 4 + 2] = rgb[2] + 0.5; out[p * 4 + 3] = 255;
    }
    return out;
  }

  // ---- 저장만 하는 zip (압축 없음). 파일 이름은 UTF-8 ----
  const CRC_TABLE = (() => { const t = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1); t[n] = c >>> 0; } return t; })();
  function crc32(buf) { let c = 0xFFFFFFFF; for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xFF] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; }
  function makeZip(files) {   // files: [{ name, data: Uint8Array }]
    const enc = new TextEncoder();
    const parts = [], central = [];
    let offset = 0;
    const le16 = (v) => [v & 255, (v >>> 8) & 255];
    const le32 = (v) => [v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255];
    for (const f of files) {
      const name = enc.encode(f.name), data = f.data, crc = crc32(data);
      const local = new Uint8Array([0x50, 0x4b, 0x03, 0x04, ...le16(20), ...le16(0x0800), ...le16(0), ...le16(0), ...le16(0x21), ...le32(crc), ...le32(data.length), ...le32(data.length), ...le16(name.length), ...le16(0), ...name]);
      parts.push(local, data);
      central.push(new Uint8Array([0x50, 0x4b, 0x01, 0x02, ...le16(20), ...le16(20), ...le16(0x0800), ...le16(0), ...le16(0), ...le16(0x21), ...le32(crc), ...le32(data.length), ...le32(data.length), ...le16(name.length), ...le16(0), ...le16(0), ...le16(0), ...le16(0), ...le32(0), ...le32(offset), ...name]));
      offset += local.length + data.length;
    }
    const cdSize = central.reduce((s, c) => s + c.length, 0);
    const end = new Uint8Array([0x50, 0x4b, 0x05, 0x06, ...le16(0), ...le16(0), ...le16(files.length), ...le16(files.length), ...le32(cdSize), ...le32(offset), ...le16(0)]);
    const total = offset + cdSize + end.length;
    const out = new Uint8Array(total); let p = 0;
    for (const c of [...parts, ...central, end]) { out.set(c, p); p += c.length; }
    return out;
  }

  const api = { N, E, TB, BANK, SIZE_A, SIZE_B, parseCube, parseLut, parse3dl, parseVlt, parseCsp, haldFromPixels, makeLookFunc, makeBank, makeRegions, applyBankToPixels, makeZip, rint, yccToRgb, rgbToYcc, SPACES, toSpace, guessSpace, detectSpace, detectSummary, autoEv };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.NXLUT = api;
})(typeof self !== 'undefined' ? self : this);
