// Shared drawing kit for the Zoon films (showreel.html, free.html).
// A film sets window.REEL_DURATION, loads this file, declares its scenes and
// cues, then calls finishReel(story) with a function that draws story time t.
// Query flags: ?v=1 for the 9:16 phone layout, ?clean=1 for copies that a
// messaging app will re-compress.
'use strict';
// ?v=1 lays every scene out for a 9:16 phone screen instead.
const V = /[?&]v=1/.test(location.search);
// ?clean=1 drops the film grain and the star twinkle: detail that costs
// bits, for copies that a messaging app will re-compress (WhatsApp).
const CLEAN = /[?&]clean=1/.test(location.search);
const W = V ? 1080 : 1920, H = V ? 1920 : 1080, DUR = window.REEL_DURATION || 100;
const vh = (land, vert) => V ? vert : land;
const cv = document.getElementById('c'), DPR = window.devicePixelRatio || 1;
cv.width = W * DPR; cv.height = H * DPR;
for (const el of [document.documentElement, document.body, cv]) { el.style.width = W + 'px'; el.style.height = H + 'px'; }
const g = cv.getContext('2d');
const scratch = document.createElement('canvas'); scratch.width = cv.width; scratch.height = cv.height;
const sg = scratch.getContext('2d');

// ---------- palette and type ----------
const C = {
  ink: '#f4f5fb', ink2: 'rgba(244,245,251,0.74)', ink3: 'rgba(244,245,251,0.5)',
  violet: '#7b61ff', lilac: '#c4b8ff', amber: '#ffa23e', calm: '#3fd6a0', sky: '#62b3ff',
  heart: '#ff5a64', pink: '#ff6ec7', deep: '#8a74ff', night: '#05060f'
};
const HEAD = 'Nunito', BODY = 'Manrope';

