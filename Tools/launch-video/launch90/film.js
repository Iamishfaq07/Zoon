// The Zoon launch film: 90 seconds, 9:16, on a 120 BPM clock (a beat is
// 0.5 s, a bar 2 s), so every cut the score lands on is a beat.
import {
  THREE, scene, camera, drawFrame, grade, bloomCfg, W, H, GPU, CLEAN,
  clamp, lerp, seg, smooth, smoother, track, eOut3, eOut5, eOutExpo, eIn3, eInExpo, eInOut3, eInOut5, eInOutExpo, eOutBack, spring, vnoise, rng,
  lin, PAL, css, tex, texturesLoaded, canvasTex, card, setCardSize, cardMaterial, glow, Ribbon, arc, Cloud, lookFrom, project, worldToScreenScale
} from './engine.js';
import * as T from './type.js';
import * as D from './data.js';
import { Phone, Watch, pose, CAP_W, CAP_H, SCREEN_W, SCREEN_H, capX, capY, FRONT } from './phone.js';

const BPM = 120, BEAT = 60 / BPM, DURATION = 90;
const CUES = [], MUSIC = [];
const cue = (t, kind, o = {}) => CUES.push({ t: +t.toFixed(3), kind, gain: 1, pan: 0, ...o });
const mark = (t, name, o = {}) => MUSIC.push({ t, name, ...o });

// Everything registered here is hidden at the start of each frame; scenes
// show what they draw.
const all = [];
const reg = o => { all.push(o); scene.add(o); o.visible = false; return o; };
const show = (o, v = true) => { o.visible = v; return o; };

const V3 = (x, y, z) => new THREE.Vector3(x, y, z);
const L = rgb => lin(rgb);

// ================================================================ the world
// Background: the app's night ground (Theme.swift), a soft cool glow that
// follows the light, and a dawn that can rise from below.
const bgMat = new THREE.ShaderMaterial({
  depthTest: false, depthWrite: false,
  uniforms: {
    intensity: { value: 1 }, dawn: { value: 0 }, time: { value: 0 }, glowPos: { value: new THREE.Vector2(0.5, 0.62) },
    glowAmt: { value: 0.35 }, glowCol: { value: new THREE.Vector3(...L([0.30, 0.38, 0.92])) },
    c0: { value: new THREE.Vector3(...L(PAL.ground0)) }, c1: { value: new THREE.Vector3(...L(PAL.ground1)) }, c2: { value: new THREE.Vector3(...L(PAL.ground2)) },
    par: { value: new THREE.Vector2() }
  },
  vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.9999, 1.); }',
  fragmentShader: `uniform float intensity, dawn, time, glowAmt; uniform vec2 glowPos, par; uniform vec3 glowCol, c0, c1, c2; varying vec2 vUv;
    float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
    float n(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3. - 2. * f);
      return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
    float fbm(vec2 p){ float s = 0., a = 0.5; for (int i = 0; i < 5; i++) { s += a * n(p); p *= 2.03; a *= 0.5; } return s; }
    void main(){
      vec2 uv = vUv;
      vec3 c = uv.y > 0.5 ? mix(c1, c0, (uv.y - 0.5) * 2.) : mix(c2, c1, uv.y * 2.);
      vec2 q = (uv - glowPos) * vec2(1.0, 1.78);
      c += glowCol * glowAmt * exp(-dot(q, q) * 2.2) * 0.35;
      float neb = fbm(uv * vec2(2.2, 3.6) + par + vec2(time * 0.012, -time * 0.006));
      c += glowCol * 0.05 * smoothstep(0.45, 0.95, neb) * glowAmt;
      vec3 dawnCol = vec3(0.55, 0.28, 0.16) * 0.22;
      c = mix(c, c + dawnCol * pow(1. - uv.y, 2.2) + vec3(0.06, 0.04, 0.07) * (1. - uv.y) * 0.4, dawn);
      gl_FragColor = vec4(c * intensity, 1.);
    }`
});
const bg = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), bgMat);
bg.frustumCulled = false; bg.renderOrder = -1000; scene.add(bg);

// Stars: sparse and a little large, because a messaging app's encoder
// erases anything finer.
const stars = (() => {
  const n = 300, r = rng(11), pos = new Float32Array(n * 3), col = new Float32Array(n * 3), a = new Float32Array(n * 3), seed = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const u = r() * 2 - 1, th = r() * Math.PI * 2, rad = 70 + r() * 30, s = Math.sqrt(1 - u * u);
    a[i * 3] = rad * s * Math.cos(th); a[i * 3 + 1] = rad * u; a[i * 3 + 2] = rad * s * Math.sin(th) - 30;
    const b = 0.25 + Math.pow(r(), 3) * 1.4, warm = r();
    col[i * 3] = b * (0.85 + warm * 0.15); col[i * 3 + 1] = b * 0.9; col[i * 3 + 2] = b; seed[i] = r();
  }
  const c = new Cloud(n, 3);
  c.a.set(a); c.b.set(a); c.col.set(col);
  c.geo.attributes.a.needsUpdate = true; c.geo.attributes.b.needsUpdate = true; c.geo.attributes.col.needsUpdate = true;
  c.mat.uniforms.size.value = 0.3; c.mat.uniforms.morph.value = 0;
  return c;
})();
reg(stars.points);

// Dust: slow motes in front of the camera, for depth.
const dust = new Cloud(170, 21);
{
  const r = rng(5);
  dust.layout('a', () => [(r() - 0.5) * 9, (r() - 0.5) * 16, -14 + r() * 17]);
  const b = dust.a.slice();
  for (let i = 0; i < dust.n; i++) { b[i * 3 + 1] += 1.6 + r() * 1.2; b[i * 3] += (r() - 0.5) * 0.6; }
  dust.b.set(b); dust.geo.attributes.b.needsUpdate = true;
  dust.colors(() => { const k = 0.05 + r() * 0.09; return [k * 0.8, k * 0.86, k]; });
  dust.mat.uniforms.size.value = 0.55; dust.mat.uniforms.spread.value = 0.0;
}
dust.points.renderOrder = 40;   // after the phone's screen, so motes in front of it stay in front
reg(dust.points);

// The first light.
const seed = reg(glow(L([0.86, 0.88, 1.0]), 3.2));
seed.material.uniforms.core.value = 6;

// Faint sleep waves behind the question.
const waves = [0, 1, 2].map(i => {
  const rb = new Ribbon(260, { color: L([0.45, 0.42, 0.95]), color2: L([0.36, 0.62, 0.98]), width: 0.05 });
  rb.mat.uniforms.softness.value = 1.0;
  reg(rb.mesh); return rb;
});

// The one line: typography collapses into it, it becomes a sleep wave, the
// wave curls into the moon.
const line = new Ribbon(420, { color: L([0.80, 0.82, 1.0]), color2: L([0.62, 0.70, 1.0]), width: 0.026 });
reg(line.mesh);
const lineHead = reg(glow(L([0.8, 0.85, 1.0]), 2.6));
// What is left of the collapsed line ahead of the head, as it dissolves.
const lineRest = new Ribbon(60, { color: L([0.80, 0.82, 1.0]), color2: L([0.62, 0.70, 1.0]), width: 0.022 });
reg(lineRest.mesh);

// The moon: the app's own photograph (Zoon/Assets.xcassets/MoonTexture),
// shaded into a phase by a sun direction, with earthshine and a halo.
const moonTex = tex('/Zoon/Assets.xcassets/MoonTexture.imageset/moon.png');
const moonMat = new THREE.ShaderMaterial({
  transparent: true, depthWrite: true, premultipliedAlpha: true,
  uniforms: { map: { value: moonTex }, sun: { value: new THREE.Vector3(0.3, 0.1, 1).normalize() }, opacity: { value: 1 }, blur: { value: 0 },
    lit: { value: 1.35 }, earth: { value: 0.04 }, rimAmt: { value: 0.35 }, tint: { value: new THREE.Vector3(1, 1, 1) } },
  vertexShader: `varying vec3 vN; varying vec3 vObjN; varying vec3 vView;
    void main(){ vObjN = normalize(position); vN = normalize(normalMatrix * normal); vec4 mv = modelViewMatrix * vec4(position, 1.); vView = -mv.xyz; gl_Position = projectionMatrix * mv; }`,
  fragmentShader: `uniform sampler2D map; uniform vec3 sun, tint; uniform float opacity, lit, earth, rimAmt, blur; varying vec3 vN; varying vec3 vObjN; varying vec3 vView;
    void main(){
      vec3 n = normalize(vObjN);
      vec2 uv = n.xy * 0.49 + 0.5;
      vec3 alb = blur > 0. ? textureLod(map, uv, blur * 7.).rgb : texture2D(map, uv).rgb;
      float l = dot(n, normalize(sun));
      float day = smoothstep(-0.04, 0.16, l);
      float fres = pow(1. - max(0., dot(normalize(vN), normalize(vView))), 3.);
      vec3 c = alb * (day * lit * (0.55 + 0.45 * max(l, 0.)) + earth) * tint;
      c += vec3(0.55, 0.6, 1.0) * fres * rimAmt * (0.25 + day);
      // out of focus, the limb softens
      float nv = max(0., dot(normalize(vN), normalize(vView)));
      float a = opacity * (blur > 0. ? smoothstep(0., 0.05 + blur * 0.5, nv) : 1.);
      gl_FragColor = vec4(c * a, a);
    }`
});
const moon = reg(new THREE.Group());
const moonBall = new THREE.Mesh(new THREE.SphereGeometry(1, 96, 64), moonMat);
moon.add(moonBall);
const halo = glow(L([0.55, 0.60, 1.0]), 2.4); halo.scale.setScalar(5.5); halo.position.z = -0.4; moon.add(halo);
const halo2 = glow(L([0.35, 0.38, 0.9]), 1.4); halo2.scale.setScalar(11); halo2.position.z = -0.8; moon.add(halo2);
const moonRing = arc({ color: L([0.85, 0.88, 1.0]), thickness: 0.018 });
reg(moonRing);

// ================================================================ helpers
function resetFrame(t) {
  grade.exposure = 1; grade.bloom = 0.7; grade.vignette = 0.55; grade.fade = 0; grade.flash = 0; grade.chroma = 0;
  grade.saturation = 1; grade.contrast = 1;
  bloomCfg.threshold = 0.9; bloomCfg.knee = 0.55; bloomCfg.radius = 1.0;
  bgMat.uniforms.intensity.value = 1; bgMat.uniforms.dawn.value = 0; bgMat.uniforms.time.value = t;
  bgMat.uniforms.glowAmt.value = 0.35; bgMat.uniforms.glowPos.value.set(0.5, 0.62);
  camera.fov = 32; camera.updateProjectionMatrix();
  lookFrom([0, 0, 10], [0, 0, 0]);
  for (const c of [stars, dust]) c.mat.uniforms.time.value = t;
}
// Sleep-wave shape: slow deltas with a spindle riding on them.
const sleepWave = (x, t, amp = 1, seedPhase = 0) =>
  amp * (0.42 * Math.sin(x * 1.7 - t * 2.1 + seedPhase) + 0.22 * Math.sin(x * 3.9 - t * 3.4 + seedPhase * 2.1)
    + 0.10 * Math.sin(x * 9.3 - t * 6.0) * Math.exp(-Math.pow(Math.sin(x * 0.7 - t * 0.8), 2) * 3));

// ================================================================ timeline
// SCENE 01 + 02 — the hook and the question (0:00 – 0:08)
mark(0, 'intro'); mark(4, 'question'); mark(8, 'wave'); mark(11, 'reveal');
cue(0.55, 'glint', { gain: 0.6 }); cue(3.0, 'heartbeat'); cue(3.5, 'heartbeat', { gain: 0.55 });
cue(4.0, 'pulse'); cue(5.35, 'draw', { gain: 0.5 }); cue(7.0, 'rev', { dur: 1.0 }); cue(7.85, 'snap'); cue(8.0, 'tone', { gain: 0.5 });
function sHook(t) {
  // black to night: the ground comes up under the light
  bgMat.uniforms.intensity.value = smooth(seg(t, 0.4, 6.0)) * 0.9;
  bgMat.uniforms.glowAmt.value = 0.15 + 0.2 * seg(t, 1, 6);
  grade.vignette = 0.75;
  // the camera eases forward; faster once the question lands
  const z = lerp(10.6, 9.6, eInOut3(seg(t, 0, 4))) - 2.2 * eInOut3(seg(t, 4, 8.2));
  lookFrom([0, vnoise(t * 0.3) * 0.02, z], [0, 0, 0]);
  show(stars.points); stars.mat.uniforms.opacity.value = 0.55 * smooth(seg(t, 1.2, 6));
  show(dust.points); dust.mat.uniforms.opacity.value = 0.9 * smooth(seg(t, 0.8, 3.5)) * (1 - seg(t, 7.3, 8.1));
  dust.mat.uniforms.morph.value = seg(t, 0, 16);

  // the seed of light, and a heartbeat at 3.0 and 3.5
  const beat = Math.exp(-Math.pow((t - 3.0) / 0.09, 2)) + 0.55 * Math.exp(-Math.pow((t - 3.5) / 0.09, 2));
  const grow = smooth(seg(t, 0.45, 1.2)) * (1 + 0.35 * seg(t, 1.2, 4));
  const fadeForQuestion = 1 - 0.7 * smooth(seg(t, 4.0, 5.0));
  const sink = eInOut3(seg(t, 7.45, 7.88));
  const absorb = seg(t, 7.8, 7.95);
  show(seed); seed.position.set(0, lerp(0.72, 0, sink), 0);
  seed.scale.setScalar(0.55 * grow * (1 + beat * 0.25) * (1 + sink * 0.4));
  seed.material.uniforms.opacity.value = (0.9 + beat * 0.8) * grow * lerp(fadeForQuestion, 1.4, sink) * (1 - absorb);
  seed.material.uniforms.core.value = 7 + beat * 5;

  // faint waves appear behind the question
  const wa = smooth(seg(t, 4.6, 6.0)) * (1 - smooth(seg(t, 7.3, 7.9)));
  waves.forEach((rb, i) => {
    if (wa <= 0) return;
    show(rb.mesh);
    const y = -0.2 + (i - 1) * 0.55, zz = -2.5 - i * 1.2, pts = [];
    for (let j = 0; j < 220; j++) { const x = -5 + j * 10 / 219; pts.push([x, y + sleepWave(x, t + i * 0.7, 0.18 + i * 0.05, i * 1.9), zz]); }
    rb.set(pts); rb.mat.uniforms.opacity.value = wa * (0.3 - i * 0.07); rb.mat.uniforms.progress.value = 1;
  });

  // typography
  const q1a = 1 - smooth(seg(t, 3.9, 4.7)) * 0.66;   // the first line recedes
  const recede = eInOut3(seg(t, 3.9, 4.9));
  const collapse = eInExpo(seg(t, 7.2, 7.9));
  const squash = 1 - collapse * 0.99;
  T.g.save();
  if (t < 7.95) {
    // everything folds toward the frame's centre line on the beat
    T.g.translate(540, 960); T.g.scale(1 + collapse * 0.08, squash); T.g.translate(-540, -960);
    // SCENE 01: YOU SLEEP / EVERY NIGHT.
    const s1 = lerp(1, 0.6, recede) * (1 + beat * 0.006);
    const cy = lerp(1060, 470, recede);
    T.g.save();
    T.g.translate(540, cy); T.g.scale(s1, s1); T.g.translate(-540, -cy);
    T.g.filter = recede > 0.02 ? `blur(${(recede * 3.5).toFixed(1)}px)` : 'none';
    const size1 = Math.min(T.fit('EVERY NIGHT.', 108, 800, T.HEAD, 5), T.fit('YOU SLEEP', 108, 800, T.HEAD, 5));
    const o1 = { size: size1, weight: 800, ls: 5, style: 'blur', by: 'word', stagger: 0.26, dur: 1.1, alpha: q1a * (1 - collapse) };
    T.line('YOU SLEEP', 540, cy - size1 * 0.12, t, 1.15, o1);
    T.line('EVERY NIGHT.', 540, cy + size1 * 1.0, t, 1.67, o1);
    T.g.restore();
    // SCENE 02: BUT HOW WELL DO YOU / REALLY / SLEEP?
    const a2 = 1 - collapse * 0.5;
    const sA = T.fit('BUT HOW WELL DO YOU', 68, 800, T.HEAD, 3);
    T.line('BUT HOW WELL DO YOU', 540, 850, t, 4.05, { size: sA, weight: 800, ls: 3, style: 'rise', stagger: 0.022, dur: 0.7, alpha: a2 * 0.94 });
    const emph = smooth(seg(t, 5.0, 5.6));
    const glowPulse = Math.exp(-Math.pow((t - 5.35) / 0.35, 2));
    T.line('REALLY', 540, 1062, t, 4.5, {
      size: 206, weight: 900, ls: 4, style: 'track', stagger: 0.035, dur: 0.9, alpha: a2,
      color: css(mix(PAL.moon, PAL.lilac, emph)), glow: 0.16 + 0.3 * glowPulse * emph
    });
    T.line('SLEEP?', 540, 1222, t, 4.9, { size: 116, weight: 900, ls: 4, style: 'rise', stagger: 0.03, dur: 0.7, alpha: a2 });
    // REALLY: a sleep wave draws itself under the word, like a pen stroke
    if (t > 5.25) {
      const w = T.measure('REALLY', 206, 900, T.HEAD, 4), x0 = 540 - w / 2 + 8, x1 = 540 + w / 2 - 12;
      const k = eInOut3(seg(t, 5.25, 6.05));
      T.g.globalAlpha = (1 - collapse) * 0.95;
      T.g.strokeStyle = css(PAL.lilac); T.g.lineWidth = 9; T.g.lineCap = 'round'; T.g.lineJoin = 'round';
      T.g.shadowColor = css(PAL.lilac, 0.95); T.g.shadowBlur = 26;
      T.g.beginPath();
      const N = 90;
      for (let j = 0; j <= N * k; j++) {
        const u = j / N, x = x0 + (x1 - x0) * u;
        const y = 1100 + Math.sin(u * Math.PI * 4 - t * 2.2) * 9 * Math.sin(u * Math.PI);
        j ? T.g.lineTo(x, y) : T.g.moveTo(x, y);
      }
      T.g.stroke(); T.g.shadowBlur = 0;
    }
  }
  T.g.restore();
  // the collapse leaves one bright line across the frame
  if (t > 7.55) {
    show(line.mesh);
    const k = eOutExpo(seg(t, 7.6, 8.05));
    const zLine = 0, half = 0.4 + 5 * k;
    const pts = []; for (let j = 0; j < 300; j++) { const x = -half + j * 2 * half / 299; pts.push([x, 0, zLine]); }
    line.set(pts); line.mat.uniforms.opacity.value = 1.2; line.mat.uniforms.progress.value = 1; line.mat.uniforms.width.value = 0.022;
    grade.flash = 0.05 * Math.exp(-Math.pow((t - 7.88) / 0.07, 2));
  }
}
const mix = (a, b, k) => [lerp(a[0], b[0], k), lerp(a[1], b[1], k), lerp(a[2], b[2], k)];

