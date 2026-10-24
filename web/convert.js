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
  // 룩 함수 만들기 (RGB 0..1 -> RGB 0..1)
  function makeLookFunc(lut) {
    return function (x) {
      let v = x;
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

  const api = { N, E, TB, BANK, SIZE_A, SIZE_B, parseCube, haldFromPixels, makeLookFunc, makeBank, makeRegions, applyBankToPixels, makeZip, rint, yccToRgb, rgbToYcc };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.NXLUT = api;
})(typeof self !== 'undefined' ? self : this);