// ---------- maths ----------
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const lerp = (a, b, k) => a + (b - a) * k;
const seg = (t, a, b) => clamp((t - a) / (b - a));
const eOut = k => 1 - Math.pow(1 - k, 3);
const eOut5 = k => 1 - Math.pow(1 - k, 5);
const eExpo = k => k >= 1 ? 1 : 1 - Math.pow(2, -10 * k);
const eIn = k => k * k * k;
const eInOut = k => k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;
const eBack = k => { const c1 = 2.2, c3 = c1 + 1; return 1 + c3 * Math.pow(k - 1, 3) + c1 * Math.pow(k - 1, 2); };
const spring = (k, f = 3.2, d = 6) => k <= 0 ? 0 : k >= 1 ? 1 : 1 - Math.exp(-d * k) * Math.cos(f * Math.PI * k);
function rng(seed) { return () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
const fmtHM = m => `${Math.floor(m / 60)}h ${String(Math.round(m % 60)).padStart(2, '0')}m`;
function clock(minsAfterMidnight) {
  let m = ((Math.round(minsAfterMidnight) % 1440) + 1440) % 1440;
  const h = Math.floor(m / 60), mm = m % 60, ap = h < 12 ? 'AM' : 'PM', h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${String(mm).padStart(2, '0')} ${ap}`;
}

// ---------- sound cues (exported for the score) ----------
const CUES = [];
const cue = (t, kind, gain = 1, pan = 0, extra = {}) => CUES.push({ t: +t.toFixed(3), kind, gain, pan, ...extra });

// ---------- assets ----------
const SHOT = n => '../../docs/screenshots/hires/' + n + '.jpg';
const PHONES = ['today', 'coach', 'bodyClock', 'breathing', 'snoreCheck', 'soundscapes', 'nap', 'journal', 'patterns',
  'tomorrow', 'evidence', 'nightHistory', 'sleepDetail', 'sleepDetail-heart', 'today-morning', 'trends', 'trends-forYourAge', 'today-night'];
const FACES = ['page-today', 'page-tonight', 'page-nap', 'page-scorelight'];
const IMG = {};
for (const n of PHONES) { const im = new Image(); im.src = SHOT(n); IMG[n] = im; }
for (const n of FACES) { const im = new Image(); im.src = '../../docs/screenshots/watch/hires/' + n + '.jpg'; IMG[n] = im; }
const PH = {};
function buildPhone(im) {
  const cn = document.createElement('canvas'); cn.width = 900; cn.height = 1900; const q = cn.getContext('2d');
  const gr = q.createLinearGradient(0, 0, 900, 1900);
  gr.addColorStop(0, '#454a63'); gr.addColorStop(0.3, '#151722'); gr.addColorStop(0.7, '#10111a'); gr.addColorStop(1, '#2d3044');
  q.fillStyle = gr; q.beginPath(); q.roundRect(0, 0, 900, 1900, 150); q.fill();
  q.strokeStyle = 'rgba(255,255,255,0.22)'; q.lineWidth = 3; q.beginPath(); q.roundRect(2, 2, 896, 1896, 148); q.stroke();
  q.save(); q.beginPath(); q.roundRect(24, 24, 852, 1852, 128); q.clip(); q.drawImage(im, 24, 24, 852, 1852);
  const sh = q.createLinearGradient(0, 0, 900, 1100);
  sh.addColorStop(0, 'rgba(255,255,255,0.09)'); sh.addColorStop(0.45, 'rgba(255,255,255,0)');
  q.fillStyle = sh; q.fillRect(0, 0, 900, 1900); q.restore();
  return cn;
}

// ---------- drawing helpers ----------
function glowAt(x, y, r, col, a = 1) {
  if (a <= 0) return;
  g.save(); g.globalAlpha *= a;
  const gr = g.createRadialGradient(x, y, 0, x, y, r);
  gr.addColorStop(0, col); gr.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = gr; g.fillRect(x - r, y - r, 2 * r, 2 * r); g.restore();
}
function dot(x, y, r, col = '#ffffff', glowCol = 'rgba(196,184,255,0.55)') {
  if (r <= 0) return;
  glowAt(x, y, r * 9, glowCol);
  g.fillStyle = col; g.beginPath(); g.arc(x, y, r, 0, Math.PI * 2); g.fill();
}
function setFont(size, weight, fam, ls = 0) { g.font = `${weight} ${size}px ${fam}`; g.letterSpacing = ls + 'px'; }
function text(s, x, y, o = {}) {
  g.save(); setFont(o.size || 40, o.weight || 800, o.fam || HEAD, o.ls || 0);
  g.textAlign = o.align || 'left'; g.textBaseline = o.base || 'alphabetic';
  g.globalAlpha *= (o.a ?? 1); g.fillStyle = o.color || C.ink; g.fillText(s, x, y);
  const w = g.measureText(s).width; g.restore(); return w;
}
function measure(s, size, weight, fam, ls = 0) { g.save(); setFont(size, weight, fam, ls); const w = g.measureText(s).width; g.restore(); return w; }
// A line whose letters rise out of a mask, one after another, and leave the
// same way at `o.out`.
function kline(s, x, y, t, t0, o = {}) {
  if (t < t0) return 0;
  const size = o.size || 86, weight = o.weight || 900, fam = o.fam || HEAD, ls = o.ls ?? -1;
  const st = o.stagger ?? 0.022, d = o.dur ?? 0.75, align = o.align || 'left';
  if (o.out !== undefined && t > o.out + s.length * st * 0.5 + 0.4) return 0;
  g.save(); setFont(size, weight, fam, ls); g.textAlign = 'left';
  const total = g.measureText(s).width;
  const sx = align === 'center' ? x - total / 2 : align === 'right' ? x - total : x;
  g.beginPath(); g.rect(sx - size, y - size * 1.08, total + size * 2, size * 1.42); g.clip();
  const fill = typeof o.color === 'function' ? o.color(sx, total) : (o.color || C.ink);
  for (let i = 0; i < s.length; i++) {
    const ch = s[i]; if (ch === ' ') continue;
    const xi = g.measureText(s.slice(0, i)).width;
    const k = eExpo(seg(t, t0 + i * st, t0 + i * st + d));
    let dy = (1 - k) * size * 1.1;
    if (o.out !== undefined) dy -= eIn(seg(t, o.out + i * st * 0.5, o.out + i * st * 0.5 + 0.38)) * size * 1.15;
    g.globalAlpha = (o.a ?? 1) * clamp(k * 1.6);
    g.fillStyle = fill; g.fillText(ch, sx + xi, y + dy);
  }
  g.restore(); return total;
}
const gradText = (a, b) => (sx, w) => { const gr = g.createLinearGradient(sx, 0, sx + w, 0); gr.addColorStop(0, a); gr.addColorStop(1, b); return gr; };
// Fade-and-rise for body copy.
function rise(s, x, y, t, t0, o = {}) {
  const k = eOut(seg(t, t0, t0 + 0.7));
  let a = k; if (o.out !== undefined) a *= 1 - seg(t, o.out, o.out + 0.3);
  if (a <= 0) return;
  text(s, x, y + (1 - k) * 22, { size: 30, weight: 500, fam: BODY, color: C.ink2, ...o, a: a * (o.a ?? 1) });
}
// A picture on a plane turned about its vertical axis, drawn in strips so the
// far edge really is smaller.
function plane(src, cx, cy, h, yaw = 0, roll = 0) {
  const sw = src.width, sh = src.height, w = h * sw / sh, f = 2400, N = 96;
  const co = Math.cos(yaw), si = Math.sin(yaw);
  g.save(); g.translate(cx, cy); g.rotate(roll);
  if (Math.abs(yaw) < 0.002) { g.drawImage(src, -w / 2, -h / 2, w, h); g.restore(); return; }
  const P = X => { const k = f / (f + X * si); return [X * co * k, k]; };
  for (let i = 0; i < N; i++) {
    const u0 = i / N, u1 = (i + 1) / N;
    const [x0, k0] = P((u0 - 0.5) * w), [x1, k1] = P((u1 - 0.5) * w), k = (k0 + k1) / 2;
    g.drawImage(src, u0 * sw, 0, sw / N, sh, x0, -h * k / 2, x1 - x0 + 0.8, h * k);
  }
  g.restore();
}
function phone(name, cx, cy, h, o = {}) {
  const src = PH[name]; if (!src) return;
  const a = o.a ?? 1; if (a <= 0) return;
  g.save(); g.globalAlpha *= a;
  const w = h * 900 / 1900;
  g.save(); g.translate(cx, cy + h * 0.5); g.scale(1, 0.1);
  const sh = g.createRadialGradient(0, 0, 0, 0, 0, w * 0.95); sh.addColorStop(0, 'rgba(0,0,0,0.6)'); sh.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = sh; g.beginPath(); g.arc(0, 0, w * 0.95, 0, 7); g.fill(); g.restore();
  if (o.glow !== 0) glowAt(cx, cy, h * 0.75, o.glowCol || 'rgba(123,97,255,0.22)');
  plane(src, cx, cy, h, o.yaw || 0, o.roll || 0);
  g.restore();
}
function chip(x, y, val, key, col, a = 1, s = 1) {
  if (a <= 0.01) return;
  g.save(); g.translate(x, y); g.scale(s, s); g.globalAlpha *= a;
  const vw = measure(val, 32, 800, HEAD), kw = measure(key, 14, 800, BODY, 2.5);
  const w = Math.max(vw, kw) + 92, h = 78;
  g.fillStyle = 'rgba(16,18,40,0.9)'; g.beginPath(); g.roundRect(-w / 2, -h / 2, w, h, 24); g.fill();
  g.strokeStyle = 'rgba(255,255,255,0.12)'; g.lineWidth = 1.5; g.stroke();
  g.fillStyle = col; g.globalAlpha *= 0.95; g.beginPath(); g.roundRect(-w / 2 + 14, -20, 40, 40, 13); g.fill();
  g.fillStyle = 'rgba(255,255,255,0.9)'; g.beginPath(); g.arc(-w / 2 + 34, 0, 6, 0, 7); g.fill();
  text(val, -w / 2 + 70, 5, { size: 32, weight: 800, color: C.ink });
  text(key, -w / 2 + 70, 27, { size: 14, weight: 800, fam: BODY, ls: 2.5, color: C.ink3 });
  g.restore();
}
function pill(x, y, s, col, a = 1, sc = 1, align = 'left') {
  if (a <= 0.01) return;
  const w = measure(s, 22, 800, BODY) + 40, h = 44;
  const x0 = align === 'center' ? -w / 2 : align === 'right' ? -w : 0;
  g.save(); g.translate(x, y); g.scale(sc, sc); g.globalAlpha *= a;
  g.fillStyle = col; g.globalAlpha *= 0.2; g.beginPath(); g.roundRect(x0, -h / 2, w, h, 22); g.fill();
  g.globalAlpha /= 0.2; text(s, x0 + 20, 8, { size: 22, weight: 800, fam: BODY, color: col });
  g.restore();
}
function kicker(s, x, y, t, t0, o = {}) {
  kline(s, x, y, t, t0, { size: 22, weight: 800, fam: BODY, ls: 7, color: o.color || C.lilac, stagger: 0.012, ...o });
}
// The crescent from the app icon: a disc with a second disc taken out of it.
function arcVia(cx, cy, r, from, to, via) {
  const n = a => ((a % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI);
  g.arc(cx, cy, r, from, to, !(n(via - from) < n(to - from)));
}
function crescent(cx, cy, r, carve, a = 1, glow = 1) {
  if (r <= 0 || a <= 0) return;
  g.save(); g.globalAlpha *= a;
  glowAt(cx, cy, r * 2.6, 'rgba(160,150,255,0.25)', glow);
  const bx = cx + lerp(1.9, 0.4, carve) * r, by = cy + lerp(-1.3, -0.22, carve) * r, rr = 0.92 * r;
  const dx = bx - cx, dy = by - cy, d = Math.hypot(dx, dy);
  g.beginPath();
  if (d >= r + rr) g.arc(cx, cy, r, 0, Math.PI * 2);
  else {
    const q = (r * r - rr * rr + d * d) / (2 * d), h = Math.sqrt(Math.max(0, r * r - q * q)), ux = dx / d, uy = dy / d;
    const px = cx + q * ux, py = cy + q * uy, p1 = [px - h * uy, py + h * ux], p2 = [px + h * uy, py - h * ux];
    const beta = Math.atan2(dy, dx);
    g.moveTo(p1[0], p1[1]);
    arcVia(cx, cy, r, Math.atan2(p1[1] - cy, p1[0] - cx), Math.atan2(p2[1] - cy, p2[0] - cx), beta + Math.PI);
    arcVia(bx, by, rr, Math.atan2(p2[1] - by, p2[0] - bx), Math.atan2(p1[1] - by, p1[0] - bx), beta + Math.PI);
    g.closePath();
  }
  g.shadowColor = 'rgba(200,196,255,0.9)'; g.shadowBlur = r * 0.35 * glow;
  const gr = g.createLinearGradient(0, cy - r, 0, cy + r); gr.addColorStop(0, '#f6f6f3'); gr.addColorStop(1, '#dbe3f6');
  g.fillStyle = gr; g.fill();
  g.restore();
}
// A moon lit by `f` of its face, the way the Month recap draws a night.
function moonPhase(cx, cy, r, f, a = 1, lit = '#e9e6ff') {
  g.save(); g.globalAlpha *= a;
  g.fillStyle = 'rgba(255,255,255,0.07)'; g.beginPath(); g.arc(cx, cy, r, 0, 7); g.fill();
  g.strokeStyle = 'rgba(255,255,255,0.12)'; g.lineWidth = 1.5; g.stroke();
  if (f > 0.005) {
    const k = 1 - 2 * clamp(f);
    g.beginPath(); g.moveTo(cx, cy - r); g.arc(cx, cy, r, -Math.PI / 2, Math.PI / 2);
    for (let i = 0; i <= 32; i++) { const p = Math.PI / 2 - i / 32 * Math.PI; g.lineTo(cx + k * r * Math.cos(p), cy + r * Math.sin(p)); }
    g.closePath(); g.fillStyle = lit; g.shadowColor = 'rgba(196,184,255,0.8)'; g.shadowBlur = f >= 1 ? r * 0.6 : 0; g.fill();
  }
  g.restore();
}
function ecg(p) {
  p = p - Math.floor(p);
  const gs = (c, w, a) => a * Math.exp(-Math.pow((p - c) / w, 2));
  return gs(0.18, 0.03, 0.12) - gs(0.355, 0.008, 0.16) + gs(0.385, 0.011, 1) - gs(0.415, 0.01, 0.3) + gs(0.62, 0.05, 0.24);
}

// ---------- the sky ----------
const STARS = (() => { const r = rng(7), s = []; for (let i = 0; i < 420; i++) s.push({ x: r() * W, y: r() * H, z: 0.2 + r() * 0.8, tw: r() * 6.28, r: 0.4 + r() * 1.3 }); return s; })();
function stars(t, a = 1, drift = 1) {
  if (a <= 0) return;
  g.save();
  for (const s of STARS) {
    const x = ((s.x - t * 9 * s.z * drift) % W + W) % W;
    const tw = CLEAN ? 0.8 : 0.55 + 0.45 * Math.sin(t * 1.7 + s.tw);
    g.globalAlpha = a * s.z * tw * 0.85; g.fillStyle = '#dfe2ff';
    g.beginPath(); g.arc(x, s.y, s.r * s.z, 0, 7); g.fill();
  }
  g.restore();
}
function bg(t, starA = 1, tint = 'rgba(123,97,255,0.12)') {
  const gr = g.createLinearGradient(0, 0, 0, H); gr.addColorStop(0, '#0c0e27'); gr.addColorStop(1, '#04050c');
  g.fillStyle = gr; g.fillRect(0, 0, W, H);
  glowAt(W * 0.22 + Math.sin(t * 0.09) * 140, H * 0.28, 820, tint);
  glowAt(W * 0.82, H * 0.78 + Math.cos(t * 0.07) * 90, 700, 'rgba(98,179,255,0.06)');
  stars(t, starA);
}
function burst(cx, cy, t, t0, n = 70, speed = 900, col = '#e6e0ff', seed = 3) {
  const u = t - t0; if (u < 0 || u > 1.6) return;
  const r = rng(seed);
  g.save();
  for (let i = 0; i < n; i++) {
    const a = r() * Math.PI * 2, v = speed * (0.25 + r() * 0.9), life = 0.6 + r() * 0.9;
    if (u > life) continue;
    const d = v * (1 - Math.exp(-u * 3.2)) / 3.2 * 3;
    const x = cx + Math.cos(a) * d, y = cy + Math.sin(a) * d;
    g.globalAlpha = (1 - u / life) * 0.9; g.fillStyle = col;
    g.beginPath(); g.arc(x, y, 1 + r() * 2.2, 0, 7); g.fill();
  }
  g.restore();
}
function shock(cx, cy, t, t0, r0 = 100, speed = 1500, col = '200,190,255') {
  const u = t - t0; if (u < 0 || u > 0.9) return;
  g.save(); g.globalAlpha = Math.pow(1 - u / 0.9, 2) * 0.8;
  g.strokeStyle = `rgb(${col})`; g.lineWidth = 3 + 14 * (1 - u / 0.9);
  g.beginPath(); g.arc(cx, cy, r0 + eOut(u / 0.9) * speed * 0.9, 0, 7); g.stroke(); g.restore();
}


// Post-processing and the page contract (render, DURATION, CUES, ready),
// wired once every scene has declared its cues.
function finishReel(story) {
  // camera shake, keyed to the hits
  const SHAKES = CUES.filter(c => ['boom', 'hit', 'latch', 'land'].includes(c.kind)).map(c => [c.t, c.kind === 'boom' ? 16 : c.kind === 'latch' ? 9 : c.kind === 'land' ? 5 : 7]);
  function shake(t) {
    let x = 0, y = 0;
    for (const [t0, a] of SHAKES) { const u = t - t0; if (u < 0 || u > 0.5) continue; const e = a * Math.exp(-u * 11); x += Math.sin(u * 83 + t0) * e; y += Math.cos(u * 71 + t0 * 2) * e; }
    return [x, y];
  }
  const FLASH = CUES.filter(c => c.kind === 'boom' || c.kind === 'cut' || (c.kind === 'hit' && c.gain >= 1)).map(c => [c.t, c.kind === 'boom' ? 0.85 : c.kind === 'cut' ? 0.22 : 0.3]);
  const WHIPS = CUES.filter(c => c.kind === 'whoosh' || c.kind === 'whooshL').map(c => c.t);
  // grain
  const GRAIN = [0, 1, 2].map(s => { const cn = document.createElement('canvas'); cn.width = cn.height = 256; const q = cn.getContext('2d'); const id = q.createImageData(256, 256); const r = rng(100 + s);
    for (let i = 0; i < id.data.length; i += 4) { const v = r() * 255; id.data[i] = id.data[i + 1] = id.data[i + 2] = v; id.data[i + 3] = 255; } q.putImageData(id, 0, 0); return cn; });
  function post(t) {
    // whip smear: the frame dragged along itself
    let sm = 0; for (const w of WHIPS) { const u = t - w; if (u > -0.15 && u < 0.45) sm = Math.max(sm, Math.exp(-Math.pow((u - 0.12) / 0.14, 2))); }
    if (sm > 0.05) {
      sg.setTransform(1, 0, 0, 1, 0, 0); sg.clearRect(0, 0, scratch.width, scratch.height); sg.drawImage(cv, 0, 0);
      g.save(); g.setTransform(1, 0, 0, 1, 0, 0);
      for (let i = 1; i <= 6; i++) { g.globalAlpha = 0.14 * sm; g.drawImage(scratch, i * 18 * sm * DPR, 0); g.drawImage(scratch, -i * 18 * sm * DPR, 0); }
      g.restore();
    }
    let fl = 0; for (const [t0, a] of FLASH) { const u = t - t0; if (u >= 0 && u < 0.4) fl = Math.max(fl, a * Math.exp(-u * 14)); }
    if (fl > 0.01) { g.fillStyle = `rgba(236,232,255,${fl})`; g.fillRect(0, 0, W, H); }
    const vg = g.createRadialGradient(W / 2, H / 2, H * 0.45, W / 2, H / 2, H * 1.05);
    vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,0.5)'); g.fillStyle = vg; g.fillRect(0, 0, W, H);
    if (CLEAN) return;
    g.save(); g.globalCompositeOperation = 'overlay'; g.globalAlpha = 0.07;
    const fr = Math.floor(t * 30); const pat = g.createPattern(GRAIN[fr % 3], 'repeat');
    g.translate((fr * 37) % 256, (fr * 91) % 256); g.fillStyle = pat; g.fillRect(-256, -256, W + 512, H + 512); g.restore();
  }
  window.render = function (t) {
    g.setTransform(DPR, 0, 0, DPR, 0, 0);
    g.globalAlpha = 1; g.globalCompositeOperation = 'source-over'; g.shadowBlur = 0; g.filter = 'none';
    g.fillStyle = '#030409'; g.fillRect(0, 0, W, H);
    const [sx, sy] = shake(t);
    g.save(); g.translate(sx, sy); story(t); g.restore();
    post(t);
  };
  window.DURATION = DUR;
  window.CUES = CUES.sort((a, b) => a.t - b.t);
  window.ready = Promise.all([
    ...['900 20px Nunito', '800 20px Nunito', '500 20px Manrope', '600 20px Manrope', '700 20px Manrope', '800 20px Manrope'].map(f => document.fonts.load(f)),
    ...Object.values(IMG).map(im => im.decode().catch(() => {}))
  ]).then(() => { for (const n of PHONES) PH[n] = buildPhone(IMG[n]); window.render(0); return true; });
}