// SCENE 03 — the wave, the moon, Zoon (0:08 – 0:13)
cue(9.2, 'whoosh', { gain: 0.5, pan: 0.4 }); cue(10.2, 'swell', { dur: 0.8 }); cue(11.0, 'impact'); cue(11.0, 'shimmer');
cue(11.75, 'tick', { gain: 0.4 }); cue(12.3, 'tick', { gain: 0.35 });
const MOON_C = [4.4, 0.35, 0];
function sIntro(t) {
  bgMat.uniforms.intensity.value = 0.9;
  bgMat.uniforms.glowAmt.value = 0.35 + 0.2 * smooth(seg(t, 10.4, 11.4));
  bgMat.uniforms.glowPos.value.set(0.5, lerp(0.5, 0.62, smooth(seg(t, 9.6, 11.2))));
  show(stars.points); stars.mat.uniforms.opacity.value = 0.55;
  show(dust.points); dust.mat.uniforms.opacity.value = 0.9 * smooth(seg(t, 8.2, 9.4)); dust.mat.uniforms.morph.value = seg(t, 0, 16);
  // the light that sank into the line is its head now: it runs right, and
  // the camera follows it, then settles on the moon
  const run = eInOut3(seg(t, 7.85, 10.1));
  const head = lerp(0, MOON_C[0] + 1.3, run);
  const settle = eInOut5(seg(t, 9.7, 11.2));
  const follow = smooth(seg(t, 7.95, 8.9));
  const camX = lerp(lerp(0, head - 0.75, follow), MOON_C[0], settle);
  const camY = lerp(vnoise(t * 0.3) * 0.02 * (1 - follow), MOON_C[1] - 0.55, settle);
  const camZ = lerp(7.4, 8.6, eInOut3(seg(t, 8.0, 11.2))) + 0.5 * eInOut3(seg(t, 11.0, 13.6));
  lookFrom([camX, camY, camZ], [camX, camY, 0], 0.035 * Math.sin(seg(t, 8.2, 10.4) * Math.PI));
  // wave -> circle
  const curl = eInOut3(seg(t, 9.55, 10.75));
  const amp = smooth(seg(t, 8.0, 8.9)) * 0.42;
  show(line.mesh);
  const N = 400, pts = [];
  const R = 1.08;
  for (let j = 0; j < N; j++) {
    const u = j / (N - 1);
    const x = lerp(-6, head, u);
    const wy = sleepWave(x * 1.1, t * 1.6, amp * smooth(seg(u, 0.05, 0.3)) * (1 - smooth(seg(u, 0.93, 1))));
    // the circle: the head's end wraps around the moon's centre
    const ang = Math.PI * 0.5 - u * Math.PI * 2 * 1.0;
    const cx = MOON_C[0] + Math.cos(ang) * R, cy = MOON_C[1] + Math.sin(ang) * R;
    const kk = clamp(curl * 1.6 - (1 - u) * 0.6);
    const e = smoother(clamp(kk));
    pts.push([lerp(x, cx, e), lerp(wy, cy, e), 0]);
  }
  line.set(pts);
  line.mat.uniforms.progress.value = 1;
  line.mat.uniforms.start.value = curl > 0.6 ? lerp(-0.01, 0.999, eIn3(seg(curl, 0.6, 1.0))) : -1;
  line.mat.uniforms.opacity.value = 1.25 * (1 - smooth(seg(t, 10.7, 11.15)));
  line.mat.uniforms.head.value = 0.8; line.mat.uniforms.width.value = lerp(0.024, 0.03, curl);
  // what is left of the collapsed line to the right of the head dissolves
  if (t < 8.4) {
    show(lineRest.mesh);
    const rp = []; for (let j = 0; j < 60; j++) rp.push([lerp(head, 5.6, j / 59), 0, 0]);
    lineRest.set(rp);
    lineRest.mat.uniforms.opacity.value = 1.2 * (1 - smooth(seg(t, 7.95, 8.4)));
  }
  show(lineHead); lineHead.position.set(...pts[N - 1]); lineHead.scale.setScalar(0.62 + curl * 0.25);
  lineHead.material.uniforms.opacity.value = (1.1 + curl * 0.6) * (1 - smooth(seg(t, 10.6, 11.1)));
  lineHead.material.uniforms.core.value = 4;
  // the ring and the moon inside it
  const ringIn = smooth(seg(t, 10.2, 10.8)) * (1 - smooth(seg(t, 11.0, 11.8)));
  if (ringIn > 0) {
    show(moonRing); moonRing.position.set(MOON_C[0], MOON_C[1], 0.001); moonRing.scale.setScalar(2 * R * 1.04);
    moonRing.material.uniforms.opacity.value = ringIn * 1.1; moonRing.material.uniforms.progress.value = 1;
    moonRing.material.uniforms.glowAmt.value = 0.25;
  }
  const mIn = smooth(seg(t, 10.45, 11.25));
  if (mIn > 0) {
    show(moon); moon.position.set(...MOON_C); moon.scale.setScalar(R * lerp(0.94, 1, mIn));
    moon.rotation.set(0.05, -0.25 + t * 0.012, 0.02);
    moonMat.uniforms.opacity.value = mIn;
    moonMat.uniforms.sun.value.set(0.55, 0.2, 0.9).normalize();
    halo.material.uniforms.opacity.value = 0.24 * mIn * (1 + 1.2 * Math.exp(-Math.pow((t - 11.0) / 0.25, 2)));
    halo2.material.uniforms.opacity.value = 0.16 * mIn;
  }
  grade.flash = 0.06 * Math.exp(-Math.pow((t - 11.0) / 0.07, 2));
  bloomCfg.threshold = 0.8;
  // ZOON
  const yLogo = 1470;
  const tr = eOut5(seg(t, 11.0, 12.2));
  T.line('ZOON', 540, yLogo, t, 11.0, { size: 150, weight: 800, ls: lerp(60, 26, tr), style: 'blur', stagger: 0.07, dur: 1.0, glow: 0.25, out: 13.1, outDur: 0.5 });
  T.line('Understand your sleep.', 540, yLogo + 128, t, 11.7, { size: 56, weight: 700, ls: 0.5, style: 'rise', stagger: 0.012, dur: 0.7, out: 13.2 });
  T.line('Improve your nights.', 540, yLogo + 204, t, 12.25, { size: 46, weight: 600, fam: T.BODY, ls: 0.5, style: 'fade', by: 'word', stagger: 0.08, alpha: 0.72, out: 13.25 });
}

// ================================================================ screens
// The app's own captures (demo mode, badged "Sample data" by the app).
const SCR = {};
for (const n of ['sleep', 'today-morning', 'today-night', 'today-day', 'today', 'sleepDetail', 'sleepDetail-heart', 'trends', 'nightHistory',
  'report', 'patterns', 'coach', 'coach-ask-tired', 'coach-ask-night', 'coach-ask-tonight', 'windDown', 'soundscapes', 'breathing',
  'snoreCheck', 'nap', 'bodyClock', 'tomorrow', 'splash', 'more', 'today-breakdown']) SCR[n] = tex(`/Tools/launch-video/screens/${n}.webp`);
const phone = new Phone();
scene.add(phone.group);
// The screen with nothing on it yet: a sliver of the capture's own ground at
// its left edge, stretched across and softened.
function ground(map, k = 1) {
  const s = phone.setScreen(map, { blur: 0.9, bright: k });
  s.material.uniforms.uvRect.value.set(6 / CAP_W, 0, 18 / CAP_W, 1);
  return s;
}
// A backlight for the phone: a light behind it, where the moon is.
const backLight = new THREE.PointLight(new THREE.Color().setRGB(0.55, 0.6, 1.0), 0, 30, 1.2);
scene.add(backLight);
// A rim from behind and above, for the metal's edges.
const rimLight = new THREE.DirectionalLight(new THREE.Color().setRGB(0.7, 0.75, 1.0), 0);
rimLight.position.set(-0.6, 0.9, -1.0); scene.add(rimLight); scene.add(rimLight.target);

// A point `back` units behind `p` along the camera's line of sight, raised
// by `up`: somewhere a backlight stays put however the camera moves.
function backlightSpot(p, back, up) {
  const d = new THREE.Vector3(p[0], p[1], p[2]).sub(camera.position).normalize();
  const u = new THREE.Vector3(0, 1, 0).applyQuaternion(camera.quaternion);
  return [p[0] + d.x * back + u.x * up, p[1] + d.y * back + u.y * up, p[2] + d.z * back + u.z * up];
}

// SCENE 04 — the moon becomes a backlight; the night assembles (0:13 – 0:18)
mark(13, 'build');
const PC = [4.4, -0.3, 1.1];                       // where the phone stands
const SLEEP_LAYERS = [
  // crop [x, y, w, h] in capture pixels, when it lands, where it comes from
  { crop: [0, 0, 1206, 150], t: 14.30, from: { y: 0.1, z: 0.1, blur: 0.3 } },                       // status bar
  { crop: [0, 168, 1206, 162], t: 14.42, from: { y: 0.25, z: 0.25, rx: -0.3 } },                     // header
  { crop: [90, 336, 1026, 404], t: 14.62, from: { z: 0.55, s: 0.82, blur: 0.8 } },                   // last night, 7h 32m, 78 · Good
  { crop: [170, 752, 866, 108], t: 14.86, from: { x: -0.3, z: 0.3, ry: 0.5 } },                     // in bed -> up
  { crop: [380, 878, 446, 164], t: 15.02, from: { x: 0.3, z: 0.3, ry: -0.5 } },                     // date, sample data
  { crop: [0, 1128, 1206, 96], t: 15.20, from: { y: -0.15, z: 0.3 } },                               // chart header
  { crop: [24, 1282, 1166, 640], t: 15.36, from: { z: 0.4, rx: 0.35, blur: 0.4 }, wipe: [15.36, 16.25] }, // the hypnogram
  { crop: [0, 1964, 1206, 108], t: 15.92, from: { y: -0.25, z: 0.3, rx: 0.3 } },                     // chips
  { crop: [0, 2118, 1206, 190], t: 16.06, from: { y: -0.25, z: 0.25 } },                             // read / awakenings
  { crop: [70, 2304, 1066, 210], t: 16.22, from: { y: -0.22, z: 0.35, s: 0.9 }, radiusPx: 105 }               // tab bar
];
for (const L of SLEEP_LAYERS) cue(L.t - 0.05, 'click', { gain: 0.35, pan: (L.crop[0] + L.crop[2] / 2) / CAP_W - 0.5 });
cue(13.0, 'riser', { dur: 1.2 }); cue(14.25, 'boom', { gain: 0.7 }); cue(15.36, 'data', { dur: 0.9, gain: 0.45 }); cue(16.5, 'glass', { gain: 0.5 });
// The camera through scene 04, as a function so the next scene can start
// exactly where this one leaves off.
function camNight(t) {
  const aim = track(t, [[13.0, [MOON_C[0], -0.2, 0]], [14.5, [PC[0], PC[1] + 0.2, PC[2]]], [18.6, [PC[0], PC[1] + 0.2, PC[2]]]]);
  const orbit = track(t, [[13.0, 0], [14.7, -0.3], [18.6, 0.2]]);
  const dist = track(t, [[13.0, 9.07], [14.6, 5.75], [18.6, 5.35]]);
  const lift = track(t, [[13.0, 0], [14.6, 0.32], [18.6, 0.22]]);
  return { pos: [aim[0] + Math.sin(orbit) * dist, aim[1] + lift, aim[2] + Math.cos(orbit) * dist], aim };
}
function posePhoneNight(t) {
  const rise = eOut5(seg(t, 13.45, 14.75));
  phone.group.position.set(PC[0], lerp(PC[1] - 4.4, PC[1], rise), PC[2]);
  phone.group.rotation.set(lerp(0.5, 0.05, rise), lerp(-1.0, -0.08, rise) + 0.1 * eInOut3(seg(t, 14.75, 18.6)), lerp(0.12, 0, rise));
}
function sNight(t) {
  // the camera leaves the moon and comes round to the phone, never stopping
  const cam = camNight(t);
  lookFrom(cam.pos, cam.aim, 0);
  bgMat.uniforms.intensity.value = lerp(0.9, 0.62, smooth(seg(t, 13.0, 14.6)));
  bgMat.uniforms.glowAmt.value = lerp(0.55, 0.3, smooth(seg(t, 13.0, 14.6)));
  bgMat.uniforms.glowPos.value.set(0.5, 0.7);
  show(stars.points); stars.mat.uniforms.opacity.value = 0.55;
  show(dust.points); dust.mat.uniforms.opacity.value = 0.9; dust.mat.uniforms.morph.value = seg(t, 0, 16);
  // the moon moves back, up and out of focus: a backlight
  show(moon);
  const mb = eInOut3(seg(t, 13.1, 14.7));
  // held behind the phone's upper half from wherever the camera is, like an eclipse
  const behind = backlightSpot(PC, 6.2, 1.05);
  moon.position.set(lerp(MOON_C[0], behind[0], mb), lerp(MOON_C[1], behind[1], mb), lerp(0, behind[2], mb));
  moon.scale.setScalar(lerp(1.08, 1.32, mb));
  moon.rotation.set(0.05, -0.25 + t * 0.012, 0.02);
  moonMat.uniforms.opacity.value = 1; moonMat.uniforms.lit.value = lerp(1.35, 0.72, mb); moonMat.uniforms.blur.value = 0.55 * mb;
  moonMat.uniforms.sun.value.set(0.55, 0.2, 0.9).normalize();
  halo.material.uniforms.opacity.value = lerp(0.24, 0.2, mb); halo2.material.uniforms.opacity.value = lerp(0.16, 0.12, mb);
  backLight.position.set(moon.position.x, moon.position.y, moon.position.z + 2.5); backLight.intensity = 10 * mb;
  rimLight.intensity = 2.2 * mb; rimLight.target.position.set(...PC);
  // the phone rises in front of it, and turns to face us
  posePhoneNight(t);
  phone.show(camera);
  // the screen wakes, and the night assembles, layer by layer
  const wake = smooth(seg(t, 14.05, 14.45));
  if (wake > 0) {
    ground(SCR.sleep, wake);
    for (const L of SLEEP_LAYERS) {
      const k = eOutExpo(seg(t, L.t, L.t + 0.62));
      if (k <= 0) continue;
      const m = phone.layer(SCR.sleep, L.crop, { radiusPx: L.radiusPx || 0 });
      if (L.wipe) { m.material.uniforms.revealMode.value = 1; m.material.uniforms.revealDir.value.set(1, 0); m.material.uniforms.revealSoft.value = 0.08;
        m.material.uniforms.reveal.value = lerp(-0.08, 1.08, eInOut3(seg(t, L.wipe[0], L.wipe[1]))); }
      pose(m, k, L.from);
    }
    // once every layer has landed, the capture itself takes over, pixel for pixel
    const full = smooth(seg(t, 16.5, 16.9));
    if (full > 0) phone.setScreen(SCR.sleep, { b: true, opacity: full });
  }
  // type
  T.line('Your night.', 540, 205, t, 15.15, { size: 92, weight: 800, ls: -0.5, style: 'rise', stagger: 0.025, out: 17.4, outDur: 0.4 });
  T.line('Explained.', 540, 308, t, 15.65, { size: 92, weight: 800, ls: -0.5, style: 'rise', stagger: 0.025, color: css(PAL.lilac), out: 17.45, outDur: 0.4 });
}

// SCENE 05 — one score (0:18 – 0:23)
// The night's Sleep Intelligence score as the app computes it: five
// components, each an arc sized by the weight it carried (LunarOrbit's
// geometry and colours). `v` is the component's own score, read from the
// app's legend (screens/today-breakdown).
const SI = { score: 78, band: 'Good', components: [
  { label: 'Duration', w: 0.40, v: 56, color: [0.424, 0.361, 0.906] },
  { label: 'Continuity', w: 0.30, v: 97, color: [1.0, 0.435, 0.78] },
  { label: 'Regularity', w: 0.20, v: 87, color: [0.0, 0.902, 0.463] },
  { label: 'Timing', w: 0.05, v: 100, color: [1.0, 0.6, 0.31] },
  { label: 'Stage Pattern', w: 0.05, v: 86, color: [0.70, 0.62, 0.96] }
] };
{ let c = 0; for (const k of SI.components) { k.start = c; k.end = c + Math.max(0, k.w - 0.008); c += k.w; } }
const ringGroup = reg(new THREE.Group());
const ringTrack = new Ribbon(200, { color: L([0.5, 0.52, 0.7]), width: 0.07 });
ringTrack.mat.uniforms.softness.value = 0.35; ringGroup.add(ringTrack.mesh);
const ringSegs = SI.components.map(k => {
  const rb = new Ribbon(160, { color: L(k.color).map(v => v * 1.25), color2: L(k.color).map(v => v * 1.6), width: 0.075 });
  rb.mat.uniforms.softness.value = 0.35; ringGroup.add(rb.mesh); return rb;
});
const ringGlow = glow(L([0.45, 0.4, 0.95]), 1.6); ringGroup.add(ringGlow);
// a point on the ring (or, once `unroll` > 0, on the line it unrolls into)
const RING_R = 1;
function ringPoint(f, unroll = 0, lineLen = 7.2) {
  const a = Math.PI / 2 - f * Math.PI * 2;
  const c = [Math.cos(a) * RING_R, Math.sin(a) * RING_R, 0];
  if (unroll <= 0) return c;
  // unroll: the ring opens at its top and lays itself along x
  const l = [(f - 0.5) * lineLen, 0, 0];
  const e = smoother(clamp(unroll * 1.25 - (1 - Math.abs(f - 0.5) * 2) * 0.25));
  return [lerp(c[0], l[0], e), lerp(c[1], l[1], e), lerp(c[2], l[2], e) + Math.sin(e * Math.PI) * 0.35 * (f - 0.5)];
}
function drawRing(progress, unroll = 0, lineLen = 7.2, alpha = 1) {
  show(ringGroup);
  const tp = []; for (let i = 0; i < 200; i++) tp.push(ringPoint(i / 199, unroll, lineLen));
  ringTrack.set(tp); ringTrack.mat.uniforms.opacity.value = 0.16 * alpha * (1 - unroll);
  SI.components.forEach((k, i) => {
    const rb = ringSegs[i], pts = [];
    for (let j = 0; j < 160; j++) pts.push(ringPoint(lerp(k.start, k.end, j / 159), unroll, lineLen));
    rb.set(pts);
    const p = clamp((progress - k.start) / Math.max(1e-3, k.end - k.start));
    rb.mat.uniforms.progress.value = p; rb.mat.uniforms.opacity.value = p > 0 ? alpha : 0;
    rb.mat.uniforms.head.value = p < 1 ? 1.2 : 0; rb.mat.uniforms.start.value = -1;
  });
  ringGlow.material.uniforms.opacity.value = 0.18 * alpha * (1 - unroll); ringGlow.scale.setScalar(3.4);
}

