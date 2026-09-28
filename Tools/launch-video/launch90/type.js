// Typography, drawn crisp on a 2D canvas above the 3D frame. Lines animate
// glyph by glyph: rising out of a mask, resolving from blur, or closing their
// tracking. Everything is a function of time, like the 3D world beneath.
import { W, H, DPR, clamp, seg, eOut3, eOut5, eOutExpo, eIn3, eInOut3, lerp } from './engine.js';

export const HEAD = 'Nunito', BODY = 'Manrope';
const cv = document.getElementById('type');
cv.width = Math.round(W * DPR); cv.height = Math.round(H * DPR);
cv.style.width = W + 'px'; cv.style.height = H + 'px';
export const g = cv.getContext('2d');

export function clear() {
  g.setTransform(1, 0, 0, 1, 0, 0);
  g.clearRect(0, 0, cv.width, cv.height);
  g.setTransform(DPR, 0, 0, DPR, 0, 0);
  g.globalAlpha = 1; g.filter = 'none'; g.globalCompositeOperation = 'source-over';
}

export function font(size, weight = 800, fam = HEAD, ls = 0) {
  g.font = `${weight} ${size}px ${fam}`; g.letterSpacing = ls + 'px';
}
export function measure(s, size, weight = 800, fam = HEAD, ls = 0) {
  g.save(); font(size, weight, fam, ls); const w = g.measureText(s).width; g.restore(); return w;
}

// The largest size, up to `size`, at which a line fits `maxW` pixels.
export function fit(s, size, weight = 800, fam = HEAD, ls = 0, maxW = 920) {
  const w = measure(s, size, weight, fam, ls);
  return w <= maxW ? size : Math.floor(size * maxW / w);
}

// Glyph x offsets for a string at the current font (letter spacing included).
function glyphs(s) {
  const out = []; let prev = 0;
  for (let i = 0; i < s.length; i++) {
    const w = g.measureText(s.slice(0, i + 1)).width;
    out.push({ ch: s[i], x: prev, w: w - prev }); prev = w;
  }
  return { list: out, width: prev };
}

// A line that arrives at t0 and, if `out` is set, leaves at `out`.
//   style: 'rise' | 'blur' | 'track' | 'fade'
//   by: 'glyph' | 'word'
export function line(s, x, y, t, t0, o = {}) {
  if (t < t0 - 0.001) return;
  const size = o.size || 96, weight = o.weight || 800, fam = o.fam || HEAD;
  const ls = o.ls ?? -1, style = o.style || 'rise', by = o.by || 'glyph';
  const stagger = o.stagger ?? (by === 'word' ? 0.12 : 0.028), dur = o.dur ?? 0.8;
  const outT = o.out, outDur = o.outDur ?? 0.45, outStyle = o.outStyle || 'blur';
  if (outT !== undefined && t > outT + outDur + stagger * (by === 'word' ? 8 : s.length) * 0.4 + 0.05) return;
  g.save();
  font(size, weight, fam, ls);
  const G = glyphs(s);
  const total = G.width;
  const align = o.align || 'center';
  const sx = align === 'center' ? x - total / 2 : align === 'right' ? x - total : x;
  const color = o.color || '#f4f5fb';
  g.textBaseline = 'alphabetic'; g.textAlign = 'left';
  // word index per glyph
  let wi = 0; const wordOf = G.list.map(c => { const w = wi; if (c.ch === ' ') wi++; return w; });
  const nUnits = by === 'word' ? wi + 1 : G.list.length;
  const scale = o.scale ?? 1;
  if (scale !== 1) { g.translate(x, y); g.scale(scale, scale); g.translate(-x, -y); }
  for (let i = 0; i < G.list.length; i++) {
    const c = G.list[i]; if (c.ch === ' ') continue;
    const unit = by === 'word' ? wordOf[i] : i;
    const k = seg(t, t0 + unit * stagger, t0 + unit * stagger + dur);
    let kOut = 0;
    if (outT !== undefined) kOut = seg(t, outT + (nUnits - 1 - unit) * stagger * 0.4, outT + (nUnits - 1 - unit) * stagger * 0.4 + outDur);
    if (k <= 0) continue;
    let a = (o.alpha ?? 1), dy = 0, blur = 0, dx = 0;
    if (style === 'rise') { const e = eOutExpo(k); dy = (1 - e) * size * 0.95; a *= clamp(k * 3); }
    else if (style === 'blur') { const e = eOut3(k); blur = (1 - e) * size * 0.22; a *= e; dy = (1 - e) * size * 0.08; }
    else if (style === 'track') { const e = eOut5(k); dx = (c.x + c.w / 2 - total / 2) * (1 - e) * 0.35; a *= e; blur = (1 - e) * size * 0.1; }
    else { a *= eOut3(k); }
    if (kOut > 0) {
      const e = eIn3(kOut);
      if (outStyle === 'blur') { blur += e * size * 0.25; a *= 1 - e; dy -= e * size * 0.06; }
      else if (outStyle === 'rise') { dy -= e * size * 0.95; a *= 1 - clamp(e * 1.4); }
      else { a *= 1 - e; }
    }
    if (a <= 0.002) continue;
    const col = o.colorAt ? o.colorAt(i, unit) || color : color;
    g.globalAlpha = a;
    g.filter = blur > 0.3 ? `blur(${blur.toFixed(2)}px)` : 'none';
    if (style === 'rise' && kOut === 0) {
      // mask: the glyph rises out of its own baseline box
      g.save();
      g.beginPath(); g.rect(sx + c.x - size, y - size * 1.05, c.w + size * 2, size * 1.35); g.clip();
      g.fillStyle = col; g.fillText(c.ch, sx + c.x + dx, y + dy);
      g.restore();
    } else {
      g.fillStyle = col; g.fillText(c.ch, sx + c.x + dx, y + dy);
    }
    if (o.glow) {
      g.save(); g.globalCompositeOperation = 'lighter'; g.globalAlpha = a * o.glow;
      g.filter = `blur(${(size * 0.18 + blur).toFixed(1)}px)`; g.fillStyle = col; g.fillText(c.ch, sx + c.x + dx, y + dy); g.restore();
    }
  }
  g.restore();
  return { x: sx, width: total };
}

