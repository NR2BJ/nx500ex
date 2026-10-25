#!/usr/bin/env node
// 웹 변환기 (web/convert.js) 가 파이썬 변환기 (tools/lut/cube2bank.py) 와 바이트 단위로 같은지 검사한다.
// 사용: node tools/lut/web_test.js <lut 파일 (.cube .3dl .vlt .csp)> <파이썬이 만든 _a.bin> <파이썬이 만든 _b.bin> [입력 공간] [ev]
//   web/stock.bin (카메라 원래 표 구간 A + B) 을 읽어 같은 표로 구간을 만들고 비교한다.
const fs = require('fs'), path = require('path');
const X = require(path.join(__dirname, '..', '..', 'web', 'convert.js'));
const [lutPath, refA, refB, space, evs] = process.argv.slice(2);
if (!lutPath || !refA || !refB) { console.error('사용: web_test.js <lut> <ref_a.bin> <ref_b.bin> [space] [ev]'); process.exit(2); }
const stock = new Uint8Array(fs.readFileSync(path.join(__dirname, '..', '..', 'web', 'stock.bin')));
const lut = X.parseLut(lutPath, fs.readFileSync(lutPath, 'utf8'));
const t0 = Date.now();
const { a, b } = X.makeRegions(X.makeLookFunc(lut, space || 'srgb', parseFloat(evs || '0')), stock);
const ms = Date.now() - t0;
function diff(name, got, ref) {
  if (got.length !== ref.length) { console.log(`${name}: 크기 다름 ${got.length} vs ${ref.length}`); return 1; }
  let n = 0, maxd = 0;
  for (let i = 0; i < got.length; i++) { const d = Math.abs(got[i] - ref[i]); if (d) { n++; if (d > maxd) maxd = d; } }
  console.log(`${name}: ${n === 0 ? '바이트 일치' : `다른 바이트 ${n} 개 (${(100 * n / got.length).toFixed(4)}%), 최대 차 ${maxd}`}`);
  return n ? 1 : 0;
}
const rc = diff('구간 A', a, new Uint8Array(fs.readFileSync(refA))) | diff('구간 B', b, new Uint8Array(fs.readFileSync(refB)));
console.log(`변환 ${ms} ms`);
process.exit(rc);