mark(18, 'score');
cue(18.0, 'whoosh', { gain: 0.6, pan: -0.2 }); cue(18.5, 'sweep', { dur: 1.2, gain: 0.5 }); cue(19.0, 'glass', { gain: 0.6 });
SI.components.forEach((k, i) => cue(19.55 + i * 0.25, 'pop', { gain: 0.45, pan: Math.sin((k.start + k.end) * Math.PI) * 0.7 }));
cue(20.5, 'tick', { gain: 0.4 }); cue(21.0, 'tick', { gain: 0.4 }); cue(22.6, 'rev', { dur: 0.5, gain: 0.6 });
const RING_AT = [PC[0], PC[1] + 0.62, PC[2] + 1.35];
const ringRotScore = (t, lift = 1) => [lerp(-0.05, 0.28, lift) + 0.05 * Math.sin(t * 0.7), lerp(0.1, -0.22, lift) + 0.04 * Math.sin(t * 0.5), 0];
function camScore(t) {
  const n = camNight(18.0);
  // from the phone's hero line toward a ring that lifts off the glass
  const aim = track(t, [[18.0, n.aim], [19.2, RING_AT], [23.0, [RING_AT[0] + 0.05, RING_AT[1], RING_AT[2] + 0.2]]]);
  const pos = track(t, [[18.0, n.pos], [19.2, [PC[0] + 0.55, PC[1] + 0.95, PC[2] + 6.35]], [23.0, [PC[0] - 0.35, PC[1] + 0.8, PC[2] + 6.05]]]);
  return { pos, aim };
}
function sScore(t) {
  const cam = camScore(t);
  lookFrom(cam.pos, cam.aim, lerp(0, -0.03, smooth(seg(t, 19, 23))));
  bgMat.uniforms.intensity.value = 0.62; bgMat.uniforms.glowAmt.value = 0.3; bgMat.uniforms.glowPos.value.set(0.5, 0.6);
  show(stars.points); stars.mat.uniforms.opacity.value = 0.55;
  show(dust.points); dust.mat.uniforms.opacity.value = 0.9; dust.mat.uniforms.morph.value = seg(t, 0, 16);
  // the phone and its moon stay behind, and fall away
  const away = eInOut3(seg(t, 18.3, 19.6));
  show(moon);
  const behind = backlightSpot(PC, 6.2, 1.05), behindRing = backlightSpot(RING_AT, 6.0, 0.0), mr = smooth(seg(t, 18.4, 19.6));
  moon.position.set(lerp(behind[0], behindRing[0], mr), lerp(behind[1], behindRing[1], mr), lerp(behind[2], behindRing[2], mr)); moon.scale.setScalar(lerp(1.32, 1.02, mr)); moon.rotation.set(0.05, -0.25 + t * 0.012, 0.02);
  moonMat.uniforms.lit.value = lerp(0.72, 0.5, away); moonMat.uniforms.blur.value = 0.55;
  halo.material.uniforms.opacity.value = 0.2; halo2.material.uniforms.opacity.value = 0.12;
  rimLight.intensity = 2.2; rimLight.target.position.set(...PC);
  posePhoneNight(18.0);
  const drop = eInOut3(seg(t, 18.45, 19.55));
  phone.group.position.y -= 3.6 * drop; phone.group.position.z -= 1.2 * drop;
  phone.group.rotation.x += 0.55 * drop;
  if (t < 19.6) {
    phone.show(camera);
    phone.setScreen(SCR.sleep, { bright: lerp(1, 0.55, away) });
  }
  // the ring lifts off the screen where "78 · Good" is, and draws itself
  const lift = eOut5(seg(t, 18.35, 19.4));
  const from = new THREE.Vector3(capX(603), capY(706), FRONT + 0.01);
  phone.group.updateMatrixWorld(); from.applyMatrix4(phone.group.matrixWorld);
  const to = new THREE.Vector3(...RING_AT);
  ringGroup.position.copy(from.clone().lerp(to, lift));
  ringGroup.scale.setScalar(lerp(0.06, 0.5, lift));
  ringGroup.rotation.set(...ringRotScore(t, lift));
  ringGroup.updateMatrixWorld();
  const drawn = eInOut3(seg(t, 18.6, 19.85));
  const out = seg(t, 22.4, 23.0);
  drawRing(drawn, 0, 7.2, 1);
  grade.bloom = 0.8;
  // the number in the middle counts up, in the app's light rounded numerals
  const rp = [ringGroup.position.x, ringGroup.position.y, ringGroup.position.z];
  const c = project(rp);
  const px = worldToScreenScale(rp) * ringGroup.scale.x;
  const n = Math.round(SI.score * eOut3(seg(t, 19.05, 20.1)));
  const na = smooth(seg(t, 19.0, 19.4)) * (1 - smooth(out));
  if (na > 0) {
    T.g.save(); T.g.globalAlpha = na; T.g.textAlign = 'center'; T.g.textBaseline = 'alphabetic';
    // as the app draws it: the number in the band's colour, the band in quiet caps
    T.font(px * 0.78, 300, T.HEAD, -px * 0.02); T.g.fillStyle = css([0.56, 0.5, 1.0]); T.g.shadowColor = css([0.45, 0.4, 1.0], 0.6); T.g.shadowBlur = px * 0.08;
    T.g.fillText(String(n), c.x, c.y + px * 0.26); T.g.shadowBlur = 0;
    T.font(px * 0.13, 700, T.BODY, px * 0.03); T.g.fillStyle = 'rgba(226,228,240,0.92)'; T.g.fillText(SI.band.toUpperCase(), c.x, c.y + px * 0.5);
    T.g.restore();
  }
  // the components, around the ring, each at the middle of its own arc
  SI.components.forEach((k, i) => {
    const ka = eOutBack(seg(t, 19.55 + i * 0.25, 19.95 + i * 0.25), 1.4);
    if (ka <= 0) return;
    // the two narrow arcs at the top would stack their chips; fan them apart
    const mid = k.label === 'Timing' ? 0.8 : k.label === 'Stage Pattern' ? 1.04 : (k.start + k.end) / 2, a = Math.PI / 2 - mid * Math.PI * 2;
    const rr = k.w < 0.1 ? 1.5 : 1.36;
    const w = new THREE.Vector3(Math.cos(a) * rr, Math.sin(a) * rr, 0).applyMatrix4(ringGroup.matrixWorld);
    const p = project([w.x, w.y, w.z]);
    const al = clamp(ka) * (1 - smooth(out));
    T.g.save(); T.g.translate(p.x, p.y); T.g.scale(lerp(0.6, 1, clamp(ka)), lerp(0.6, 1, clamp(ka))); T.g.translate(-p.x, -p.y);
    const cw = T.chipWidth(k.label, k.v != null ? String(k.v) : null, 34), cx = clamp(p.x, 36 + cw / 2, W - 36 - cw / 2);
    T.chip(cx, p.y, css(k.color), k.label, k.v != null ? String(k.v) : null, al, { size: 34, fill: 'rgba(20,22,42,0.78)', stroke: css(k.color, 0.5) });
    T.g.restore();
  });
  T.line('One score.', 540, 250, t, 20.5, { size: 96, weight: 800, ls: -0.5, style: 'rise', stagger: 0.025, out: 22.4, outDur: 0.35 });
  T.line('A complete picture.', 540, 350, t, 21.0, { size: 64, weight: 700, ls: 0, style: 'rise', stagger: 0.018, color: css(PAL.lilac), out: 22.45, outDur: 0.35 });
}

// SCENE 06 — the ring unrolls into the night (0:23 – 0:29)
// The night's stages exactly as the app draws them (AppMockData's pattern,
// 11:14 PM to 7:10 AM), in the app's four rows and colours.
const STAGE_ROW = { awake: 1.02, rem: 0.42, core: -0.18, deep: -0.78 };
const STAGE_Z = { awake: 0.22, rem: 0.075, core: -0.075, deep: -0.22 };
const STAGE_COL = { awake: PAL.awake, rem: PAL.rem, core: PAL.core, deep: PAL.deep };
const NIGHT0 = D.hypnogram[0].start, NIGHT1 = D.hypnogram.at(-1).end;
const TL_W = 2.62;                                          // the timeline's width, world units
const tlX = ms => (ms - NIGHT0) / (NIGHT1 - NIGHT0) * TL_W - TL_W / 2;
const hyp = reg(new THREE.Group());
const bars = D.hypnogram.map(sg => {
  const m = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), cardMaterial());
  const u = m.material.uniforms; u.color.value.set(...L(STAGE_COL[sg.stage]).map(v => v * 1.15)); u.grad.value = 0.3;
  u.rim.value = 0.25; u.rimColor.value.set(...L(STAGE_COL[sg.stage]));
  hyp.add(m); m.userData.sg = sg; return m;
});
// the thin rules that join one stage to the next, as in the app
const joins = D.hypnogram.slice(1).map(() => { const rb = new Ribbon(2, { color: L([0.55, 0.57, 0.72]), width: 0.012 }); hyp.add(rb.mesh); return rb; });
const playhead = new Ribbon(2, { color: L([0.85, 0.87, 1.0]), width: 0.018 }); hyp.add(playhead.mesh);
const playGlow = glow(L([0.7, 0.75, 1.0]), 2.2); hyp.add(playGlow);
const HYP_AT = [RING_AT[0] + 0.24, RING_AT[1] - 0.1, RING_AT[2]];
const BAR_H = 0.34;

mark(23, 'stages');
cue(23.0, 'sweep', { dur: 1.0, gain: 0.55 }); cue(24.2, 'data', { dur: 2.2, gain: 0.35 }); cue(24.25, 'glass', { gain: 0.45, pan: -0.6 });
const SWEEP = [24.2, 26.4];
const sweepAt = ms => lerp(SWEEP[0], SWEEP[1], (ms - NIGHT0) / (NIGHT1 - NIGHT0));
D.hypnogram.forEach(sg => { if (sg.stage === 'awake') cue(sweepAt(sg.start), 'tick', { gain: 0.5, pan: (sg.start - NIGHT0) / (NIGHT1 - NIGHT0) - 0.5 }); });
cue(26.45, 'boom', { gain: 0.5 }); cue(28.5, 'rev', { dur: 0.6, gain: 0.6 });
// Words the sweep leaves behind: the night's first deep sleep, first REM, the
// 2:54 AM wake-up the app reports (7 minutes), and the morning's Recovery.
const firstOf = st => D.hypnogram.find(sg => sg.stage === st);
const WORDS = [
  { sg: firstOf('deep'), text: 'DEEP', col: PAL.lilac, dy: -0.36 },
  { sg: firstOf('rem'), text: 'REM', col: PAL.rem, dy: 0.34 },
  { sg: firstOf('awake'), text: 'AWAKE · 7 MIN', col: PAL.awake, dy: 0.4 },
];
function camStages(t) {
  const s = camScore(23.0);
  const C = [HYP_AT[0] - 0.24, HYP_AT[1] + 0.12, HYP_AT[2]];
  const orbit = track(t, [[24.2, -0.12], [26.6, -0.03], [29.0, 0.0]]), dist = track(t, [[24.2, 10.4], [29.0, 10.2]]);
  const at = [C[0] + Math.sin(orbit) * dist, C[1] - 0.9 + 0.5 * seg(t, 24.2, 29), C[2] + Math.cos(orbit) * dist];
  const pos = track(t, [[23.0, s.pos], [24.2, at], [29.0, at]].map(([k, v], i) => i === 0 ? [k, v] : [k, at]));
  const aim = track(t, [[23.0, s.aim], [24.2, C], [29.0, [C[0] + 0.05, C[1], C[2]]]]);
  return { pos, aim };
}
function sStages(t) {
  const cam = camStages(t);
  lookFrom(cam.pos, cam.aim, lerp(-0.03, 0.02, smooth(seg(t, 23, 26))));
  bgMat.uniforms.intensity.value = 0.62; bgMat.uniforms.glowAmt.value = 0.3; bgMat.uniforms.glowPos.value.set(0.5, 0.58);
  show(stars.points); stars.mat.uniforms.opacity.value = 0.55;
  show(dust.points); dust.mat.uniforms.opacity.value = 0.9; dust.mat.uniforms.morph.value = seg(t, 0, 16);
  // the moon that sat in the ring drifts away
  const mAway = smooth(seg(t, 23.0, 24.4));
  if (mAway < 1) {
    show(moon); const b = backlightSpot(RING_AT, 6.0, 0.0);
    moon.position.set(b[0], b[1] + mAway * 1.6, b[2]); moon.scale.setScalar(1.02); moon.rotation.set(0.05, -0.25 + t * 0.012, 0.02);
    moonMat.uniforms.lit.value = 0.5 * (1 - mAway); moonMat.uniforms.blur.value = 0.55; moonMat.uniforms.opacity.value = 1 - mAway;
    halo.material.uniforms.opacity.value = 0.2 * (1 - mAway); halo2.material.uniforms.opacity.value = 0.12 * (1 - mAway);
  }
  // the ring opens at the top and lays itself down as the night's time axis
  const unroll = eInOut3(seg(t, 23.0, 24.3));
  const axisY = STAGE_ROW.deep - BAR_H * 0.5 - 0.14;
  const r0 = ringRotScore(23.0);
  ringGroup.position.set(lerp(RING_AT[0], HYP_AT[0], unroll), lerp(RING_AT[1], HYP_AT[1] + axisY, unroll), lerp(RING_AT[2], HYP_AT[2], unroll));
  ringGroup.rotation.set(lerp(r0[0], 0, unroll), lerp(r0[1], 0, unroll), 0);
  ringGroup.scale.setScalar(lerp(0.5, 1.0, unroll));
  ringGroup.updateMatrixWorld();
  if (t < 24.9) drawRing(1, unroll, TL_W, 1 - smooth(seg(t, 24.3, 24.9)));
  // bars rise out of the axis as the playhead passes them
  show(hyp); hyp.position.set(...HYP_AT); hyp.rotation.set(0, 0, 0);
  const dissolve = smooth(seg(t, 28.55, 29.0));
  bars.forEach((m, i) => {
    const sg = m.userData.sg, x0 = tlX(sg.start), x1 = tlX(sg.end), tb = sweepAt(sg.start);
    const k = eOutBack(seg(t, tb, tb + 0.42), 1.2), kc = clamp(k);
    m.visible = kc > 0.001;
    if (!m.visible) return;
    const w = Math.max(0.04, x1 - x0 - 0.012), h = sg.stage === 'awake' ? 0.42 : BAR_H;
    const y = lerp(axisY, STAGE_ROW[sg.stage], k);
    m.position.set((x0 + x1) / 2, y, STAGE_Z[sg.stage] * kc);
    setCardSize(m, w, h * lerp(0.15, 1, kc));
    const u = m.material.uniforms; u.radius.value = Math.min(0.07, w * 0.4); u.opacity.value = kc * (1 - dissolve);
  });
  joins.forEach((rb, i) => {
    const a = bars[i].userData.sg, b = bars[i + 1].userData.sg, x = tlX(b.start), tb = sweepAt(b.start);
    const k = smooth(seg(t, tb + 0.15, tb + 0.45));
    rb.mesh.visible = k > 0;
    rb.set([[x - 0.006, STAGE_ROW[a.stage], STAGE_Z[a.stage]], [x - 0.006, STAGE_ROW[b.stage], STAGE_Z[b.stage]]]);
    rb.mat.uniforms.opacity.value = 0.38 * k * (1 - dissolve);
  });
  const ph = seg(t, SWEEP[0], SWEEP[1]), phA = smooth(seg(t, SWEEP[0] - 0.1, SWEEP[0] + 0.1)) * (1 - smooth(seg(t, SWEEP[1], SWEEP[1] + 0.3)));
  const phx = lerp(-TL_W / 2, TL_W / 2, ph);
  playhead.mesh.visible = phA > 0; playGlow.visible = phA > 0;
  playhead.set([[phx, axisY, 0.4], [phx, STAGE_ROW.awake + 0.42, 0.4]]); playhead.mat.uniforms.opacity.value = 1.1 * phA; playhead.mat.uniforms.width.value = 0.022;
  playGlow.position.set(phx, axisY, 0.41); playGlow.scale.setScalar(0.8); playGlow.material.uniforms.opacity.value = 0.9 * phA;
  grade.bloom = 0.75;
  // labels: rows at the left, times beneath, in the app's own words
  const la = smooth(seg(t, 24.4, 25.0)) * (1 - dissolve);
  const hw = (x, y, z) => { const v = new THREE.Vector3(x, y, z).add(hyp.position); return project([v.x, v.y, v.z]); };
  if (la > 0) {
    [['awake', 'Awake', PAL.awake], ['rem', 'REM', PAL.rem], ['core', 'Light sleep', PAL.core], ['deep', 'Deep', PAL.lilac]].forEach(([st, name, col], i) => {
      const p = hw(-TL_W / 2 - 0.08, STAGE_ROW[st], STAGE_Z[st]);
      T.g.save(); T.g.globalAlpha = la * clamp(seg(t, 24.4 + i * 0.08, 24.8 + i * 0.08) * 1.5); T.font(30, 700, T.BODY, 0.2); T.g.fillStyle = css(col); T.g.textAlign = 'right'; T.g.textBaseline = 'middle';
      T.g.fillText(name, p.x, p.y); T.g.restore();
    });
    [[NIGHT0, '11:14 PM'], [(NIGHT0 + NIGHT1) / 2, '3:12 AM'], [NIGHT1, '7:10 AM']].forEach(([ms, s], i) => {
      const p = hw(tlX(ms), axisY - 0.12, 0);
      T.g.save(); T.g.globalAlpha = la * 0.85; T.font(30, 600, T.BODY, 0.2); T.g.fillStyle = 'rgba(214,216,232,0.9)'; T.g.textAlign = i === 0 ? 'left' : i === 2 ? 'right' : 'center'; T.g.textBaseline = 'top';
      T.g.fillText(s, p.x, p.y); T.g.restore();
    });
  }
  // the words the sweep leaves behind
  WORDS.forEach(wd => {
    const tb = sweepAt(wd.sg.start) + 0.12;
    const ka = eOutBack(seg(t, tb, tb + 0.45), 1.6), a = clamp(ka) * (1 - smooth(seg(t, 27.9, 28.4)));
    if (a <= 0) return;
    const x = (tlX(wd.sg.start) + tlX(wd.sg.end)) / 2, p = hw(x, STAGE_ROW[wd.sg.stage] + wd.dy, STAGE_Z[wd.sg.stage]);
    T.g.save(); T.g.globalAlpha = a; T.g.translate(p.x, p.y); T.g.scale(lerp(0.7, 1, clamp(ka)), lerp(0.7, 1, clamp(ka)));
    T.font(38, 800, T.BODY, 5); T.g.textAlign = 'center'; T.g.textBaseline = 'middle'; T.g.fillStyle = css(wd.col);
    T.g.shadowColor = css(wd.col, 0.7); T.g.shadowBlur = 18; T.g.fillText(wd.text, 0, 0); T.g.restore();
  });
  // and at the wake, what the night left the body with
  const ra = eOutBack(seg(t, 26.5, 26.95), 1.5), rA = clamp(ra) * (1 - smooth(seg(t, 27.9, 28.4)));
  if (rA > 0) {
    const p = hw(-0.1, STAGE_ROW.deep - 0.78, 0.0);
    T.g.save(); T.g.translate(p.x, p.y); T.g.scale(lerp(0.7, 1, clamp(ra)), lerp(0.7, 1, clamp(ra))); T.g.translate(-p.x, -p.y);
    T.chip(p.x, p.y, css([0.0, 0.902, 0.463]), 'Morning Recovery', '65', rA, { size: 34, fill: 'rgba(16,30,28,0.82)', stroke: 'rgba(0,230,118,0.45)' });
    T.g.restore();
  }
  T.line('See what happened', 540, 250, t, 24.75, { size: 86, weight: 800, ls: -0.5, style: 'rise', stagger: 0.02, out: 28.3, outDur: 0.35 });
  T.line('while you slept.', 540, 350, t, 25.2, { size: 86, weight: 800, ls: -0.5, style: 'rise', stagger: 0.02, color: css(PAL.lilac), out: 28.35, outDur: 0.35 });
}

