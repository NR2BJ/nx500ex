// nx500ex 웹 원격. 서버 API 는 bin/nxweb (tools/nxweb/nxweb.c) 참고.
const $ = s => document.querySelector(s);
const W = 720, H = 480;

// 탭
document.querySelectorAll('nav button').forEach(b => b.onclick = () => {
  document.querySelectorAll('nav button').forEach(x => x.classList.toggle('on', x === b));
  document.querySelectorAll('.tab').forEach(t => t.classList.toggle('on', t.id === b.dataset.tab));
  if (b.dataset.tab === 'gallery' && !$('#grid').children.length) loadGallery();
  if (b.dataset.tab === 'actions' && !$('#alist').children.length) loadActions();
});

// 라이브 뷰: NV12 -> RGBA. 풀 레인지 (0~255) 와 비디오 레인지 (16~235) 둘 다 지원
const cv = $('#lv'), ctx = cv.getContext('2d');
const img = ctx.createImageData(W, H);
let frames = 0, lastFps = Date.now(), fps = 0, busy = false;
function nv12ToRgba(buf, low, full) {
  const yw = low ? W / 2 : W, yh = low ? H / 2 : H;
  const Y = new Uint8Array(buf, 0, yw * yh), UV = new Uint8Array(buf, yw * yh);
  const d = img.data;
  const ys = full ? 1.0 : 1.164, yo = full ? 0 : 16;
  for (let y = 0; y < H; y++) {
    const yrow = low ? (y >> 1) * yw : y * W;
    const uvrow = (y >> 1) * W;           // UV 는 늘 360x240 (가로 720 바이트)
    for (let x = 0; x < W; x++) {
      const yy = ys * (Y[yrow + (low ? x >> 1 : x)] - yo);
      const ui = uvrow + (x & ~1);
      const u = UV[ui] - 128, v = UV[ui + 1] - 128;
      const i = (y * W + x) * 4;
      let r = yy + 1.596 * v, g = yy - 0.391 * u - 0.813 * v, b = yy + 2.018 * u;
      d[i] = r < 0 ? 0 : r > 255 ? 255 : r;
      d[i + 1] = g < 0 ? 0 : g > 255 ? 255 : g;
      d[i + 2] = b < 0 ? 0 : b > 255 ? 255 : b;
      d[i + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
}
async function lvLoop() {
  for (;;) {
    if ($('#pause').checked || busy) { await sleep(200); continue; }
    busy = true;
    const low = $('#lowq').checked;
    const t0 = Date.now();
    try {
      const r = await fetch('/lv' + (low ? '?low=1' : ''), { cache: 'no-store' });
      if (r.status === 200) {
        const buf = await r.arrayBuffer();
        if (buf.byteLength === (low ? W * H / 4 * 3 : W * H * 3 / 2)) {
          nv12ToRgba(buf, low, $('#fullrange').checked);
          frames++;
        }
      } else {
        $('#lvinfo').textContent = '라이브 뷰 없음 (촬영 화면인지 확인)';
        await sleep(700);
      }
    } catch (e) { $('#lvinfo').textContent = '연결 끊김'; await sleep(1000); }
    const now = Date.now();
    if (now - lastFps >= 1000) { fps = frames * 1000 / (now - lastFps); frames = 0; lastFps = now; }
    $('#lvinfo').textContent = `${fps.toFixed(1)} fps, ${now - t0} ms${low ? ', 저화질' : ''}`;
    busy = false;
  }
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

// 키
async function key(k, a) { try { await fetch(`/key?k=${k}&a=${a || 'click'}`); } catch (e) {} }
document.querySelectorAll('#pad button[data-key]').forEach(b => b.onclick = () => key(b.dataset.key, b.dataset.act || 'click'));
$('#s1hold').onclick = () => key('s1', 'push');
$('#s1rel').onclick = () => key('s1', 'release');
$('#shoot').onclick = async () => { await key('s1', 'push'); await sleep(700); await key('s2', 'click'); await sleep(300); await key('s1', 'release'); };

// 상태
async function statusLoop() {
  for (;;) {
    try {
      const s = await (await fetch('/status', { cache: 'no-store' })).json();
      const up = parseFloat(s.uptime || '0');
      $('#status').textContent = `${s.ip || ''}  모드 ${s.mode || '?'}  드라이브 ${s.drive || '?'}  배터리 ${s.bat || '?'}${s.charging === '1' ? ' 충전' : ''}  ${s.hevc === 'ON' ? '녹화 중' : ''}  켜진 지 ${Math.floor(up / 60)}분`;
    } catch (e) { $('#status').textContent = '연결 끊김'; }
    await sleep(2000);
  }
}

// 사진
async function loadGallery() {
  const list = await (await fetch('/dcim', { cache: 'no-store' })).json();
  $('#gcount').textContent = `${list.length}장 (최근 200장까지)`;
  const g = $('#grid'); g.innerHTML = '';
  for (const f of list) {
    const d = document.createElement('div'); d.className = 'it';
    const isJpg = /\.jpg$/i.test(f.n);
    d.innerHTML = `${isJpg ? `<img loading="lazy" src="/dcim/${f.n}?thumb=1">` : `<div style="height:90px;line-height:90px">${f.n.split('.').pop()}</div>`}<div>${f.n.split('/').pop()}<br>${(f.s / 1048576).toFixed(1)} MB</div>`;
    d.onclick = () => { $('#big').src = isJpg ? `/dcim/${f.n}` : ''; $('#bigname').textContent = f.n; $('#dl').href = `/dcim/${f.n}`; $('#dl').download = f.n.split('/').pop(); $('#viewer').classList.remove('hidden'); };
    g.appendChild(d);
  }
}
$('#greload').onclick = loadGallery;
$('#close').onclick = () => $('#viewer').classList.add('hidden');

// 동작 (scripts/actions.list: 이름|표시)
async function loadActions() {
  const txt = await (await fetch('/actions', { cache: 'no-store' })).text();
  const a = $('#alist'); a.innerHTML = '';
  for (const line of txt.split('\n')) {
    if (!line || line.startsWith('#')) continue;
    const [name, label] = line.split('|');
    if (!name) continue;
    const b = document.createElement('button'); b.textContent = label || name;
    b.onclick = () => fetch(`/run?s=${name}`);
    a.appendChild(b);
  }
}

lvLoop(); statusLoop();