// A small label pinned near a point: an overline kicker and a value.
export function label(x, y, kicker, value, a = 1, o = {}) {
  if (a <= 0.002) return;
  g.save(); g.globalAlpha = a;
  const align = o.align || 'center';
  g.textAlign = align; g.textBaseline = 'alphabetic';
  if (kicker) { font(o.kSize || 26, 700, BODY, 4); g.fillStyle = o.kColor || 'rgba(196,184,255,0.85)'; g.fillText(kicker.toUpperCase(), x, y); }
  if (value) { font(o.vSize || 54, 800, HEAD, -0.5); g.fillStyle = o.vColor || '#f4f5fb'; g.fillText(value, x, y + (o.vSize || 54) * 1.05); }
  g.restore();
}

// A pill of glass with a line of text in it.
export function pill(x, y, s, a = 1, o = {}) {
  if (a <= 0.002) return;
  const size = o.size || 30;
  g.save(); g.globalAlpha = a;
  font(size, o.weight || 700, o.fam || BODY, o.ls ?? 0.5);
  const w = g.measureText(s).width + size * 1.4, h = size * 1.9;
  const x0 = (o.align === 'left' ? x : o.align === 'right' ? x - w : x - w / 2), y0 = y - h / 2;
  g.fillStyle = o.fill || 'rgba(255,255,255,0.08)';
  g.strokeStyle = o.stroke || 'rgba(255,255,255,0.18)'; g.lineWidth = 1.5;
  g.beginPath(); g.roundRect(x0, y0, w, h, h / 2); g.fill(); g.stroke();
  g.fillStyle = o.color || '#f4f5fb'; g.textBaseline = 'middle'; g.textAlign = 'left';
  g.fillText(s, x0 + size * 0.7, y + size * 0.04);
  g.restore();
  return { w, h };
}

export function chipWidth(label, value, size = 32) {
  const wl = measure(label, size, 600, BODY, 0.3), wv = value ? measure(value, size, 700, BODY, 0.3) : 0;
  return size * 0.62 * 2 + size * 0.38 + size * 0.4 + wl + (value ? size * 0.4 + wv : 0);
}
// A legend chip in the app's style (LunarOrbitLegend): a coloured dot, the
// label, and its value in a quieter weight.
export function chip(x, y, dotColor, label, value, a = 1, o = {}) {
  if (a <= 0.002) return;
  const size = o.size || 32;
  g.save(); g.globalAlpha = a;
  font(size, 600, BODY, 0.3); const wl = g.measureText(label).width;
  let wv = 0; if (value) { font(size, 700, BODY, 0.3); wv = g.measureText(value).width; }
  const dot = size * 0.38, gap = size * 0.4, padX = size * 0.62;
  const w = padX + dot + gap + wl + (value ? gap + wv : 0) + padX, h = size * 1.86;
  const x0 = (o.align === 'left' ? x : o.align === 'right' ? x - w : x - w / 2), y0 = y - h / 2;
  g.fillStyle = o.fill || 'rgba(255,255,255,0.07)'; g.strokeStyle = o.stroke || 'rgba(255,255,255,0.16)'; g.lineWidth = 2;
  g.beginPath(); g.roundRect(x0, y0, w, h, h / 2); g.fill(); g.stroke();
  g.fillStyle = dotColor; g.beginPath(); g.arc(x0 + padX + dot / 2, y, dot / 2, 0, Math.PI * 2); g.fill();
  g.textBaseline = 'middle'; g.textAlign = 'left';
  font(size, 600, BODY, 0.3); g.fillStyle = o.color || '#f4f5fb'; g.fillText(label, x0 + padX + dot + gap, y + size * 0.04);
  if (value) { font(size, 700, BODY, 0.3); g.fillStyle = o.vColor || 'rgba(214,216,232,0.82)'; g.fillText(value, x0 + padX + dot + gap + wl + gap, y + size * 0.04); }
  g.restore();
  return { w, h };
}

export { lerp, eInOut3 };