// SCENE 07 — patterns (0:29 – 0:34)
// The night's bars break into particles, and the particles become the last
// 30 nights: when each night began, and how long it lasted, with the weekly
// average the app's Weekly Report shows (7h 12m). The particles land, and
// the charts resolve into solid shapes.
const CH = { x0: -1.3, x1: 1.3, bedTop: 1.08, bedBot: 0.36, durBase: -1.62, durMax: -0.34 };
const HIST = D.history;
const nightX = i => lerp(CH.x0, CH.x1, i / (HIST.length - 1));
// bedtimes between 9:30 PM (bottom) and 12:30 AM (top): later nights sit higher
const bedY = d => lerp(CH.bedBot, CH.bedTop, clamp((D.eveningMinutes(d) - 210) / 180));
const durY = min => lerp(CH.durBase, CH.durMax, min / 540);
const WEEK = HIST.slice(-7);
const WEEK_AVG = WEEK.reduce((s, n) => s + n.asleep, 0) / 7;
const WEEK_BED = WEEK.map(n => D.eveningMinutes(n.bedtime));
const BED_SPREAD = Math.max(...WEEK_BED) - Math.min(...WEEK_BED);        // 1h 51m for the demo week
const BAR_W = 0.058;
const dots = new Cloud(1100, 77);
{
  const r = rng(29);
  // where every particle starts: somewhere on one of the night's bars (scene 06's last pose)
  const src = D.hypnogram.map(sg => ({ x0: tlX(sg.start), x1: tlX(sg.end), y: STAGE_ROW[sg.stage], z: STAGE_Z[sg.stage], h: sg.stage === 'awake' ? 0.42 : BAR_H }));
  const areas = src.map(s => (s.x1 - s.x0) * s.h), total = areas.reduce((a, b) => a + b, 0);
  const pick = () => { let u = r() * total; for (let i = 0; i < src.length; i++) { u -= areas[i]; if (u <= 0) return src[i]; } return src.at(-1); };
  dots.layout('a', () => { const s = pick(); return [HYP_AT[0] + lerp(s.x0, s.x1, r()), HYP_AT[1] + s.y + (r() - 0.5) * s.h, HYP_AT[2] + s.z]; });
  // where every particle lands: inside a duration bar, or on a bedtime dot
  const C1 = [HYP_AT[0] - 0.24, HYP_AT[1] + 0.12, HYP_AT[2]];
  const tg = [], cols = [];
  HIST.forEach((n, i) => {
    const last = i === HIST.length - 1, top = durY(n.asleep), k = Math.round((top - CH.durBase) / 0.05);
    for (let j = 0; j < k; j++) { tg.push([nightX(i) + (r() - 0.5) * BAR_W * 0.7, lerp(CH.durBase + 0.02, top - 0.02, (j + r()) / k), (r() - 0.5) * 0.04]);
      cols.push(last ? [1.4, 1.35, 1.5] : L(PAL.sleep).map(v => v * 1.6)); }
    const y = bedY(n.bedtime);
    for (let j = 0; j < 7; j++) { const a = r() * 6.283, rr = Math.sqrt(r()) * 0.03; tg.push([nightX(i) + Math.cos(a) * rr, y + Math.sin(a) * rr, 0]);
      cols.push(last ? [1.4, 1.35, 1.5] : L(PAL.lilac).map(v => v * 1.5)); }
  });
  dots.n = Math.min(dots.n, tg.length); dots.geo.setDrawRange(0, dots.n);
  dots.layout('b', i => [C1[0] + tg[i][0], C1[1] + tg[i][1], C1[2] + tg[i][2]]);
  dots.colors(i => cols[i]);
  dots.mat.uniforms.size.value = 0.1; dots.mat.uniforms.spread.value = 0.45; dots.mat.uniforms.swirl.value = 0.5; dots.mat.uniforms.sizeVar.value = 0.3;
  dots.C1 = C1;
}
dots.points.renderOrder = 30;
reg(dots.points);
// the solid charts the particles resolve into
const charts = reg(new THREE.Group());
const durBars = HIST.map((n, i) => {
  const m = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), cardMaterial()); const u = m.material.uniforms;
  const last = i === HIST.length - 1;
  u.color.value.set(...(last ? [1.1, 1.08, 1.2] : L(PAL.sleep).map(v => v * 1.25))); u.grad.value = 0.45;
  const h = durY(n.asleep) - CH.durBase; m.position.set(nightX(i), CH.durBase + h / 2, 0); setCardSize(m, BAR_W, h);
  u.radius.value = BAR_W * 0.5; charts.add(m); return m;
});
const bedDots = HIST.map((n, i) => { const g = glow(i === HIST.length - 1 ? [1.2, 1.2, 1.3] : L(PAL.lilac).map(v => v * 1.2), 3); g.material.uniforms.core.value = 3;
  g.position.set(nightX(i), bedY(n.bedtime), 0.01); g.scale.setScalar(0.14); charts.add(g); return g; });
const bedLine = new Ribbon(120, { color: L(PAL.lilac), width: 0.016 }); charts.add(bedLine.mesh);
{ const pts = []; for (let j = 0; j < 120; j++) { const f = j / 119 * (HIST.length - 1), i = Math.min(HIST.length - 2, Math.floor(f)), u = smooth(f - i);
    pts.push([lerp(nightX(i), nightX(i + 1), f - i), lerp(bedY(HIST[i].bedtime), bedY(HIST[i + 1].bedtime), u), 0]); } bedLine.set(pts); }
const avgLine = new Ribbon(2, { color: L([1.0, 0.8, 0.5]), width: 0.026 }); avgLine.mesh.renderOrder = 5; charts.add(avgLine.mesh);

mark(29, 'patterns');
cue(28.95, 'impact', { gain: 0.7 }); cue(29.0, 'data', { dur: 1.4, gain: 0.5 }); cue(30.55, 'glass', { gain: 0.5 }); cue(31.0, 'sweep', { dur: 0.6, gain: 0.4 });
cue(31.75, 'tick', { gain: 0.4 }); cue(33.5, 'whoosh', { gain: 0.6, pan: 0.3 });
function camPatterns(t) {
  if (t < 29.0) return camStages(t);
  const s = camStages(29.0), C = dots.C1;
  const orbit = track(t, [[29.0, 0.0], [34.0, -0.12]]), dist = track(t, [[29.0, 10.2], [34.0, 9.7]]);
  const at = [C[0] + Math.sin(orbit) * dist, C[1] - 0.25, C[2] + Math.cos(orbit) * dist];
  return { pos: track(t, [[29.0, s.pos], [30.6, at], [34.0, at]]), aim: track(t, [[29.0, s.aim], [30.6, [C[0], C[1] - 0.1, C[2]]], [34.0, [C[0], C[1] - 0.1, C[2]]]]) };
}
function sPatterns(t) {
  const cam = camPatterns(t);
  lookFrom(cam.pos, cam.aim, 0);
  bgMat.uniforms.intensity.value = 0.62; bgMat.uniforms.glowAmt.value = 0.3; bgMat.uniforms.glowPos.value.set(0.5, 0.55);
  show(stars.points); stars.mat.uniforms.opacity.value = 0.55;
  show(dust.points); dust.mat.uniforms.opacity.value = 0.9; dust.mat.uniforms.morph.value = seg(t, 0, 16);
  // particles fly, land, and hand over to the solid charts
  const land = smooth(seg(t, 30.45, 30.95)), gone = smooth(seg(t, 33.55, 33.95));
  show(dots.points);
  dots.mat.uniforms.time.value = t;
  dots.mat.uniforms.morph.value = eInOut3(seg(t, 29.0, 30.7));
  dots.mat.uniforms.opacity.value = smooth(seg(t, 28.85, 29.05)) * (1 - land * 0.85) * (1 - gone);
  show(charts); const C = dots.C1; charts.position.set(...C);
  durBars.forEach((m, i) => { m.material.uniforms.opacity.value = land * (1 - gone) * clamp(seg(t, 30.45 + i * 0.008, 30.8 + i * 0.008) * 1.2); });
  bedDots.forEach(g => { g.material.uniforms.opacity.value = land * (1 - gone); });
  bedLine.mat.uniforms.progress.value = eInOut3(seg(t, 30.6, 31.3)); bedLine.mat.uniforms.opacity.value = 0.55 * land * (1 - gone);
  const la = smooth(seg(t, 30.8, 31.2)) * (1 - gone);
  const xa = nightX(HIST.length - 7) - 0.05, xb = nightX(HIST.length - 1) + 0.05, yAvg = durY(WEEK_AVG);
  avgLine.set([[xa, yAvg, 0.05], [lerp(xa, xb, eInOut3(seg(t, 30.8, 31.35))), yAvg, 0.05]]); avgLine.mat.uniforms.opacity.value = 1.8 * la;
  grade.bloom = 0.75;
  // titles and the week's real numbers
  const P = (x, y) => project([C[0] + x, C[1] + y, C[2]]);
  const ta = smooth(seg(t, 30.5, 30.9)) * (1 - gone);
  if (ta > 0) {
    T.g.save(); T.g.globalAlpha = ta; T.g.textBaseline = 'alphabetic';
    let p = P(CH.x0, CH.bedTop + 0.22); T.font(32, 800, T.BODY, 3); T.g.textAlign = 'left'; T.g.fillStyle = css(PAL.lilac); T.g.fillText('BEDTIME · 30 NIGHTS', p.x, p.y);
    p = P(CH.x0, CH.durMax + 0.3); T.g.fillStyle = css([0.62, 0.62, 1.0]); T.g.fillText('TIME ASLEEP · 30 NIGHTS', p.x, p.y);
    T.g.globalAlpha = la; T.font(34, 700, T.BODY, 0.2); T.g.textAlign = 'right';
    p = P(CH.x1 + 0.03, CH.durMax + 0.12); T.g.fillStyle = 'rgba(255,212,150,1)'; T.g.fillText(`${D.fmtHM(WEEK_AVG)} weekly average`, p.x, p.y);
    p = P(CH.x1 + 0.03, CH.bedBot - 0.16); T.g.fillStyle = 'rgba(214,210,255,0.95)'; T.g.fillText(`Varied by ${D.fmtHM(BED_SPREAD)} this week`, p.x, p.y);
    T.g.restore();
  }
  T.line('Patterns become', 540, 250, t, 29.5, { size: 88, weight: 800, ls: -0.5, style: 'rise', stagger: 0.02, out: 31.4, outDur: 0.3 });
  T.line('insights.', 540, 350, t, 29.85, { size: 88, weight: 800, ls: -0.5, style: 'rise', stagger: 0.02, color: css(PAL.lilac), out: 31.45, outDur: 0.3 });
  T.line('Insights become', 540, 250, t, 31.75, { size: 88, weight: 800, ls: -0.5, style: 'rise', stagger: 0.02, out: 33.45, outDur: 0.3 });
  T.line('better decisions.', 540, 350, t, 32.1, { size: 88, weight: 800, ls: -0.5, style: 'rise', stagger: 0.02, color: css(PAL.lilac), out: 33.5, outDur: 0.3 });
}

// SCENE 08 — the app's own insights, as cards (0:34 – 0:39)
// Five cards cut from the real screens. Every number on them is the app's.
// The Weekly Averages card comes forward: its 7h 12m is the average the
// chart before it just drew.
const INSIGHT_CARDS = [
  { map: 'trends', crop: [236, 650, 734, 500], r: 0, at: [-0.42, 1.08, -0.7], rot: [0.05, 0.28, 0.03], w: 0.78, t: 33.7, from: [-1.6, 1.2, -5] },   // Sleep Health 80
  { map: 'report', crop: [50, 1066, 1106, 700], r: 60, at: [0.4, 0.5, -1.25], rot: [0.02, -0.3, -0.02], w: 1.02, t: 33.95, from: [1.8, 0.8, -6] },   // Highlights
  { map: 'report', crop: [50, 1808, 1106, 636], r: 60, at: [0.02, -0.22, 0.15], rot: [0.08, -0.14, 0], w: 1.1, t: 34.2, from: [0.2, -1.6, -5], hero: true }, // Weekly Averages
  { map: 'trends', crop: [48, 1570, 1110, 680], r: 60, at: [-0.45, -1.02, -0.95], rot: [-0.04, 0.3, 0.02], w: 0.98, t: 34.45, from: [-1.9, -1.2, -6] }, // Sleep resilience
  { map: 'patterns', crop: [48, 398, 1110, 1250], r: 60, at: [0.5, -1.3, -1.8], rot: [0, -0.36, 0], w: 0.92, t: 34.7, from: [1.9, -1.6, -7] }     // Things Zoon has noticed
].map(c => {
  const m = card(SCR[c.map], { crop: c.crop, imgW: CAP_W, imgH: CAP_H, width: c.w, radiusPx: c.r });
  m.material.uniforms.rim.value = 0.18; m.userData.w = c.w; m.userData.h = c.w * c.crop[3] / c.crop[2];
  reg(m); m.renderOrder = 12; return { ...c, m };
});
const C8 = [HYP_AT[0] - 0.24, HYP_AT[1] - 0.1, HYP_AT[2] - 0.4];
const tileGlows = [0, 1, 2, 3].map(() => { const g = glow(L([0.75, 0.72, 1.0]), 1.5); g.renderOrder = 13; return reg(g); });
mark(34, 'insights');
INSIGHT_CARDS.forEach((c, i) => cue(c.t + 0.35, 'glass', { gain: 0.35, pan: c.at[0] * 0.8 }));
cue(34.0, 'whoosh', { gain: 0.5, pan: -0.3 }); cue(36.35, 'swell', { dur: 0.7, gain: 0.5 }); cue(36.95, 'boom', { gain: 0.55 });
cue(37.4, 'pop', { gain: 0.35, pan: -0.4 }); cue(37.65, 'pop', { gain: 0.35, pan: 0.4 }); cue(37.9, 'pop', { gain: 0.35, pan: -0.4 }); cue(38.15, 'pop', { gain: 0.35, pan: 0.4 });
function camInsights(t) {
  if (t < 34.0) return camPatterns(t);
  const s = camPatterns(34.0);
  const focus = [C8[0], C8[1], C8[2]];
  const pos = track(t, [[34.0, s.pos], [35.6, [C8[0] + 0.22, C8[1] + 0.1, C8[2] + 6.3]], [36.4, [C8[0] + 0.12, C8[1] + 0.02, C8[2] + 5.6]], [39.0, [C8[0] - 0.08, C8[1] - 0.05, C8[2] + 4.9]]]);
  const aim = track(t, [[34.0, s.aim], [35.6, focus], [39.0, [C8[0], C8[1] - 0.02, C8[2]]]]);
  return { pos, aim };
}
function sInsights(t) {
  const cam = camInsights(t);
  lookFrom(cam.pos, cam.aim, 0.015 * Math.sin(seg(t, 34, 39) * Math.PI));
  bgMat.uniforms.intensity.value = 0.62; bgMat.uniforms.glowAmt.value = 0.32; bgMat.uniforms.glowPos.value.set(0.5, 0.55);
  show(stars.points); stars.mat.uniforms.opacity.value = 0.55;
  show(dust.points); dust.mat.uniforms.opacity.value = 0.9; dust.mat.uniforms.morph.value = seg(t, 0, 16);
  const hero = eInOut5(seg(t, 36.35, 37.1));
  INSIGHT_CARDS.forEach((c, i) => {
    const k = eOutExpo(seg(t, c.t, c.t + 1.1));
    if (k <= 0) return;
    const m = show(c.m), u = m.material.uniforms;
    const drift = [Math.sin(t * 0.6 + i) * 0.03, Math.cos(t * 0.5 + i * 1.7) * 0.03, 0];
    let p = [C8[0] + lerp(c.from[0], c.at[0], k) + drift[0], C8[1] + lerp(c.from[1], c.at[1], k) + drift[1], C8[2] + lerp(c.from[2], c.at[2], k)];
    let r = [c.rot[0] * (2 - k), c.rot[1] * (2 - k), c.rot[2]];
    let w = c.w, op = clamp(k * 1.5), blur = (1 - k) * 0.6;
    if (c.hero) {
      // comes forward, squares up, and fills the frame
      p = [lerp(p[0], C8[0], hero), lerp(p[1], C8[1] - 0.02, hero), lerp(p[2], C8[2] + 1.0, hero)];
      r = [lerp(r[0], 0, hero), lerp(r[1], 0, hero), lerp(r[2], 0, hero)];
    } else {
      op *= lerp(1, 0.32, hero); blur = Math.max(blur, 0.55 * hero);
      p[2] -= 0.6 * hero;
    }
    m.position.set(...p); m.rotation.set(...r);
    setCardSize(m, w, m.userData.h * (w / c.w));
    u.opacity.value = op * (1 - smooth(seg(t, 38.6, 39.0))); u.blur.value = blur; u.bright.value = 1.1 * (c.hero ? 1 : lerp(1, 0.6, hero));
    u.rim.value = 0.18 + (c.hero ? 0.12 * hero : 0);
  });
  // the four averages, one after another, catch the light
  const H = INSIGHT_CARDS.find(c => c.hero).m;
  [[0.268, 0.40, 37.4], [0.73, 0.40, 37.65], [0.268, 0.77, 37.9], [0.73, 0.77, 38.15]].forEach(([u, v, tt], i) => {
    const g = tileGlows[i], a = Math.exp(-Math.pow((t - tt - 0.12) / 0.2, 2)) * hero;
    if (a < 0.01) return;
    show(g); H.updateMatrixWorld();
    const w = new THREE.Vector3(u - 0.5, 0.5 - v, 0.02).applyMatrix4(H.matrixWorld);
    g.position.copy(w); g.quaternion.copy(H.quaternion); g.scale.set(0.62, 0.34, 1); g.material.uniforms.opacity.value = 0.32 * a;
  });
  grade.bloom = 0.7;
}

// SCENE 09 — the Coach (0:39 – 0:45)
// The music drops out. Threads of light carry what came before into the
// Coach, and the Coach's real answer to "Why am I tired?" builds on the
// phone. The four signals it names connect to it: nothing is claimed that
// the answer does not say.
const PH9 = [C8[0], C8[1] + 0.02, C8[2] - 0.25];
const threads = [0, 1, 2, 3, 4].map(i => { const rb = new Ribbon(80, { color: L([0.62, 0.6, 1.0]), color2: L([0.85, 0.87, 1.0]), width: 0.014 }); reg(rb.mesh); rb.mesh.renderOrder = 20; return rb; });
const SIGNALS = [
  { label: 'Asleep', value: '7h 32m', col: PAL.sleep, at: [-0.235, -0.2], t: 40.5 },
  { label: 'Recovery', value: '65', col: [0.0, 0.902, 0.463], at: [0.235, -0.2], t: 40.75 },
  { label: 'Energy', value: '43', col: PAL.battery, at: [-0.235, -0.36], t: 41.0 },
  { label: 'Shortfall', value: '1h 57m', col: PAL.awake, at: [0.235, -0.36], t: 41.25 }
];
const links = SIGNALS.map(() => { const rb = new Ribbon(40, { color: L([0.7, 0.68, 1.0]), width: 0.01 }); reg(rb.mesh); rb.mesh.renderOrder = 21; return rb; });
const TIRED_LAYERS = [
  { crop: [0, 0, 1206, 150], t: 39.55, from: { z: 0.1, blur: 0.2 } },
  { crop: [0, 168, 1206, 136], t: 39.65, from: { y: 0.15, z: 0.2 } },
  { crop: [48, 368, 1110, 220], t: 39.85, from: { z: 0.35, s: 0.92 }, radiusPx: 34 },                 // Apple Intelligence · on this iPhone
  { crop: [794, 638, 364, 104], t: 40.25, from: { x: 0.35, z: 0.3, s: 0.6 }, radiusPx: 52 },          // Why am I tired?
  { crop: [44, 778, 382, 76], t: 41.3, from: { x: -0.2, z: 0.2 } },                                  // Zoon · General
  { crop: [44, 866, 1118, 282], t: 41.45, from: { z: 0.15, blur: 0.1 }, wipe: [41.45, 42.55] },       // the answer
  { crop: [0, 2322, 1206, 196], t: 39.75, from: { y: -0.2, z: 0.1 } }                                // input bar
];
mark(39, 'coach');
cue(38.7, 'rev', { dur: 0.5, gain: 0.5 }); cue(39.0, 'sweep', { dur: 1.2, gain: 0.45 }); cue(39.85, 'glass', { gain: 0.45 });
cue(40.25, 'pop', { gain: 0.6, pan: 0.4 });
SIGNALS.forEach(s => cue(s.t, 'data', { dur: 0.25, gain: 0.45, pan: s.at[0] }));
cue(41.45, 'data', { dur: 1.1, gain: 0.3 }); cue(42.3, 'tick', { gain: 0.4 }); cue(43.0, 'riser', { dur: 2.0, gain: 0.7 }); cue(44.0, 'glint', { gain: 0.8 });
function camCoach(t) {
  if (t < 39.0) return camInsights(t);
  const s = camInsights(39.0);
  const pos = track(t, [[39.0, s.pos], [40.3, [PH9[0] + 0.16, PH9[1] + 0.3, PH9[2] + 4.3]], [45.0, [PH9[0] - 0.08, PH9[1] + 0.25, PH9[2] + 3.55]]]);
  const aim = track(t, [[39.0, s.aim], [40.3, [PH9[0], PH9[1] + 0.2, PH9[2]]], [45.0, [PH9[0], PH9[1] + 0.25, PH9[2]]]]);
  return { pos, aim };
}
function sCoach(t) {
  const cam = camCoach(t);
  lookFrom(cam.pos, cam.aim, 0);
  bgMat.uniforms.intensity.value = 0.58; bgMat.uniforms.glowAmt.value = 0.3; bgMat.uniforms.glowPos.value.set(0.5, 0.5);
  show(stars.points); stars.mat.uniforms.opacity.value = 0.55;
  show(dust.points); dust.mat.uniforms.opacity.value = 0.9; dust.mat.uniforms.morph.value = seg(t, 0, 16);
  // threads from where the cards were to the Coach
  INSIGHT_CARDS.forEach((c, i) => {
    const k0 = seg(t, 38.75 + i * 0.07, 39.75 + i * 0.07);
    const fade = 1 - smooth(seg(t, 39.9 + i * 0.05, 40.4 + i * 0.05));
    if (k0 <= 0 || fade <= 0) return;
    const rb = threads[i]; show(rb.mesh);
    const a = [C8[0] + c.at[0], C8[1] + c.at[1], C8[2] + c.at[2] - (c.hero ? -1.0 : 0.6)], b = [PH9[0], PH9[1] + 0.1, PH9[2] + FRONT];
    const pts = []; for (let j = 0; j < 80; j++) { const u = j / 79, bow = Math.sin(u * Math.PI) * 0.35;
      pts.push([lerp(a[0], b[0], u) + bow * (i % 2 ? 0.4 : -0.4), lerp(a[1], b[1], u) + bow * 0.2, lerp(a[2], b[2], u) + bow * 0.5]); }
    rb.set(pts); rb.mat.uniforms.progress.value = eInOut3(k0); rb.mat.uniforms.head.value = 1.4; rb.mat.uniforms.fadeTail.value = 0.45;
    rb.mat.uniforms.opacity.value = 1.2 * fade;
  });
  // the phone, with the Coach's answer
  const rise = eOut5(seg(t, 39.05, 40.2));
  phone.group.position.set(PH9[0], PH9[1] - 3.2 * (1 - rise), PH9[2] - 0.6 * (1 - rise));
  phone.group.rotation.set(0.06 * (1 - rise), lerp(0.35, -0.06, rise) + 0.05 * Math.sin(t * 0.5), 0);
  phone.show(camera); phone.sheenMat.uniforms.opacity.value = rise;
  const wake = smooth(seg(t, 39.35, 39.7));
  if (rise > 0.01) {
    ground(SCR['coach-ask-tired'], wake);
    for (const Ly of TIRED_LAYERS) {
      const k = eOutExpo(seg(t, Ly.t, Ly.t + 0.6));
      if (k <= 0) continue;
      const m = phone.layer(SCR['coach-ask-tired'], Ly.crop, { radiusPx: Ly.radiusPx || 0 });
      if (Ly.wipe) { const u = m.material.uniforms; u.revealMode.value = 1; u.revealDir.value.set(0, -1); u.revealSoft.value = 0.12;
        u.reveal.value = lerp(-0.1, 1.1, eInOut3(seg(t, Ly.wipe[0], Ly.wipe[1]))); }
      pose(m, k, Ly.from);
    }
  }
  // the four signals the answer names, joined to it
  phone.group.updateMatrixWorld();
  const answerAt = i => new THREE.Vector3(SIGNALS[i].at[0] * 0.55, capY(1150), FRONT + 0.02).applyMatrix4(phone.group.matrixWorld);
  SIGNALS.forEach((sg, i) => {
    const ka = eOutBack(seg(t, sg.t, sg.t + 0.4), 1.5), a = clamp(ka) * (1 - smooth(seg(t, 43.65, 43.95)));
    if (a <= 0) return;
    const w = new THREE.Vector3(sg.at[0], sg.at[1], FRONT + 0.06).applyMatrix4(phone.group.matrixWorld);
    // the line from the signal into the answer
    const lk = eInOut3(seg(t, sg.t + 0.15, sg.t + 0.7));
    const rb = links[i]; show(rb.mesh);
    const e = answerAt(i);
    const pts = []; for (let j = 0; j < 40; j++) { const u = j / 39; pts.push([lerp(w.x, e.x, u), lerp(w.y, e.y, u), lerp(w.z, e.z, u) + Math.sin(u * Math.PI) * 0.04]); }
    rb.set(pts); rb.mat.uniforms.progress.value = lk; rb.mat.uniforms.head.value = 1.2; rb.mat.uniforms.opacity.value = 0.9 * a;
    rb.mat.uniforms.color.value.set(...L(sg.col)); rb.mat.uniforms.color2.value.set(...L(sg.col));
    const p = project([w.x, w.y, w.z]);
    T.g.save(); T.g.translate(p.x, p.y); T.g.scale(lerp(0.6, 1, clamp(ka)), lerp(0.6, 1, clamp(ka))); T.g.translate(-p.x, -p.y);
    T.chip(p.x, p.y, css(sg.col), sg.label, sg.value, a, { size: 38, fill: 'rgba(18,20,40,0.9)', stroke: css(sg.col, 0.6) });
    T.g.restore();
  });
  grade.bloom = 0.7;
  T.line('Meet your personal', 540, 1650, t, 42.3, { size: 80, weight: 800, ls: -0.5, style: 'rise', stagger: 0.02, out: 43.75, outDur: 0.3 });
  T.line('sleep intelligence.', 540, 1745, t, 42.65, { size: 80, weight: 800, ls: -0.5, style: 'rise', stagger: 0.02, color: css(PAL.lilac), out: 43.8, outDur: 0.3 });
  T.line('Zoon Coach', 540, 1720, t, 44.0, { size: 112, weight: 800, ls: lerp(18, 0, eOut5(seg(t, 44.0, 44.8))), style: 'blur', stagger: 0.04, dur: 0.7, glow: 0.2, out: 44.5, outDur: 0.3 });
}

// SCENE 10 — tonight's recommendation (0:45 – 0:50)
// The Coach's answer to "When should I go to bed tonight?", its three facts
// as chips, and the Tonight's plan card they come from (Today, at night).
const TONIGHT_LAYERS = [
  { crop: [468, 638, 694, 104], t: 45.05, from: { x: 0.3, z: 0.3, s: 0.7 }, radiusPx: 52 },          // the question
  { crop: [44, 778, 584, 76], t: 45.3, from: { x: -0.2, z: 0.2 } },                                  // Zoon · Recorded evidence
  { crop: [44, 866, 1118, 172], t: 45.4, from: { z: 0.15 }, wipe: [45.4, 46.1] }                      // the answer
];
const PLAN = { map: 'today-night', crop: [48, 1850, 1110, 462], radiusPx: 56 };
const planCard = reg(card(SCR['today-night'], { crop: PLAN.crop, imgW: CAP_W, imgH: CAP_H, width: 1.0, radiusPx: PLAN.radiusPx }));
planCard.renderOrder = 22; planCard.material.uniforms.rim.value = 0.25;
const TONIGHT_CHIPS = [
  { label: 'Bed', value: '11:02 PM', col: PAL.sleep, t: 46.15 },
  { label: 'Wake', value: '6:46 AM', col: PAL.awake, t: 46.4 },
  { label: 'Target', value: '9h 5m', col: PAL.battery, t: 46.65 }
];
mark(45, 'tonight');
cue(45.0, 'impact', { gain: 0.8 }); cue(45.05, 'pop', { gain: 0.5, pan: 0.4 }); cue(45.4, 'data', { dur: 0.7, gain: 0.35 });
TONIGHT_CHIPS.forEach((c, i) => cue(c.t, 'pop', { gain: 0.5, pan: (i - 1) * 0.5 }));
cue(47.0, 'whoosh', { gain: 0.55, pan: 0.2 }); cue(47.6, 'glass', { gain: 0.5 }); cue(47.8, 'tick', { gain: 0.4 }); cue(48.3, 'tick', { gain: 0.4 }); cue(49.5, 'sweep', { dur: 0.5, gain: 0.4 });
function camTonight(t) {
  const s = camCoach(45.0);
  const pos = track(t, [[45.0, s.pos], [46.9, [PH9[0] + 0.02, PH9[1] + 0.25, PH9[2] + 3.45]], [47.9, [PH9[0] + 0.05, PH9[1] + 0.1, PH9[2] + 3.9]], [50.0, [PH9[0] + 0.12, PH9[1] + 0.06, PH9[2] + 3.7]]]);
  const aim = track(t, [[45.0, s.aim], [46.9, [PH9[0], PH9[1] + 0.25, PH9[2]]], [47.9, [PH9[0], PH9[1] + 0.0, PH9[2] + 0.9]], [50.0, [PH9[0], PH9[1] + 0.0, PH9[2] + 0.9]]]);
  return { pos, aim };
}
function sTonight(t) {
  const cam = camTonight(t);
  lookFrom(cam.pos, cam.aim, 0);
  bgMat.uniforms.intensity.value = 0.6; bgMat.uniforms.glowAmt.value = 0.32; bgMat.uniforms.glowPos.value.set(0.5, 0.5);
  show(stars.points); stars.mat.uniforms.opacity.value = 0.55;
  show(dust.points); dust.mat.uniforms.opacity.value = 0.9; dust.mat.uniforms.morph.value = seg(t, 0, 16);
  // the phone recedes a little as the plan comes forward
  const planK = eInOut5(seg(t, 46.95, 47.75));
  phone.group.position.set(PH9[0], PH9[1] - 2.6 * eIn3(seg(t, 47.0, 48.0)), PH9[2] - 0.8 * planK);
  phone.group.rotation.set(0.4 * eIn3(seg(t, 47.0, 48.0)), -0.06 + 0.05 * Math.sin(t * 0.5), 0);
  phone.show(camera);
  // the chat turns to tonight: the old answer wipes up and away, the new one builds
  const swap = eInOut3(seg(t, 44.85, 45.3));
  ground(SCR['coach-ask-tonight'], 1);
  if (swap < 1) { const s = phone.setScreen(SCR['coach-ask-tired'], { b: true, opacity: 1 - swap }); }
  for (const Ly of TIRED_LAYERS.slice(0, 3).concat(TIRED_LAYERS.slice(7))) phone.layer(SCR['coach-ask-tonight'], Ly.crop, { radiusPx: Ly.radiusPx || 0 });
  for (const Ly of TONIGHT_LAYERS) {
    const k = eOutExpo(seg(t, Ly.t, Ly.t + 0.6));
    if (k <= 0) continue;
    const m = phone.layer(SCR['coach-ask-tonight'], Ly.crop, { radiusPx: Ly.radiusPx || 0 });
    if (Ly.wipe) { const u = m.material.uniforms; u.revealMode.value = 1; u.revealDir.value.set(0, -1); u.revealSoft.value = 0.12;
      u.reveal.value = lerp(-0.1, 1.1, eInOut3(seg(t, Ly.wipe[0], Ly.wipe[1]))); }
    pose(m, k, Ly.from);
  }
  // three facts from the answer
  phone.group.updateMatrixWorld();
  TONIGHT_CHIPS.forEach((c, i) => {
    const ka = eOutBack(seg(t, c.t, c.t + 0.4), 1.5), a = clamp(ka) * (1 - smooth(seg(t, 46.95, 47.35)));
    if (a <= 0) return;
    const w = new THREE.Vector3((i - 1) * 0.315, capY(1210), FRONT + 0.06).applyMatrix4(phone.group.matrixWorld);
    const p = project([w.x, w.y, w.z]);
    T.g.save(); T.g.translate(p.x, p.y); T.g.scale(lerp(0.6, 1, clamp(ka)), lerp(0.6, 1, clamp(ka))); T.g.translate(-p.x, -p.y);
    T.chip(p.x, p.y, css(c.col), c.label, c.value, a, { size: 30, fill: 'rgba(18,20,40,0.9)', stroke: css(c.col, 0.6) });
    T.g.restore();
  });
  // Tonight's plan, forward
  if (planK > 0) {
    show(planCard);
    const from = new THREE.Vector3(capX(603), capY(2076), FRONT + 0.01).applyMatrix4(phone.group.matrixWorld);
    const to = new THREE.Vector3(PH9[0], PH9[1] - 0.02, PH9[2] + 0.9);
    planCard.position.copy(from.clone().lerp(to, planK));
    planCard.rotation.set(lerp(0, -0.06, planK), lerp(phone.group.rotation.y, -0.05, planK), 0);
    const s = lerp(0.92, 0.86, planK); setCardSize(planCard, s, s * PLAN.crop[3] / PLAN.crop[2]);
    planCard.material.uniforms.opacity.value = smooth(seg(t, 46.95, 47.2)) * (1 - smooth(seg(t, 49.6, 50.0)));
    const kp = project([to.x, to.y + 0.34, to.z]);
    T.g.save(); T.g.globalAlpha = smooth(seg(t, 47.5, 47.9)) * (1 - smooth(seg(t, 49.5, 49.9)));
    T.font(34, 800, T.BODY, 4); T.g.textAlign = 'center'; T.g.fillStyle = css(PAL.lilac); T.g.fillText("TONIGHT'S RECOMMENDATION", kp.x, kp.y);
    T.g.restore();
  }
  grade.bloom = 0.7;
  T.line('Not generic advice.', 540, 1720, t, 45.6, { size: 86, weight: 800, ls: -0.5, style: 'rise', stagger: 0.02, out: 47.35, outDur: 0.3 });
  T.line('Your sleep.', 540, 230, t, 47.8, { size: 86, weight: 800, ls: -0.5, style: 'rise', stagger: 0.02, out: 49.4, outDur: 0.3 });
  T.line('Your patterns.', 540, 330, t, 48.3, { size: 86, weight: 800, ls: -0.5, style: 'rise', stagger: 0.02, color: css(PAL.lilac), out: 49.45, outDur: 0.3 });
}

// SCENE 11 — everything before sleep (0:50 – 0:56)
// The tools, as their real screens, turning past on the beat. The wake alarm
// has no screen of its own (it lives in Settings), so it is a tile in the
// app's own words: "Notifies within your usual wake window."
let alarmTex = null;
function drawAlarmTile() {
  alarmTex = canvasTex(1206, 2622, (g, w, h) => {
    const gr = g.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, '#171a3a'); gr.addColorStop(1, '#0a0c1e');
    g.fillStyle = gr; g.fillRect(0, 0, w, h);
    const cx = w / 2, cy = 980, R = 250;
    g.strokeStyle = 'rgba(196,184,255,0.95)'; g.lineWidth = 34; g.lineCap = 'round';
    g.beginPath(); g.arc(cx, cy, R, 0, Math.PI * 2); g.stroke();
    g.beginPath(); g.moveTo(cx, cy); g.lineTo(cx, cy - 150); g.moveTo(cx, cy); g.lineTo(cx + 110, cy + 60); g.stroke();
    g.beginPath(); g.arc(cx - 250, cy - 230, 90, Math.PI * 1.05, Math.PI * 1.75); g.stroke();
    g.beginPath(); g.arc(cx + 250, cy - 230, 90, Math.PI * 1.25, Math.PI * 1.95); g.stroke();
    g.beginPath(); g.moveTo(cx - 170, cy + 250); g.lineTo(cx - 215, cy + 310); g.moveTo(cx + 170, cy + 250); g.lineTo(cx + 215, cy + 310); g.stroke();
    g.fillStyle = '#f4f5fb'; g.textAlign = 'center'; g.font = '800 120px Nunito'; g.fillText('Wake alarm', cx, 1560);
    g.fillStyle = 'rgba(214,216,232,0.85)'; g.font = '500 62px Manrope'; g.fillText('Notifies within your', cx, 1700); g.fillText('usual wake window.', cx, 1785);
  });
}
const TOOLS = [
  { map: 'soundscapes', name: 'Sleep Sounds', sub: 'Mix and save scenes', hot: [[130, 640], [700, 640], [130, 1100]] },
  { map: 'windDown', name: 'Tonight', sub: 'Guided breathing and your sound scene', hot: [[738, 2330]] },
  { map: 'breathing', name: '4-7-8 breathing', sub: 'Voice, haptics, or silent', ring: [603, 940, 236] },
  { map: 'snoreCheck', name: 'Snore Check', sub: 'Listens on-device', hot: [[603, 2404]] },
  { map: 'nap', name: 'Nap', sub: '10, 20, 30 or 90 minutes', hot: [[1044, 1026]] },
  { map: null, name: 'Wake alarm', sub: 'Within your usual wake window', hot: [[603, 980]] }
];
const TOOL_W = 0.72, TOOL_H = TOOL_W * CAP_H / CAP_W;
const toolCards = TOOLS.map(() => {
  const m = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), cardMaterial()); setCardSize(m, TOOL_W, TOOL_H);
  m.material.uniforms.radius.value = TOOL_W * 0.137; m.material.uniforms.rim.value = 0.22; m.renderOrder = 14; return reg(m);
});
const toolHot = [0, 1, 2].map(() => { const g = glow(L([0.72, 0.7, 1.0]), 1.8); g.renderOrder = 15; return reg(g); });
const toolRing = arc({ color: L([0.62, 0.58, 1.0]), color2: L([0.3, 0.85, 0.8]), thickness: 0.035 }); toolRing.renderOrder = 15; reg(toolRing);
const C11 = [PH9[0], PH9[1] + 0.05, PH9[2] - 0.3];
const TOOL_STEPS = [51.0, 51.75, 52.5, 53.25, 54.0];
const toolIndex = t => TOOL_STEPS.reduce((s, b) => s + spring(seg(t, b, b + 0.55), 0.3, 1.6), 0);
mark(50, 'tools');
cue(50.0, 'whoosh', { gain: 0.6, pan: 0.3 });
TOOL_STEPS.forEach((b, i) => { cue(b, 'whoosh', { gain: 0.35, pan: 0.5 }); cue(b + 0.3, 'pop', { gain: 0.45, pan: 0 }); });
cue(55.2, 'riser', { dur: 0.8, gain: 0.8 });
function camTools(t) {
  const s = camTonight(50.0);
  const pos = track(t, [[50.0, s.pos], [50.9, [C11[0], C11[1] + 0.42, C11[2] + 4.3]], [55.4, [C11[0] + 0.1, C11[1] + 0.38, C11[2] + 4.05]], [56.0, [C11[0], C11[1] + 0.1, C11[2] + 4.6]]]);
  const aim = track(t, [[50.0, s.aim], [50.9, [C11[0], C11[1] + 0.12, C11[2]]], [55.4, [C11[0], C11[1] + 0.12, C11[2]]], [56.0, [C11[0], C11[1] + 0.05, C11[2]]]]);
  return { pos, aim };
}
function sTools(t) {
  const cam = camTools(t);
  lookFrom(cam.pos, cam.aim, 0);
  bgMat.uniforms.intensity.value = 0.6; bgMat.uniforms.glowAmt.value = 0.32; bgMat.uniforms.glowPos.value.set(0.5, 0.5);
  show(stars.points); stars.mat.uniforms.opacity.value = 0.55;
  show(dust.points); dust.mat.uniforms.opacity.value = 0.9; dust.mat.uniforms.morph.value = seg(t, 0, 16);
  // the cards arrive, then turn past one per step; at the end they whip back to Sleep Sounds
  const arrive = eOutExpo(seg(t, 50.0, 50.9));
  const back = eInOutExpo(seg(t, 55.25, 55.9));
  const c = lerp(toolIndex(t), 0, back);
  const R = 1.55;
  TOOLS.forEach((tool, i) => {
    const m = show(toolCards[i]), u = m.material.uniforms;
    const map = tool.map ? SCR[tool.map] : alarmTex;
    u.map.value = map; u.hasMap.value = map ? 1 : 0;
    const th = (i - c) * 0.6;
    const d = Math.abs(i - c);
    m.position.set(C11[0] + R * Math.sin(th), C11[1] - (1 - arrive) * (1.4 + i * 0.3), C11[2] + R * Math.cos(th) - R - (1 - arrive) * 2.5);
    m.rotation.set(0, th * 0.85, 0);
    u.opacity.value = clamp(arrive * 1.4 - i * 0.08) * clamp(1.25 - d * 0.28) * (1 - smooth(seg(t, 55.8, 56.05)) * (i === 0 ? 0 : 1));
    u.blur.value = clamp(d - 0.35) * 0.45; u.bright.value = 1.1 * lerp(1, 0.55, clamp(d));
    // the micro-animation on whichever card faces us
    // the micro-animation belongs to the card's own turn in front, not to the
    // spring's overshoot, so it neither flickers nor pops
    const tIn = i === 0 ? 50.35 : TOOL_STEPS[i - 1] + 0.3, tOut = i < TOOL_STEPS.length ? TOOL_STEPS[i] : 55.2;
    const facing = smooth(seg(t, tIn, tIn + 0.3)) * (1 - smooth(seg(t, tOut - 0.05, tOut + 0.15))) * arrive * (1 - back);
    if (facing > 0.02) {
      m.updateMatrixWorld();
      const at = (px, py, z = 0.01) => new THREE.Vector3((px / CAP_W - 0.5) * 1, (0.5 - py / CAP_H) * 1, z).applyMatrix4(m.matrixWorld);
      (tool.hot || []).forEach(([hx, hy], j) => {
        const g = toolHot[j]; show(g); g.position.copy(at(hx, hy)); g.quaternion.copy(m.quaternion);
        const pulse = 0.5 + 0.5 * Math.sin((t - j * 0.18) * Math.PI * 4);
        g.scale.setScalar(0.28 + 0.06 * pulse); g.material.uniforms.opacity.value = 0.22 * facing * (0.5 + 0.5 * pulse);
      });
      if (tool.ring) {
        show(toolRing); toolRing.position.copy(at(tool.ring[0], tool.ring[1], 0.012)); toolRing.quaternion.copy(m.quaternion);
        const breath = 0.5 - 0.5 * Math.cos((t - 51.9) * Math.PI * 1.0);
        toolRing.scale.setScalar(tool.ring[2] / CAP_W * TOOL_W * 2 * (1.06 + 0.16 * breath));
        toolRing.material.uniforms.opacity.value = 0.9 * facing; toolRing.material.uniforms.glowAmt.value = 0.5;
      }
    }
  });
  // the facing tool's name, in the app's words
  const ci = Math.round(c), cf = clamp(1 - Math.abs(c - ci) * 3.2) * arrive * (1 - smooth(seg(t, 55.1, 55.4)));
  const tool = TOOLS[clamp(ci, 0, TOOLS.length - 1)];
  if (cf > 0.02 && tool) {
    const b = project([C11[0], C11[1] - TOOL_H / 2 - 0.02, C11[2]]);
    T.g.save(); T.g.globalAlpha = cf; T.g.textAlign = 'center'; T.g.textBaseline = 'top';
    T.font(58, 800, T.HEAD, -0.3); T.g.fillStyle = '#f4f5fb'; T.g.fillText(tool.name, 540, b.y + 34);
    T.font(34, 600, T.BODY, 0.2); T.g.fillStyle = 'rgba(214,216,232,0.85)'; T.g.fillText(tool.sub, 540, b.y + 108);
    T.g.restore();
  }
  grade.bloom = 0.7;
  T.line('Everything you need', 540, 180, t, 50.6, { size: 80, weight: 800, ls: -0.5, style: 'rise', stagger: 0.02, out: 55.3, outDur: 0.3 });
  T.line('before sleep.', 540, 272, t, 50.95, { size: 80, weight: 800, ls: -0.5, style: 'rise', stagger: 0.02, color: css(PAL.lilac), out: 55.35, outDur: 0.3 });
}

// SCENE 12 — slow down (0:56 – 1:01)
// The drop: Sleep Sounds becomes the phone again and its sound wraps around
// it in rings of light, pulsing on the beat, until they gather into one
// ring, the Wind Down's 4-7-8 breath.
const soundRings = [0, 1, 2, 3, 4, 5, 6].map(i => {
  const rb = new Ribbon(180, { color: L(mix(PAL.sleep, PAL.battery, i / 6)).map(v => v * 1.05), color2: L(mix(PAL.rem, [0.45, 0.8, 1.0], i / 6)).map(v => v * 1.05), width: 0.03 });
  rb.mat.uniforms.softness.value = 0.7; reg(rb.mesh); rb.mesh.renderOrder = 18; return rb;
});
const breathRing = arc({ color: L([0.62, 0.56, 1.0]).map(v => v * 1.3), color2: L([0.3, 0.85, 0.8]).map(v => v * 1.3), thickness: 0.02 }); reg(breathRing); breathRing.renderOrder = 19;
const PH12 = C11;
// a pulse on every beat, with a short attack so it swells rather than strobes
const beatEnv = (t, t0) => { let e = 0; for (let b = t0; b <= t + 0.001; b += 0.5) { const x = t - b; e = Math.max(e, smooth(clamp(x / 0.06)) * Math.exp(-Math.max(0, x - 0.06) * 3.2)); } return e; };
mark(56, 'drop');
cue(56.0, 'impact', { gain: 1.0 }); cue(56.0, 'bass', { gain: 0.8 });
cue(56.5, 'tick', { gain: 0.5 }); cue(57.75, 'tick', { gain: 0.5 }); cue(59.0, 'impact', { gain: 0.6 });
cue(58.35, 'sweep', { dur: 0.6, gain: 0.5 }); cue(58.95, 'glass', { gain: 0.6 }); cue(60.6, 'whoosh', { gain: 0.55, pan: -0.3 });
function camSlow(t) {
  if (t < 56.0) return camTools(t);
  const s = camTools(56.0);
  const orbit = track(t, [[56.0, 0], [58.6, 0.46], [61.0, 0.22]]);
  const dist = track(t, [[56.0, 5.5], [58.6, 5.9], [61.0, 6.2]]);
  const lift = track(t, [[56.0, 0.1], [58.6, -0.3], [61.0, 0.05]]);
  const at = [PH12[0] + Math.sin(orbit) * dist, PH12[1] + lift + 0.12, PH12[2] + Math.cos(orbit) * dist];
  return { pos: track(t, [[56.0, s.pos], [56.3, at], [61.0, at]].map((k, i) => i ? [k[0], at] : k)), aim: [PH12[0], PH12[1] + 0.12, PH12[2]] };
}
function sSlow(t) {
  const cam = camSlow(t);
  lookFrom(cam.pos, cam.aim, 0.04 * Math.sin(seg(t, 56, 61) * Math.PI));
  bgMat.uniforms.intensity.value = 0.6; bgMat.uniforms.glowAmt.value = 0.34 + 0.05 * beatEnv(t, 56.0) * (1 - seg(t, 58.4, 59)); bgMat.uniforms.glowPos.value.set(0.5, 0.55);
  show(stars.points); stars.mat.uniforms.opacity.value = 0.55;
  show(dust.points); dust.mat.uniforms.opacity.value = 0.9; dust.mat.uniforms.morph.value = seg(t, 0, 16);
  // Sleep Sounds becomes the phone again
  const grow = eOutExpo(seg(t, 55.85, 56.35));
  phone.group.position.set(...PH12);
  phone.group.rotation.set(0, 0.05 * Math.sin(t * 0.6), 0);
  phone.group.scale.setScalar(lerp(TOOL_W, 1, grow));
  phone.show(camera);
  const toBreath = smooth(seg(t, 58.55, 58.95)), toSnore = smooth(seg(t, 60.6, 61.0));
  phone.setScreen(SCR.soundscapes, { opacity: 1 });
  if (toBreath > 0) phone.setScreen(toSnore > 0 ? SCR.snoreCheck : SCR.breathing, { b: true, opacity: toSnore > 0 ? toSnore : toBreath });
  if (toSnore > 0 && toSnore < 1) phone.setScreen(SCR.breathing, { opacity: 1 });
  // rings of sound around it, pulsing on the beat, then gathering into one
  const env = beatEnv(t, 56.0), gather = eInOut3(seg(t, 58.3, 59.0)), spin = t * 0.7;
  soundRings.forEach((rb, i) => {
    const a = smooth(seg(t, 55.95 + i * 0.04, 56.3 + i * 0.04)) * (1 - smooth(seg(t, 59.0, 59.4)));
    if (a <= 0) return;
    show(rb.mesh);
    const y0 = lerp((i - 3) * 0.3, 0.12, gather), r0 = lerp(0.95 + 0.14 * Math.sin(i * 1.7), 0.78, gather);
    const tilt = lerp(0.25 * Math.sin(i * 2.1), 0, gather);
    const pts = [];
    for (let j = 0; j < 180; j++) {
      const u = j / 179 * Math.PI * 2 + spin * (i % 2 ? 1 : -1) * 0.6;
      const wob = (0.05 + 0.05 * env) * (1 - gather) * Math.sin(u * (3 + i * 0.5) + t * 4);
      const r = r0 + wob;
      pts.push([PH12[0] + Math.cos(u) * r, PH12[1] + y0 + Math.sin(u) * r * tilt + wob * 0.5, PH12[2] + Math.sin(u) * r]);
    }
    rb.set(pts); rb.mat.uniforms.opacity.value = a * (0.82 + 0.28 * env); rb.mat.uniforms.width.value = 0.027 + 0.01 * env;
  });
  // the breath: in for four, out for eight, compressed to the film's time
  const br = smooth(seg(t, 58.8, 59.2)) * (1 - smooth(seg(t, 60.55, 60.9)));
  if (br > 0) {
    show(breathRing);
    phone.group.updateMatrixWorld();
    const c = new THREE.Vector3(capX(603), capY(940), FRONT + 0.012).applyMatrix4(phone.group.matrixWorld);
    breathRing.position.copy(c); breathRing.quaternion.copy(phone.group.quaternion);
    const inhale = eInOut3(seg(t, 58.9, 59.7)), exhale = eInOut3(seg(t, 59.9, 60.9));
    breathRing.scale.setScalar(236 / CAP_W * 2 * (1.05 + 0.55 * inhale - 0.55 * exhale));
    breathRing.material.uniforms.opacity.value = br; breathRing.material.uniforms.glowAmt.value = 0.8;
  }
  grade.bloom = 0.85 + 0.1 * env * (1 - gather);
  grade.flash = 0.035 * Math.exp(-Math.pow((t - 56.0) / 0.06, 2)) + 0.02 * Math.exp(-Math.pow((t - 59.0) / 0.06, 2));
  T.line('Slow down.', 540, 250, t, 56.5, { size: 120, weight: 900, ls: -0.5, style: 'blur', by: 'word', stagger: 0.08, dur: 0.45, out: 57.55, outDur: 0.25 });
  T.line('Disconnect.', 540, 250, t, 57.75, { size: 120, weight: 900, ls: -0.5, style: 'blur', by: 'word', stagger: 0.08, dur: 0.45, out: 58.8, outDur: 0.25 });
  T.line('Sleep.', 540, 250, t, 59.0, { size: 140, weight: 900, ls: 1, style: 'blur', dur: 0.6, color: css(PAL.lilac), glow: 0.3, out: 60.55, outDur: 0.35 });
}

// SCENE 13 — the night, listened to (1:01 – 1:06)
// Snore Check, as the app describes itself: it listens on-device, the audio
// is never saved, and the morning brings minutes flagged, how much of the
// night was covered, and timestamped labels. The waveform is the idea of
// listening, not a recording: it carries no data.
const waveBars = new THREE.InstancedMesh(new THREE.PlaneGeometry(1, 1), new THREE.ShaderMaterial({
  transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, premultipliedAlpha: true,
  uniforms: { opacity: { value: 1 }, c0: { value: new THREE.Vector3(...L(PAL.sleep).map(v => v * 1.3)) }, c1: { value: new THREE.Vector3(...L([0.3, 0.85, 0.8]).map(v => v * 1.3)) } },
  vertexShader: `attribute float fx; varying vec2 vUv; varying float vX; void main(){ vUv = uv; vX = fx; gl_Position = projectionMatrix * modelViewMatrix * instanceMatrix * vec4(position, 1.); }`,
  fragmentShader: `uniform float opacity; uniform vec3 c0, c1; varying vec2 vUv; varying float vX;
    void main(){ vec2 q = abs(vUv - 0.5) * 2.; float m = (1. - smoothstep(0.55, 1., q.x)) * (1. - smoothstep(0.9, 1., q.y));
      float fade = smoothstep(0., 0.15, vX) * smoothstep(1., 0.8, vX);
      gl_FragColor = vec4(mix(c0, c1, vX) * m * fade * opacity, 0.); }`
}), 64);
waveBars.geometry.setAttribute('fx', new THREE.InstancedBufferAttribute(new Float32Array(64).map((_, i) => i / 63), 1));
waveBars.frustumCulled = false; waveBars.renderOrder = 25; reg(waveBars);
const listenLevel = x => { // a slow breath, with the occasional louder rumble
  const b = 0.35 + 0.3 * Math.pow(0.5 + 0.5 * Math.sin(x * 1.3), 2);
  const r = Math.max(0, Math.sin(x * 0.37 + 1.1)) ** 6 * 0.9;
  return clamp(b + r * (0.6 + 0.4 * Math.sin(x * 9.1)) + 0.12 * vnoise(x * 3.3));
};
mark(61, 'snore');
cue(61.0, 'boom', { gain: 0.6 }); cue(61.45, 'click', { gain: 0.7 }); cue(61.5, 'swell', { dur: 0.8, gain: 0.4 });
cue(62.0, 'pop', { gain: 0.45, pan: -0.4 }); cue(62.5, 'pop', { gain: 0.45, pan: 0.4 });
cue(63.4, 'data', { dur: 0.3, gain: 0.35, pan: -0.5 }); cue(63.75, 'data', { dur: 0.3, gain: 0.35 }); cue(64.1, 'data', { dur: 0.3, gain: 0.35, pan: 0.5 });
cue(65.6, 'whoosh', { gain: 0.6, pan: 0.5 });
function camSnore(t) {
  const s = camSlow(61.0);
  const pos = track(t, [[61.0, s.pos], [62.0, [PH12[0] - 0.45, PH12[1] + 0.3, PH12[2] + 6.5]], [66.0, [PH12[0] + 0.22, PH12[1] + 0.25, PH12[2] + 6.2]]]);
  const aim = track(t, [[61.0, s.aim], [62.0, [PH12[0], PH12[1] + 0.24, PH12[2]]], [66.0, [PH12[0], PH12[1] + 0.22, PH12[2]]]]);
  return { pos, aim };
}
const SNORE_CHIPS = [
  { label: 'Listens on-device', col: PAL.battery, t: 62.0, x: 330 },
  { label: 'Audio never saved', col: [0.0, 0.902, 0.463], t: 62.5, x: 750 }
];
const RESULT_CHIPS = [
  { label: 'Minutes flagged', t: 63.4 }, { label: 'Night covered', t: 63.75 }, { label: 'Timestamped labels', t: 64.1 }
];
function sSnore(t) {
  const cam = camSnore(t);
  lookFrom(cam.pos, cam.aim, 0);
  bgMat.uniforms.intensity.value = 0.58; bgMat.uniforms.glowAmt.value = 0.3; bgMat.uniforms.glowPos.value.set(0.5, 0.5);
  show(stars.points); stars.mat.uniforms.opacity.value = 0.55;
  show(dust.points); dust.mat.uniforms.opacity.value = 0.9; dust.mat.uniforms.morph.value = seg(t, 0, 16);
  phone.group.position.set(...PH12); phone.group.scale.setScalar(1);
  phone.group.rotation.set(0, lerp(0.05 * Math.sin(61.0 * 0.6), 0.2 * Math.sin(seg(t, 61, 66) * Math.PI * 0.5) - 0.08, smooth(seg(t, 61.0, 62.2))), 0);
  phone.show(camera);
  phone.setScreen(SCR.snoreCheck, { opacity: 1 });
  // "Start listening" is pressed
  const press = Math.exp(-Math.pow((t - 61.5) / 0.12, 2));
  if (t > 61.2 && t < 62.2) {
    const m = phone.layer(SCR.snoreCheck, [40, 2330, 1126, 150], { radiusPx: 75, bright: 1 + 0.5 * press });
    m.scale.x *= 1 - 0.03 * press; m.scale.y *= 1 - 0.03 * press;
  }
  // the listening: bars that breathe, streaming out of the phone's foot
  const wa = smooth(seg(t, 61.55, 62.1)) * (1 - smooth(seg(t, 65.5, 65.95)));
  if (wa > 0) {
    show(waveBars); waveBars.material.uniforms.opacity.value = wa;
    phone.group.updateMatrixWorld();
    const base = new THREE.Vector3(0, capY(1950), FRONT + 0.22).applyMatrix4(phone.group.matrixWorld);
    const dummy = new THREE.Object3D();
    for (let i = 0; i < 64; i++) {
      const u = i / 63, x = lerp(-0.62, 0.62, u), lvl = listenLevel(u * 9 - t * 3.2) * wa * smooth(seg(u, 0, 1));
      dummy.position.set(base.x + x, base.y, base.z); dummy.quaternion.copy(phone.group.quaternion);
      dummy.scale.set(0.012, 0.03 + lvl * 0.34, 1); dummy.updateMatrix(); waveBars.setMatrixAt(i, dummy.matrix);
    }
    waveBars.instanceMatrix.needsUpdate = true;
  }
  // what it promises, in its own words
  phone.group.updateMatrixWorld();
  SNORE_CHIPS.forEach(c => {
    const ka = eOutBack(seg(t, c.t, c.t + 0.4), 1.5), a = clamp(ka) * (1 - smooth(seg(t, 65.4, 65.8)));
    if (a <= 0) return;
    const p = { x: c.x, y: 392 };
    T.g.save(); T.g.translate(p.x, p.y); T.g.scale(lerp(0.6, 1, clamp(ka)), lerp(0.6, 1, clamp(ka))); T.g.translate(-p.x, -p.y);
    T.chip(p.x, p.y, css(c.col), c.label, null, a, { size: 36, fill: 'rgba(14,26,30,0.9)', stroke: css(c.col, 0.6) });
    T.g.restore();
  });
  // and what the morning brings
  RESULT_CHIPS.forEach((c, i) => {
    const ka = eOutBack(seg(t, c.t, c.t + 0.4), 1.5), a = clamp(ka) * (1 - smooth(seg(t, 65.4, 65.8)));
    if (a <= 0) return;
    const ws = RESULT_CHIPS.map(r => T.chipWidth(r.label, null, 29)), tot = ws.reduce((s, v) => s + v, 0) + 16 * (ws.length - 1);
    const x = 540 - tot / 2 + ws.slice(0, i).reduce((s, v) => s + v + 16, 0) + ws[i] / 2, y = 1790;
    T.g.save(); T.g.translate(x, y); T.g.scale(lerp(0.6, 1, clamp(ka)), lerp(0.6, 1, clamp(ka))); T.g.translate(-x, -y);
    T.chip(x, y, css(PAL.lilac), c.label, null, a, { size: 29, fill: 'rgba(20,20,44,0.9)', stroke: css(PAL.lilac, 0.5) });
    T.g.restore();
  });
  const ra = smooth(seg(t, 63.2, 63.5)) * (1 - smooth(seg(t, 65.4, 65.8)));
  if (ra > 0) { T.g.save(); T.g.globalAlpha = ra; T.font(30, 800, T.BODY, 4); T.g.textAlign = 'center'; T.g.fillStyle = 'rgba(196,184,255,0.9)'; T.g.fillText('IN THE MORNING', 540, 1738); T.g.restore(); }
  grade.bloom = 0.75;
  T.line('Understand what happens', 540, 190, t, 61.8, { size: 72, weight: 800, ls: -0.5, style: 'rise', stagger: 0.018, out: 65.4, outDur: 0.3 });
  T.line('through the night.', 540, 280, t, 62.2, { size: 72, weight: 800, ls: -0.5, style: 'rise', stagger: 0.018, color: css(PAL.lilac), out: 65.45, outDur: 0.3 });
}

// SCENE 14 — the Apple ecosystem (1:06 – 1:11)
// The phone steps aside for the watch. Both show the same night, 7h 32m:
// the watch page used is the one whose demo numbers agree with the phone's.
const watch = new Watch();
scene.add(watch.group);
const WSCR = {};
for (const n of ['page-scorelight', 'page-log', 'page-nap']) WSCR[n] = tex(`/Tools/launch-video/screens/watch/${n}.webp`);
const P14 = PH12;
const flows = [0, 1, 2].map(i => { const rb = new Ribbon(90, { color: L(i === 1 ? PAL.battery : PAL.lilac).map(v => v * 1.2), color2: L([0.9, 0.92, 1.0]), width: 0.016 }); reg(rb.mesh); rb.mesh.renderOrder = 26; return rb; });
const flowDots = [0, 1, 2, 3, 4, 5].map(() => { const g = glow(L([0.8, 0.82, 1.0]), 2.4); g.material.uniforms.core.value = 3; g.renderOrder = 27; return reg(g); });
mark(66, 'watch');
cue(66.0, 'whoosh', { gain: 0.6, pan: -0.5 }); cue(66.45, 'whoosh', { gain: 0.5, pan: 0.6 }); cue(66.9, 'glass', { gain: 0.6, pan: 0.5 });
for (let b = 67.5; b < 70.5; b += 0.5) cue(b, 'data', { dur: 0.18, gain: 0.3, pan: ((b * 2) % 2 ? 0.5 : -0.5) });
cue(68.5, 'pop', { gain: 0.5 }); cue(70.6, 'whoosh', { gain: 0.55, pan: 0.6 });
const PH_L = [P14[0] - 0.42, P14[1] + 0.06, P14[2]], W_R = [P14[0] + 0.5, P14[1] - 0.22, P14[2] + 0.6];
function camEco(t) {
  const s = camSnore(66.0);
  const pos = track(t, [[66.0, s.pos], [67.0, [P14[0] + 0.04, P14[1] + 0.26, P14[2] + 6.1]], [71.0, [P14[0] - 0.12, P14[1] + 0.2, P14[2] + 5.8]]]);
  const aim = track(t, [[66.0, s.aim], [67.0, [P14[0] + 0.04, P14[1] + 0.1, P14[2] + 0.25]], [71.0, [P14[0] + 0.02, P14[1] + 0.08, P14[2] + 0.25]]]);
  return { pos, aim };
}
function sEco(t) {
  const cam = camEco(t);
  lookFrom(cam.pos, cam.aim, 0);
  bgMat.uniforms.intensity.value = 0.6; bgMat.uniforms.glowAmt.value = 0.32; bgMat.uniforms.glowPos.value.set(0.5, 0.52);
  show(stars.points); stars.mat.uniforms.opacity.value = 0.55;
  show(dust.points); dust.mat.uniforms.opacity.value = 0.9; dust.mat.uniforms.morph.value = seg(t, 0, 16);
  // the phone steps left and turns toward the watch; the night returns to its screen
  const step = eInOut5(seg(t, 66.0, 66.9));
  if (t < 70.6) {
    phone.group.position.set(lerp(P14[0], PH_L[0], step), lerp(P14[1], PH_L[1], step), P14[2]);
    phone.group.rotation.set(0, lerp(0.12, 0.3, step) + 0.03 * Math.sin(t * 0.6) * step, 0);
    phone.show(camera);
    phone.setScreen(SCR.snoreCheck, { opacity: 1 });
    phone.setScreen(SCR.sleep, { b: true, opacity: smooth(seg(t, 66.2, 66.6)) });
  }
  // the watch comes in from the right
  const land = eOutExpo(seg(t, 66.4, 67.3));
  const out = eInOut3(seg(t, 70.55, 71.3));
  watch.group.position.set(lerp(W_R[0] + 1.6, W_R[0], land) + 1.8 * out, W_R[1] + 0.02 * Math.sin(t * 0.9), lerp(W_R[2] + 1.2, W_R[2], land) - 0.8 * out);
  watch.group.rotation.set(0.08, lerp(-1.1, -0.34, land) + 0.04 * Math.sin(t * 0.7) - 0.8 * out, lerp(0.2, 0.02, land));
  watch.group.scale.setScalar(0.92);
  if (land > 0 && out < 1) watch.show(camera, WSCR['page-scorelight']);
  // and the night flows between them
  phone.group.updateMatrixWorld(); watch.group.updateMatrixWorld();
  const a = new THREE.Vector3(capX(603), capY(560), FRONT + 0.02).applyMatrix4(phone.group.matrixWorld);
  const b = new THREE.Vector3(0, 0.06, watch.FRONT + 0.02).applyMatrix4(watch.group.matrixWorld);
  const fa = smooth(seg(t, 67.2, 67.6)) * (1 - smooth(seg(t, 70.3, 70.7)));
  flows.forEach((rb, i) => {
    if (fa <= 0) return;
    show(rb.mesh);
    const lift = (i - 1) * 0.28 + 0.1, pts = [];
    for (let j = 0; j < 90; j++) { const u = j / 89, bow = Math.sin(u * Math.PI);
      pts.push([lerp(a.x, b.x, u), lerp(a.y, b.y, u) + bow * (0.35 + lift), lerp(a.z, b.z, u) + bow * 0.45]); }
    rb.set(pts);
    const ph = ((t - 67.2) * 0.9 + i * 0.33) % 1;
    rb.mat.uniforms.progress.value = 1; rb.mat.uniforms.opacity.value = 0.32 * fa; rb.mat.uniforms.head.value = 0;
    // a pulse of light rides each arc, one way and back
    [0, 1].forEach(k => {
      const d = flowDots[i * 2 + k], u = k ? 1 - ((ph + 0.5) % 1) : ph, idx = Math.min(89, Math.round(u * 89));
      show(d); d.position.set(...pts[idx]); d.scale.setScalar(0.12); d.material.uniforms.opacity.value = fa * Math.sin(u * Math.PI) * 1.2;
    });
  });
  grade.bloom = 0.72;
  // Apple Health, where the watch's night is kept
  const ha = eOutBack(seg(t, 68.5, 68.9), 1.5), hA = clamp(ha) * (1 - smooth(seg(t, 70.4, 70.8)));
  if (hA > 0) {
    T.g.save(); T.g.translate(540, 1790); T.g.scale(lerp(0.6, 1, clamp(ha)), lerp(0.6, 1, clamp(ha))); T.g.translate(-540, -1790);
    T.chip(540, 1790, css([1.0, 0.18, 0.33]), 'Apple Health', null, hA, { size: 40, fill: 'rgba(40,16,26,0.88)', stroke: 'rgba(255,70,110,0.5)' });
    T.g.restore();
  }
  T.line('Built around your', 540, 190, t, 66.6, { size: 80, weight: 800, ls: -0.5, style: 'rise', stagger: 0.02, out: 70.3, outDur: 0.3 });
  T.line('Apple ecosystem.', 540, 285, t, 66.95, { size: 80, weight: 800, ls: -0.5, style: 'rise', stagger: 0.02, color: css(PAL.lilac), out: 70.35, outDur: 0.3 });
}

// SCENE 15 — morning (1:11 – 1:16)
// A dawn rises under the night. Today's morning screen assembles: the ring
// around the app's moon draws, the bars fill.
const sun = reg(glow(L([1.0, 0.62, 0.36]), 1.6)); sun.renderOrder = -5;
const MORNING_LAYERS = [
  { crop: [0, 0, 1206, 150], t: 71.25, from: { z: 0.1, blur: 0.2 } },
  { crop: [0, 168, 1206, 162], t: 71.35, from: { y: 0.15, z: 0.2 } },
  { crop: [300, 344, 606, 212], t: 71.5, from: { z: 0.3, s: 0.85 } },
  { crop: [200, 600, 806, 800], t: 71.62, from: { z: 0.2, s: 0.95 }, sweep: [71.62, 72.6], hole: 262 },
  { crop: [353, 750, 500, 500], t: 71.75, from: { z: 0.4, s: 0.7, blur: 0.6 }, radiusPx: 250 },
  { crop: [100, 1448, 1006, 232], t: 72.25, from: { y: -0.1, z: 0.25 } },
  { crop: [40, 1748, 1126, 352], t: 72.4, from: { z: 0.2 }, wipe: [72.45, 73.25] },
  { crop: [40, 2172, 1126, 140], t: 72.85, from: { y: -0.1, z: 0.2 } },
  { crop: [70, 2304, 1066, 210], t: 72.95, from: { y: -0.2, z: 0.3, s: 0.9 }, radiusPx: 105 }
];
mark(71, 'dawn');
cue(71.0, 'swell', { dur: 1.4, gain: 0.55 }); cue(71.62, 'sweep', { dur: 1.0, gain: 0.45 }); cue(72.45, 'data', { dur: 0.8, gain: 0.35 });
cue(73.4, 'glass', { gain: 0.55 }); cue(74.0, 'tick', { gain: 0.4 }); cue(74.5, 'tick', { gain: 0.4 }); cue(75.6, 'rev', { dur: 0.4, gain: 0.5 });
function camDawn(t) {
  const s = camEco(71.0);
  const pos = track(t, [[71.0, s.pos], [72.0, [P14[0] + 0.1, P14[1] + 0.36, P14[2] + 5.6]], [76.0, [P14[0] - 0.08, P14[1] + 0.3, P14[2] + 5.1]]]);
  const aim = track(t, [[71.0, s.aim], [72.0, [P14[0], P14[1] + 0.3, P14[2]]], [76.0, [P14[0], P14[1] + 0.28, P14[2]]]]);
  return { pos, aim };
}
function sDawn(t) {
  const cam = camDawn(t);
  lookFrom(cam.pos, cam.aim, 0);
  const dawn = smooth(seg(t, 70.9, 74.2));
  bgMat.uniforms.intensity.value = lerp(0.6, 0.72, dawn); bgMat.uniforms.dawn.value = dawn * 0.95;
  bgMat.uniforms.glowAmt.value = 0.3; bgMat.uniforms.glowPos.value.set(0.5, lerp(0.5, 0.35, dawn));
  bgMat.uniforms.glowCol.value.set(...L(mix([0.30, 0.38, 0.92], [0.85, 0.5, 0.45], dawn * 0.6)));
  show(stars.points); stars.mat.uniforms.opacity.value = 0.55 * (1 - dawn * 0.6);
  show(dust.points); dust.mat.uniforms.opacity.value = 0.9; dust.mat.uniforms.morph.value = seg(t, 0, 16);
  show(sun); { const p = new THREE.Vector3(0, -1.9 + 0.35 * dawn, -5).applyMatrix4(camera.matrixWorld); sun.position.copy(p); sun.quaternion.copy(camera.quaternion);
    sun.scale.set(9, 6, 1); sun.material.uniforms.opacity.value = 0.5 * dawn; }
  // the phone returns to the middle
  const k = eInOut5(seg(t, 70.6, 71.5));
  phone.group.position.set(lerp(PH_L[0], P14[0], k), lerp(PH_L[1], P14[1], k), P14[2]);
  phone.group.rotation.set(0, lerp(0.3 + 0.03 * Math.sin(70.6 * 0.6), -0.04 + 0.03 * Math.sin(t * 0.6), k), 0);
  phone.show(camera);
  const wake = smooth(seg(t, 71.1, 71.45));
  ground(SCR['today-morning'], wake);
  if (t < 71.45) phone.setScreen(SCR.sleep, { b: true, opacity: 1 - wake });
  for (const Ly of MORNING_LAYERS) {
    const kk = eOutExpo(seg(t, Ly.t, Ly.t + 0.62));
    if (kk <= 0) continue;
    const m = phone.layer(SCR['today-morning'], Ly.crop, { radiusPx: Ly.radiusPx || 0 }), u = m.material.uniforms;
    if (Ly.sweep) { u.revealMode.value = 2; u.revealCenter.value.set(0.5, 0.5); u.revealSoft.value = 0.02;
      u.reveal.value = lerp(0, 1.02, eInOut3(seg(t, Ly.sweep[0], Ly.sweep[1]))); }
    if (Ly.hole) u.hole.value.set(0.5, 0.5, Ly.hole / CAP_W * SCREEN_W);
    if (Ly.wipe) { u.revealMode.value = 1; u.revealDir.value.set(1, 0); u.revealSoft.value = 0.1;
      u.reveal.value = lerp(-0.1, 1.1, eInOut3(seg(t, Ly.wipe[0], Ly.wipe[1]))); }
    pose(m, kk, Ly.from);
  }
  const full = smooth(seg(t, 73.45, 73.85));
  if (full > 0) phone.setScreen(SCR['today-morning'], { b: true, opacity: full });
  grade.bloom = 0.7;
  T.line('Wake up', 540, 200, t, 72.2, { size: 92, weight: 800, ls: -0.5, style: 'rise', stagger: 0.025, out: 75.35, outDur: 0.3 });
  T.line('knowing more.', 540, 305, t, 72.6, { size: 92, weight: 800, ls: -0.5, style: 'rise', stagger: 0.025, color: css([1.0, 0.8, 0.62]), out: 75.4, outDur: 0.3 });
}

// SCENE 16 — the montage (1:16 – 1:22)
// Eight more of the app's screens, one every beat and a half, each cut an
// iris opening from the circle at the heart of the next screen.
const MONTAGE = [
  { t: 76.0, map: 'bodyClock', at: [603, 860], label: 'Body Clock' },
  { t: 76.75, map: 'today-day', at: [603, 930], label: 'Recovery' },
  { t: 77.5, map: 'report', at: [603, 580], label: 'Weekly Report' },
  { t: 78.25, map: 'nightHistory', at: [603, 470], label: 'Past Nights' },
  { t: 79.0, map: 'tomorrow', at: [603, 560], label: 'Tomorrow' },
  { t: 79.75, map: 'nap', at: [603, 1060], label: 'Naps' },
  { t: 80.5, map: 'patterns', at: [603, 1000], label: 'Your Patterns' },
  { t: 81.25, map: 'coach-ask-night', at: [603, 1000], label: 'Ask about your sleep' }
];
mark(76, 'montage');
MONTAGE.forEach((m, i) => { cue(m.t, i % 2 ? 'snap' : 'tick', { gain: 0.55, pan: (i % 2 ? 0.3 : -0.3) }); cue(m.t, 'whoosh', { gain: 0.3, pan: (i % 2 ? -0.5 : 0.5) }); });
function camMontage(t) {
  const s = camDawn(76.0);
  const i = MONTAGE.findLastIndex(m => t >= m.t);
  const kick = i >= 0 ? Math.exp(-(t - MONTAGE[i].t) * 7) : 0;
  const base = [P14[0] + 0.02, P14[1] + 0.26, P14[2] + 4.75 - 0.18 * kick];
  return { pos: track(t, [[76.0, s.pos], [76.35, base], [82.0, base]].map((k, j) => j ? [k[0], base] : k)), aim: [P14[0], P14[1] + 0.26, P14[2]] };
}
function sMontage(t) {
  const cam = camMontage(t);
  lookFrom(cam.pos, cam.aim, 0);
  const dawn = 1 - smooth(seg(t, 76.0, 76.9));
  bgMat.uniforms.intensity.value = lerp(0.62, 0.72, dawn); bgMat.uniforms.dawn.value = 0.95 * dawn;
  bgMat.uniforms.glowCol.value.set(...L(mix([0.30, 0.38, 0.92], [0.85, 0.5, 0.45], dawn * 0.6)));
  if (dawn > 0) { show(sun); const sp = new THREE.Vector3(0, -1.55, -5).applyMatrix4(camera.matrixWorld); sun.position.copy(sp); sun.quaternion.copy(camera.quaternion);
    sun.scale.set(9, 6, 1); sun.material.uniforms.opacity.value = 0.5 * dawn; } bgMat.uniforms.glowAmt.value = 0.3; bgMat.uniforms.glowPos.value.set(0.5, 0.5);
  show(stars.points); stars.mat.uniforms.opacity.value = 0.55;
  show(dust.points); dust.mat.uniforms.opacity.value = 0.9; dust.mat.uniforms.morph.value = seg(t, 0, 16);
  const i = MONTAGE.findLastIndex(m => t >= m.t);
  const cur = MONTAGE[i], prev = i > 0 ? MONTAGE[i - 1] : { map: 'today-morning' };
  const k = eOut3(seg(t, cur.t, cur.t + 0.24));
  phone.group.position.set(...P14);
  const snap = (i % 2 ? 1 : -1) * 0.08 * Math.exp(-(t - cur.t) * 5);
  phone.group.rotation.set(0.02, -0.03 + snap, snap * 0.2);
  phone.show(camera);
  phone.setScreen(SCR[prev.map], { opacity: 1 });
  const s = phone.setScreen(SCR[cur.map], { b: true, opacity: 1 }), u = s.material.uniforms;
  u.revealMode.value = 3; u.revealCenter.value.set(cur.at[0] / CAP_W, 1 - cur.at[1] / CAP_H); u.revealSoft.value = 0.04; u.reveal.value = lerp(0, 1.05, k);
  // a ring of light opens with each cut
  phone.group.updateMatrixWorld();
  if (k < 1) {
    show(moonRing); moonRing.position.copy(new THREE.Vector3(capX(cur.at[0]), capY(cur.at[1]), FRONT + 0.02).applyMatrix4(phone.group.matrixWorld));
    moonRing.quaternion.copy(phone.group.quaternion);
    moonRing.scale.setScalar(lerp(0.1, 2.6, k)); moonRing.material.uniforms.opacity.value = (1 - k) * 1.2; moonRing.material.uniforms.progress.value = 1; moonRing.material.uniforms.glowAmt.value = 0.5;
  }
  grade.bloom = 0.72;
  const la = smooth(seg(t, cur.t + 0.05, cur.t + 0.2)) * (1 - smooth(seg(t, cur.t + 0.62, cur.t + 0.74)));
  if (la > 0) {
    T.g.save(); T.g.globalAlpha = la; T.g.textAlign = 'center'; T.font(cur.label.length > 14 ? 60 : 76, 800, T.HEAD, -0.5); T.g.fillStyle = '#f4f5fb';
    T.g.shadowColor = 'rgba(0,0,0,0.5)'; T.g.shadowBlur = 24; T.g.fillText(cur.label, 540, 1805 - 18 * (1 - la)); T.g.restore();
  }
}

// SCENE 17 — one place (1:22 – 1:25)
// The camera pulls back, and everything the film has shown is there at once.
const P17 = P14;
const iconTex = tex('/Zoon/Assets.xcassets/AppIcon.appiconset/icon-1024.png');
const icon = reg(card(iconTex, { width: 0.5 })); icon.renderOrder = 30;
setCardSize(icon, 0.5, 0.5); icon.material.uniforms.radius.value = 0.5 * 0.2237;
mark(82, 'pullback');
cue(82.0, 'whoosh', { gain: 0.8, pan: 0 }); cue(82.05, 'boom', { gain: 0.7 }); cue(82.4, 'shimmer', { gain: 0.5 }); cue(83.6, 'glass', { gain: 0.55 });
const JOURNEY = [
  { kind: 'watch', at: [1.0, -0.62, 0.5], rot: [0.06, -0.42, 0.03] },
  { kind: 'ring', at: [-0.98, 1.08, -0.55], s: 0.36 },
  { kind: 'card', card: () => INSIGHT_CARDS[2].m, w: 0.9, at: [-1.05, -0.3, -0.35], rot: [0.02, 0.38, 0] },
  { kind: 'card', card: () => INSIGHT_CARDS[0].m, w: 0.7, at: [1.08, 0.98, -0.85], rot: [0.03, -0.36, 0.02] },
  { kind: 'card', card: () => planCard, w: 0.82, at: [-0.78, -1.38, 0.35], rot: [-0.06, 0.3, 0] },
  { kind: 'card', card: () => toolCards[2], w: 0.5, at: [1.12, 0.2, -1.25], rot: [0, -0.5, 0] },
  { kind: 'card', card: () => toolCards[0], w: 0.46, at: [-1.28, 0.55, -1.5], rot: [0, 0.55, 0] }
];
function camJourney(t) {
  const s = camMontage(82.0);
  const pull = eOutExpo(seg(t, 82.0, 83.3));
  const d = lerp(4.75, 9.6, pull) + 0.4 * seg(t, 83.3, 85.0);
  const orbit = 0.1 * Math.sin(seg(t, 82, 85) * Math.PI * 0.5);
  const aim = [P17[0], P17[1] + 0.2, P17[2]];
  return { pos: [aim[0] + Math.sin(orbit) * d, aim[1] + 0.1 * pull, aim[2] + Math.cos(orbit) * d], aim };
}
function sJourney(t) {
  const cam = camJourney(t);
  lookFrom(cam.pos, cam.aim, 0);
  bgMat.uniforms.intensity.value = 0.62; bgMat.uniforms.glowAmt.value = 0.34; bgMat.uniforms.glowPos.value.set(0.5, 0.56);
  show(stars.points); stars.mat.uniforms.opacity.value = 0.6;
  show(dust.points); dust.mat.uniforms.opacity.value = 0.9; dust.mat.uniforms.morph.value = seg(t, 0, 16);
  const away = eInOut3(seg(t, 84.55, 85.4));      // everything leaves for the moon
  const arrive = eOutExpo(seg(t, 82.0, 83.1));
  // the moon, behind it all
  show(moon); const b = backlightSpot(P17, 7.5, 1.1);
  moon.position.set(...b); moon.scale.setScalar(1.8); moon.rotation.set(0.05, -0.25 + t * 0.012, 0.02);
  moonMat.uniforms.lit.value = 0.62; moonMat.uniforms.blur.value = 0.5; moonMat.uniforms.opacity.value = 1;
  halo.material.uniforms.opacity.value = 0.18; halo2.material.uniforms.opacity.value = 0.1;
  // the phone at the centre, on the score's breakdown
  phone.group.position.set(P17[0], P17[1] - 3 * eIn3(away), P17[2] - 2 * away);
  phone.group.rotation.set(0.02, 0.08 * Math.sin(t * 0.5), 0);
  phone.show(camera);
  phone.setScreen(SCR['coach-ask-night'], { opacity: 1 - smooth(seg(t, 82.0, 82.35)) });
  phone.setScreen(SCR['today-breakdown'], { b: true, opacity: smooth(seg(t, 82.0, 82.35)) });
  JOURNEY.forEach((j, i) => {
    const k = clamp(arrive * 1.3 - i * 0.05) * (1 - away);
    if (k <= 0) return;
    const out = 1 + away * 1.5, drift = [Math.sin(t * 0.5 + i) * 0.03, Math.cos(t * 0.45 + i * 1.3) * 0.03];
    const p = [P17[0] + j.at[0] * lerp(0.4, 1, arrive) * out + drift[0], P17[1] + j.at[1] * lerp(0.4, 1, arrive) * out + drift[1], P17[2] + j.at[2]];
    if (j.kind === 'watch') {
      watch.group.position.set(...p); watch.group.rotation.set(...j.rot); watch.group.scale.setScalar(0.72 * k);
      watch.show(camera, WSCR['page-scorelight']);
    } else if (j.kind === 'ring') {
      ringGroup.position.set(...p); ringGroup.scale.setScalar(j.s * k); ringGroup.rotation.set(0.2, 0.3 + t * 0.1, 0); ringGroup.updateMatrixWorld();
      drawRing(1, 0, 7.2, k);
    } else {
      const m = show(j.card()), u = m.material.uniforms;
      m.position.set(...p); m.rotation.set(...j.rot);
      const h = j.w * (m === planCard ? PLAN.crop[3] / PLAN.crop[2] : m.userData.h ? m.userData.h / m.userData.w : TOOL_H / TOOL_W);
      setCardSize(m, j.w, h); u.opacity.value = k; u.blur.value = 0; u.bright.value = 1.05;
      if (j.card === JOURNEY[5].card || j.card === JOURNEY[6].card) { u.map.value = SCR[TOOLS[j === JOURNEY[5] ? 2 : 0].map]; u.hasMap.value = 1; u.radius.value = j.w * 0.137; }
    }
  });
  grade.bloom = 0.72;
  T.line('Your entire', 540, 200, t, 82.4, { size: 92, weight: 800, ls: -0.5, style: 'rise', stagger: 0.025, out: 84.55, outDur: 0.3 });
  T.line('sleep journey.', 540, 305, t, 82.7, { size: 92, weight: 800, ls: -0.5, style: 'rise', stagger: 0.025, out: 84.6, outDur: 0.3 });
  T.line('One place.', 540, 1760, t, 83.6, { size: 104, weight: 900, ls: -0.5, style: 'blur', by: 'word', stagger: 0.1, dur: 0.5, color: css(PAL.lilac), glow: 0.2, out: 84.65, outDur: 0.3 });
}

// SCENE 18 — the moon (1:25 – 1:28)
// Everything else goes. One third of a life, in one image.
const M18 = [P17[0], P17[1] + 0.3, P17[2] - 1.2];
mark(85, 'moon'); mark(88, 'logo');
cue(84.6, 'rev', { dur: 0.8, gain: 0.6 }); cue(85.45, 'tone', { gain: 0.5 }); cue(86.95, 'glint', { gain: 0.6 }); cue(87.6, 'riser', { dur: 0.4, gain: 0.6 });
function camMoon(t) {
  const s = camJourney(85.0);
  const pos = track(t, [[85.0, s.pos], [85.9, [M18[0], M18[1], M18[2] + 5.4]], [88.0, [M18[0], M18[1], M18[2] + 5.0]], [90.0, [M18[0], M18[1], M18[2] + 4.9]]]);
  const aim = track(t, [[85.0, s.aim], [85.9, M18], [90.0, M18]]);
  return { pos, aim };
}
// the moon's light swings round behind it, leaving the app icon's crescent
const MOON_SUN_FULL = new THREE.Vector3(0.25, 0.15, 1).normalize(), MOON_SUN_CRESCENT = new THREE.Vector3(-0.92, 0.3, -0.26).normalize();
function sMoon(t) {
  const cam = camMoon(t);
  lookFrom(cam.pos, cam.aim, 0);
  bgMat.uniforms.intensity.value = lerp(0.62, 0.5, seg(t, 85, 86)); bgMat.uniforms.glowAmt.value = 0.34; bgMat.uniforms.glowPos.value.set(0.5, 0.5);
  show(stars.points); stars.mat.uniforms.opacity.value = 0.6;
  show(dust.points); dust.mat.uniforms.opacity.value = 0.7; dust.mat.uniforms.morph.value = seg(t, 0, 16);
  // from the backlight behind the journey to the middle of the frame, in focus
  const come = eInOut5(seg(t, 84.9, 86.0));
  const from = backlightSpot(P17, 7.5, 1.1);
  show(moon);
  const toIcon = eInOut5(seg(t, 88.15, 88.85));
  const iconAt = [M18[0], M18[1] + 0.3, M18[2]];
  // the crescent's own circle sits a little right of the icon's centre
  moon.position.set(lerp(lerp(from[0], M18[0], come), iconAt[0] + 0.043, toIcon), lerp(lerp(from[1], M18[1], come), iconAt[1], toIcon), lerp(from[2], M18[2], come));
  moon.scale.setScalar(lerp(lerp(1.8, 0.62, come), 0.156, toIcon) * (1 + 0.02 * seg(t, 86, 88)));
  moon.rotation.set(0.05, -0.25 + t * 0.012, 0.02);
  const cres = eInOut3(seg(t, 87.55, 88.35));
  moonMat.uniforms.sun.value.copy(MOON_SUN_FULL).lerp(MOON_SUN_CRESCENT, cres).normalize();
  moonMat.uniforms.lit.value = lerp(lerp(0.62, 1.25, come), 1.6, cres); moonMat.uniforms.blur.value = 0.5 * (1 - come);
  moonMat.uniforms.earth.value = 0.03 * (1 - cres);
  // it pales toward the icon's white as it becomes the crescent
  moonMat.uniforms.tint.value.set(1, 1, 1);
  moonMat.uniforms.opacity.value = 1 - smooth(seg(t, 88.6, 88.9));
  if (moonMat.uniforms.opacity.value < 0.005) moon.visible = false;
  halo.material.uniforms.opacity.value = lerp(0.18, 0.3, come) * (1 - toIcon); halo2.material.uniforms.opacity.value = lerp(0.1, 0.16, come) * (1 - toIcon);
  grade.flash = 0.05 * Math.exp(-Math.pow((t - 88.0) / 0.07, 2));
  // the icon itself
  const ia = smooth(seg(t, 88.45, 88.85));
  if (ia > 0) {
    show(icon); icon.position.set(iconAt[0], iconAt[1], iconAt[2] + 0.2); icon.rotation.set(0, 0, 0);
    icon.material.uniforms.opacity.value = ia; icon.material.uniforms.rim.value = 0.1; icon.material.uniforms.bright.value = 1.1;
  }
  grade.bloom = 0.75;
  T.line('Sleep is one-third', 540, 1530, t, 85.45, { size: 84, weight: 800, ls: -0.5, style: 'rise', stagger: 0.02, out: 86.7, outDur: 0.3 });
  T.line('of your life.', 540, 1630, t, 85.8, { size: 84, weight: 800, ls: -0.5, style: 'rise', stagger: 0.02, out: 86.75, outDur: 0.3 });
  T.line('Understand it.', 540, 1590, t, 86.95, { size: 96, weight: 900, ls: -0.5, style: 'blur', by: 'word', stagger: 0.12, dur: 0.5, color: css(PAL.lilac), glow: 0.2, out: 87.75, outDur: 0.3 });
  // SCENE 19 — the lockup (1:28 – 1:30)
  const tr = eOut5(seg(t, 88.55, 89.6));
  T.line('ZOON', 540, 1110, t, 88.55, { size: 150, weight: 800, ls: lerp(64, 26, tr), style: 'blur', stagger: 0.06, dur: 0.8, glow: 0.22 });
  T.line('Sleep smarter. Live better.', 540, 1230, t, 88.95, { size: 54, weight: 700, ls: 0.3, style: 'rise', stagger: 0.012, dur: 0.6 });
  T.line('Coming to the App Store', 540, 1640, t, 89.2, { size: 42, weight: 700, fam: T.BODY, ls: 1.5, style: 'fade', by: 'word', stagger: 0.06, dur: 0.5, color: 'rgba(214,216,232,0.92)' });
  T.line('App screens show sample data.', 540, 1850, t, 88.9, { size: 26, weight: 500, fam: T.BODY, ls: 0.4, style: 'fade', by: 'word', stagger: 0.05, dur: 0.4, color: 'rgba(214,216,232,0.6)' });
}

const SCENES = [
  [0, 8.0, sHook],
  [7.95, 13.6, sIntro],
  [13.0, 18.0, sNight],
  [18.0, 23.0, sScore],
  [23.0, 29.0, sStages],
  [28.85, 34.0, sPatterns],
  [33.6, 39.0, sInsights],
  [38.9, 45.0, sCoach],
  [45.0, 50.0, sTonight],
  [50.0, 56.0, sTools],
  [55.85, 61.0, sSlow],
  [61.0, 66.0, sSnore],
  [66.0, 71.35, sEco],
  [70.6, 76.0, sDawn],
  [76.0, 82.0, sMontage],
  [82.0, 85.4, sJourney],
  [85.0, 90.01, sMoon]
];

// ================================================================ frame
async function render(t) {
  T.clear();
  for (const o of all) o.visible = false;
  phone.reset(); watch.group.visible = false; watch.group.scale.setScalar(1); backLight.intensity = 0; rimLight.intensity = 0; moonMat.uniforms.blur.value = 0; moonMat.uniforms.lit.value = 1.35;
  moonMat.uniforms.sun.value.set(0.55, 0.2, 0.9).normalize(); moonMat.uniforms.earth.value = 0.04; moonMat.uniforms.opacity.value = 1; moonMat.uniforms.tint.value.set(1, 1, 1);
  bgMat.uniforms.glowCol.value.set(...L([0.30, 0.38, 0.92]));
  resetFrame(t);
  for (const [a, b, f] of SCENES) if (t >= a && t < b) f(t);
  drawFrame(t);
}

window.DURATION = DURATION; window.BPM = BPM; window.CUES = CUES; window.MUSIC = MUSIC; window.GPU = GPU;
window.render = render;
(async () => {
  await Promise.all(['300', '600', '800', '900'].map(w => document.fonts.load(`${w} 100px Nunito`)));
  await Promise.all(['400', '500', '600', '700', '800'].map(w => document.fonts.load(`${w} 100px Manrope`)));
  await texturesLoaded();
  drawAlarmTile();
  // warm every texture on the GPU so the first real frame is not late
  render(0); render(11.5); render(16.8); render(67.5); render(88.9);
  window.READY = true;
})();
