// The film's engine: one WebGL renderer, a linear HDR scene target, a bloom
// written for this film (threshold, mip chain, tent upsample), and a final
// grade (ACES, vignette, dither) drawn to the canvas. Everything is a pure
// function of time: render(t) poses the world for t and draws one frame, so
// any frame can be drawn in any order and every render is identical.
import * as THREE from '../vendor/three.module.js';
export { THREE };

export const W = 1080, H = 1920;
export const QUERY = new URLSearchParams(location.search);
export const CLEAN = QUERY.get('clean') === '1';
export const DPR = window.devicePixelRatio || 1;

// ---------------------------------------------------------------- maths
export const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
export const lerp = (a, b, k) => a + (b - a) * k;
export const seg = (t, a, b) => clamp((t - a) / (b - a));
export const smooth = k => k * k * (3 - 2 * k);
export const smoother = k => k * k * k * (k * (k * 6 - 15) + 10);
export const eOut3 = k => 1 - Math.pow(1 - k, 3);
export const eOut5 = k => 1 - Math.pow(1 - k, 5);
export const eOutExpo = k => (k >= 1 ? 1 : 1 - Math.pow(2, -10 * k));
export const eIn3 = k => k * k * k;
export const eInExpo = k => (k <= 0 ? 0 : Math.pow(2, 10 * k - 10));
export const eInOut3 = k => (k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2);
export const eInOut5 = k => (k < 0.5 ? 16 * k ** 5 : 1 - Math.pow(-2 * k + 2, 5) / 2);
export const eInOutExpo = k => (k <= 0 ? 0 : k >= 1 ? 1 : k < 0.5 ? Math.pow(2, 20 * k - 10) / 2 : (2 - Math.pow(2, -20 * k + 10)) / 2);
export const eOutBack = (k, s = 1.7) => 1 + (s + 1) * Math.pow(k - 1, 3) + s * Math.pow(k - 1, 2);
// A damped spring settling on 1: the overshoot lives in `bounce`.
export const spring = (k, bounce = 0.35, freq = 2.2) => {
  if (k <= 0) return 0; if (k >= 1) return 1;
  const d = 6.5 * (1 - bounce) + 2.5;
  return 1 - Math.exp(-d * k) * Math.cos(freq * Math.PI * k * (1 + bounce));
};
export const mix3 = (a, b, k) => [lerp(a[0], b[0], k), lerp(a[1], b[1], k), lerp(a[2], b[2], k)];
// A smooth path through keyframes [[t, v], ...]: non-uniform Catmull-Rom,
// so a camera passes through every key without stopping at it. Values may be
// numbers or arrays.
export function track(t, keys) {
  const n = keys.length;
  if (t <= keys[0][0]) return keys[0][1];
  if (t >= keys[n - 1][0]) return keys[n - 1][1];
  let i = 0; while (t > keys[i + 1][0]) i++;
  const [t0, p0] = keys[i], [t1, p1] = keys[i + 1];
  const h = t1 - t0, u = (t - t0) / h;
  const slope = (a, b) => (a && b) ? (Array.isArray(a[1]) ? a[1].map((v, j) => (b[1][j] - v) / (b[0] - a[0])) : (b[1] - a[1]) / (b[0] - a[0])) : null;
  const tan = j => { const L = j > 0 ? keys[j - 1] : null, R = j < n - 1 ? keys[j + 1] : null;
    if (!L || !R) return Array.isArray(keys[j][1]) ? keys[j][1].map(() => 0) : 0;
    return slope(L, R); };
  const m0 = tan(i), m1 = tan(i + 1);
  const h00 = 2 * u ** 3 - 3 * u ** 2 + 1, h10 = u ** 3 - 2 * u ** 2 + u, h01 = -2 * u ** 3 + 3 * u ** 2, h11 = u ** 3 - u ** 2;
  const f = (a, b, ma, mb) => h00 * a + h10 * h * ma + h01 * b + h11 * h * mb;
  return Array.isArray(p0) ? p0.map((v, j) => f(v, p1[j], m0[j], m1[j])) : f(p0, p1, m0, m1);
}

// Deterministic noise for small motion: value noise on a hashed lattice.
const hash1 = n => { const s = Math.sin(n * 127.1) * 43758.5453; return s - Math.floor(s); };
export const vnoise = x => { const i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f); return lerp(hash1(i), hash1(i + 1), u) * 2 - 1; };
export function rng(seed) {
  let s = seed >>> 0;
  return () => { s = (s + 0x6D2B79F5) >>> 0; let t = s; t = Math.imul(t ^ (t >>> 15), 1 | t); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}

// ---------------------------------------------------------------- palette
// The app's own colours (Shared/Theme.swift), linear-light for the GPU.
const srgbToLinear = c => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
export const lin = rgb => rgb.map(srgbToLinear);
export const PAL = {
  ground0: [0.024, 0.031, 0.070], ground1: [0.043, 0.055, 0.118], ground2: [0.055, 0.070, 0.160],
  sleep: [0.424, 0.361, 0.906], battery: [0.153, 0.851, 0.753], hrv: [1.0, 0.435, 0.78],
  deep: [0.294, 0.235, 0.780], rem: [0.545, 0.400, 1.0], core: [0.290, 0.600, 0.980], awake: [1.0, 0.624, 0.263],
  moon: [0.93, 0.95, 1.0], lilac: [0.77, 0.72, 1.0], calm: [0.25, 0.84, 0.63], amber: [1.0, 0.64, 0.24]
};
export const css = (rgb, a = 1) => `rgba(${Math.round(rgb[0] * 255)},${Math.round(rgb[1] * 255)},${Math.round(rgb[2] * 255)},${a})`;

// ---------------------------------------------------------------- renderer
export const canvas = document.getElementById('gl');
export const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: false, preserveDrawingBuffer: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(DPR);
renderer.setSize(W, H, false);
canvas.style.width = W + 'px'; canvas.style.height = H + 'px';
renderer.autoClear = false;
export const RW = Math.round(W * DPR), RH = Math.round(H * DPR);
export const GPU = (() => {
  const gl = renderer.getContext(); const ext = gl.getExtension('WEBGL_debug_renderer_info');
  return ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : 'unknown';
})();

export const scene = new THREE.Scene();
export const camera = new THREE.PerspectiveCamera(32, W / H, 0.05, 400);

const hdr = new THREE.WebGLRenderTarget(RW, RH, { type: THREE.HalfFloatType, samples: 4, depthBuffer: true });
hdr.texture.colorSpace = THREE.LinearSRGBColorSpace;

// Studio environment for the metal and glass: a dark sphere with a few soft
// panels, prefiltered once. Reflections are what make a device look real.
{
  const env = new THREE.Scene();
  const sky = new THREE.Mesh(new THREE.SphereGeometry(50, 32, 16), new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false,
    vertexShader: 'varying vec3 vP; void main(){ vP = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.); }',
    fragmentShader: `varying vec3 vP; void main(){ vec3 d = normalize(vP);
      vec3 c = mix(vec3(0.010,0.012,0.028), vec3(0.05,0.055,0.11), smoothstep(-0.3,1.0,d.y));
      c += vec3(0.6,0.62,0.9) * pow(max(0.,d.y),24.) * 2.0;
      gl_FragColor = vec4(c,1.); }`
  }));
  env.add(sky);
  const panel = (w, h, pos, rot, col) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: new THREE.Color().setRGB(...col), side: THREE.DoubleSide }));
    m.position.set(...pos); m.rotation.set(...rot); env.add(m);
  };
  panel(30, 6, [0, 26, -6], [Math.PI / 2, 0, 0], [3.2, 3.3, 3.8]);          // softbox overhead
  panel(4, 24, [-24, 4, 6], [0, Math.PI / 2, 0], [1.6, 1.5, 2.2]);          // cool strip left
  panel(4, 24, [24, 2, -4], [0, -Math.PI / 2, 0], [1.9, 1.5, 1.2]);         // warm strip right
  panel(18, 3, [0, -10, 22], [0, Math.PI, 0], [0.5, 0.52, 0.8]);            // low fill front
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(env, 0.035).texture;
}

// ---------------------------------------------------------------- full-screen passes
const fsCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
const fsScene = new THREE.Scene();
const fsQuad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2));
fsQuad.frustumCulled = false; fsScene.add(fsQuad);
const VS_FS = 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0., 1.); }';
function runPass(material, target) {
  fsQuad.material = material; renderer.setRenderTarget(target); renderer.render(fsScene, fsCam);
}
const fsMat = (frag, uniforms) => new THREE.ShaderMaterial({ vertexShader: VS_FS, fragmentShader: frag, uniforms, depthTest: false, depthWrite: false });

// Bloom: a soft-knee threshold at half resolution, then a mip chain down and
// back up with a tent filter (the approach of the Call of Duty presentations).
const LEVELS = 6;
const rt = (w, h) => { const r = new THREE.WebGLRenderTarget(w, h, { type: THREE.HalfFloatType, depthBuffer: false }); r.texture.minFilter = THREE.LinearFilter; r.texture.magFilter = THREE.LinearFilter; return r; };
const down = [], up = [];
for (let i = 0; i < LEVELS; i++) {
  const w = Math.max(2, Math.round(RW / Math.pow(2, i + 1))), h = Math.max(2, Math.round(RH / Math.pow(2, i + 1)));
  down.push(rt(w, h)); up.push(rt(w, h));
}
const prefilter = fsMat(`uniform sampler2D tSrc; uniform vec2 texel; uniform float threshold, knee; varying vec2 vUv;
  vec3 s(vec2 o){ return texture2D(tSrc, vUv + o * texel).rgb; }
  void main(){
    vec3 c = (s(vec2(-1.,-1.)) + s(vec2(1.,-1.)) + s(vec2(-1.,1.)) + s(vec2(1.,1.))) * 0.25;
    float br = max(c.r, max(c.g, c.b));
    float rq = clamp(br - threshold + knee, 0., 2. * knee); rq = rq * rq / (4. * knee + 1e-4);
    float w = max(rq, br - threshold) / max(br, 1e-4);
    gl_FragColor = vec4(min(c * w, vec3(40.)), 1.);
  }`, { tSrc: { value: null }, texel: { value: new THREE.Vector2() }, threshold: { value: 0.9 }, knee: { value: 0.5 } });
const downMat = fsMat(`uniform sampler2D tSrc; uniform vec2 texel; varying vec2 vUv;
  vec3 s(vec2 o){ return texture2D(tSrc, vUv + o * texel).rgb; }
  void main(){
    vec3 a = s(vec2(-2.,2.)), b = s(vec2(0.,2.)), c = s(vec2(2.,2.));
    vec3 d = s(vec2(-2.,0.)), e = s(vec2(0.,0.)), f = s(vec2(2.,0.));
    vec3 g = s(vec2(-2.,-2.)), h = s(vec2(0.,-2.)), i = s(vec2(2.,-2.));
    vec3 j = s(vec2(-1.,1.)), k = s(vec2(1.,1.)), l = s(vec2(-1.,-1.)), m = s(vec2(1.,-1.));
    vec3 o = e * 0.125 + (a + c + g + i) * 0.03125 + (b + d + f + h) * 0.0625 + (j + k + l + m) * 0.125;
    gl_FragColor = vec4(o, 1.);
  }`, { tSrc: { value: null }, texel: { value: new THREE.Vector2() } });
const upMat = fsMat(`uniform sampler2D tSrc, tBase; uniform vec2 texel; uniform float radius; varying vec2 vUv;
  vec3 s(vec2 o){ return texture2D(tSrc, vUv + o * texel * radius).rgb; }
  void main(){
    vec3 o = s(vec2(0.,0.)) * 4. + (s(vec2(-1.,0.)) + s(vec2(1.,0.)) + s(vec2(0.,1.)) + s(vec2(0.,-1.))) * 2.
           + s(vec2(-1.,-1.)) + s(vec2(1.,-1.)) + s(vec2(-1.,1.)) + s(vec2(1.,1.));
    gl_FragColor = vec4(o / 16. + texture2D(tBase, vUv).rgb, 1.);
  }`, { tSrc: { value: null }, tBase: { value: null }, texel: { value: new THREE.Vector2() }, radius: { value: 1.0 } });

// The grade: exposure, ACES (the Hill fit), a touch of cool in the shadows,
// a vignette, dither to keep dark gradients from banding, and optional grain.
export const grade = {
  exposure: 1.0, bloom: 0.6, vignette: 0.55, fade: 0.0, fadeColor: [0, 0, 0], grain: CLEAN ? 0.0 : 0.012,
  lift: [0.004, 0.006, 0.014], saturation: 1.0, contrast: 1.0, chroma: 0.0, flash: 0.0
};
const finalMat = fsMat(`uniform sampler2D tScene, tBloom; uniform float exposure, bloom, vignette, fade, grain, time, saturation, contrast, chroma, flash;
  uniform vec3 fadeColor, lift; uniform vec2 res; varying vec2 vUv;
  vec3 RRTAndODTFit(vec3 v){ vec3 a = v * (v + 0.0245786) - 0.000090537; vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081; return a / b; }
  vec3 aces(vec3 c){
    const mat3 i = mat3(0.59719, 0.07600, 0.02840, 0.35458, 0.90834, 0.13383, 0.04823, 0.01566, 0.83777);
    const mat3 o = mat3(1.60475, -0.10208, -0.00327, -0.53108, 1.10813, -0.07276, -0.07367, -0.00605, 1.07602);
    return clamp(o * RRTAndODTFit(i * c), 0., 1.);
  }
  float h12(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
  vec3 toSRGB(vec3 c){ return mix(c * 12.92, 1.055 * pow(c, vec3(1. / 2.4)) - 0.055, step(0.0031308, c)); }
  void main(){
    vec2 d = vUv - 0.5;
    vec3 c;
    if (chroma > 0.) {
      vec2 off = d * chroma * 0.012;
      c = vec3(texture2D(tScene, vUv - off).r, texture2D(tScene, vUv).g, texture2D(tScene, vUv + off).b);
    } else c = texture2D(tScene, vUv).rgb;
    c += texture2D(tBloom, vUv).rgb * (bloom + flash * 0.9);
    c = c * exposure * (1. + flash * 5.) + lift + flash * 0.015;
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    c = mix(vec3(l), c, saturation);
    c = aces(c);
    c = (c - 0.5) * contrast + 0.5;
    float v = smoothstep(0.95, 0.2, length(d * vec2(0.85, 1.0)) * 1.25);
    c *= mix(1., v, vignette);
    c = mix(c, fadeColor, fade);
    c = toSRGB(clamp(c, 0., 1.));
    float n = h12(gl_FragCoord.xy + fract(time * 13.7) * 91.3);
    c += (n - 0.5) * (1.5 / 255.);
    c += (h12(gl_FragCoord.xy * 0.73 + time * 17.1) - 0.5) * grain;
    gl_FragColor = vec4(c, 1.);
  }`, {
  tScene: { value: null }, tBloom: { value: null }, exposure: { value: 1 }, bloom: { value: 0.6 }, vignette: { value: 0.55 },
  fade: { value: 0 }, fadeColor: { value: new THREE.Vector3() }, grain: { value: 0 }, time: { value: 0 }, res: { value: new THREE.Vector2(RW, RH) },
  lift: { value: new THREE.Vector3() }, saturation: { value: 1 }, contrast: { value: 1 }, chroma: { value: 0 }, flash: { value: 0 }
});

export const bloomCfg = { threshold: 0.85, knee: 0.55, radius: 1.0 };

export function drawFrame(t) {
  renderer.setRenderTarget(hdr);
  renderer.setClearColor(0x000000, 1);
  renderer.clear(true, true, true);
  renderer.render(scene, camera);

  prefilter.uniforms.tSrc.value = hdr.texture;
  prefilter.uniforms.texel.value.set(1 / RW, 1 / RH);
  prefilter.uniforms.threshold.value = bloomCfg.threshold;
  prefilter.uniforms.knee.value = bloomCfg.knee;
  runPass(prefilter, down[0]);
  for (let i = 1; i < LEVELS; i++) {
    downMat.uniforms.tSrc.value = down[i - 1].texture;
    downMat.uniforms.texel.value.set(1 / down[i - 1].width, 1 / down[i - 1].height);
    runPass(downMat, down[i]);
  }
  // up[i] = blur(up[i+1]) + down[i]
  let src = down[LEVELS - 1];
  for (let i = LEVELS - 2; i >= 0; i--) {
    upMat.uniforms.tSrc.value = src.texture;
    upMat.uniforms.tBase.value = down[i].texture;
    upMat.uniforms.texel.value.set(1 / src.width, 1 / src.height);
    upMat.uniforms.radius.value = bloomCfg.radius;
    runPass(upMat, up[i]);
    src = up[i];
  }
  const u = finalMat.uniforms;
  u.tScene.value = hdr.texture; u.tBloom.value = up[0].texture;
  u.exposure.value = grade.exposure; u.bloom.value = grade.bloom / LEVELS; u.vignette.value = grade.vignette;
  u.fade.value = grade.fade; u.fadeColor.value.set(...grade.fadeColor); u.grain.value = grade.grain; u.time.value = t;
  u.lift.value.set(...grade.lift); u.saturation.value = grade.saturation; u.contrast.value = grade.contrast;
  u.chroma.value = grade.chroma; u.flash.value = grade.flash;
  runPass(finalMat, null);
}

// ---------------------------------------------------------------- textures
const loader = new THREE.TextureLoader();
const pending = [];
export function tex(url, { srgb = true, mips = true } = {}) {
  const t = loader.load(url, undefined, undefined, () => console.error('missing texture ' + url));
  t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
  t.anisotropy = 8;
  t.generateMipmaps = mips;
  t.minFilter = mips ? THREE.LinearMipmapLinearFilter : THREE.LinearFilter;
  pending.push(new Promise(r => { const img = new Image(); img.onload = r; img.onerror = r; img.src = url; }));
  return t;
}
export function texturesLoaded() { return Promise.all(pending); }
// A canvas drawn once, used as a texture.
export function canvasTex(w, h, draw, srgb = true) {
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  const g = c.getContext('2d'); draw(g, w, h);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
  t.anisotropy = 8; t.minFilter = THREE.LinearMipmapLinearFilter; t.generateMipmaps = true;
  return t;
}

// ---------------------------------------------------------------- materials
// A card: a textured plane with rounded corners, an optional sub-rectangle of
// its texture (so one screenshot can be cut into its real cards), and the
// reveals and focus blur every UI layer needs.
//   reveal: 0 none | 1 wipe along `revealDir` | 2 sweep around `revealCenter`
//           | 3 iris from `revealCenter`
const CARD_VS = `varying vec2 vUv; varying vec3 vView;
  void main(){ vUv = uv; vec4 mv = modelViewMatrix * vec4(position, 1.); vView = mv.xyz; gl_Position = projectionMatrix * mv; }`;
const CARD_FS = `uniform sampler2D map; uniform vec4 uvRect; uniform vec2 size; uniform float radius, opacity, blur, bright, reveal, revealMode, revealSoft;
  uniform vec2 revealDir, revealCenter; uniform vec3 tint; uniform float tintAmt, rim, hasMap; uniform vec3 rimColor, color; uniform float glass;
  uniform float edgeSoft; uniform vec3 hole; uniform float grad;
  varying vec2 vUv; varying vec3 vView;
  float sdRound(vec2 p, vec2 b, float r){ vec2 q = abs(p) - b + r; return length(max(q, 0.)) + min(max(q.x, q.y), 0.) - r; }
  void main(){
    vec2 p = (vUv - 0.5) * size;
    float d = sdRound(p, size * 0.5, radius);
    float aa = fwidth(d) * 1.2;
    float mask = edgeSoft > 0. ? 1. - smoothstep(-edgeSoft, edgeSoft * 0.5, d) : 1. - smoothstep(-aa, aa, d);
    if (hole.z > 0.) { float hr = length((vUv - hole.xy) * size) - hole.z; mask *= smoothstep(-aa, aa, hr); }
    if (revealMode > 0.5) {
      float k;
      if (revealMode < 1.5) { k = dot(vUv - 0.5, normalize(revealDir)) + 0.5; }
      else if (revealMode < 2.5) { vec2 q = vUv - revealCenter; k = fract((atan(q.x, q.y) / 6.2831853) + 1.); }
      else { k = length((vUv - revealCenter) * size) / length(size); }
      mask *= 1. - smoothstep(reveal - revealSoft, reveal, k);
    }
    vec4 c = vec4(color * (1. - grad * (1. - vUv.y)), 1.);
    if (hasMap > 0.5) {
      vec2 uv = uvRect.xy + vUv * uvRect.zw;
      if (blur > 0.001) {
        float lod = blur * 6.;
        vec4 acc = vec4(0.);
        for (int i = 0; i < 8; i++) {
          float a = float(i) * 2.3999632 + 0.4; float r = sqrt((float(i) + 0.5) / 8.);
          vec2 o = vec2(cos(a), sin(a)) * r * blur * 0.018 * vec2(1., size.x / size.y);
          acc += textureLod(map, uv + o * uvRect.zw * 2.2, lod);
        }
        c = acc / 8.;
      } else c = texture2D(map, uv);
    }
    vec3 rgb = mix(c.rgb, c.rgb * tint, tintAmt) * bright;
    // A lit edge, as if the card were a pane of glass catching the moon.
    float edge = 1. - smoothstep(0., size.x * 0.03 + 0.004, -d);
    rgb += rimColor * rim * edge;
    float a = c.a * mask * opacity;
    gl_FragColor = vec4(rgb * a, a);
  }`;
export function cardMaterial(opts = {}) {
  const m = new THREE.ShaderMaterial({
    vertexShader: CARD_VS, fragmentShader: CARD_FS, transparent: true, depthWrite: false,
    premultipliedAlpha: true, blending: THREE.NormalBlending, side: THREE.DoubleSide,
    uniforms: {
      map: { value: opts.map || null }, hasMap: { value: opts.map ? 1 : 0 }, uvRect: { value: new THREE.Vector4(0, 0, 1, 1) },
      size: { value: new THREE.Vector2(1, 1) }, radius: { value: 0 }, opacity: { value: 1 }, blur: { value: 0 }, bright: { value: 1 },
      reveal: { value: 1 }, revealMode: { value: 0 }, revealSoft: { value: 0.06 }, revealDir: { value: new THREE.Vector2(0, 1) },
      revealCenter: { value: new THREE.Vector2(0.5, 0.5) }, tint: { value: new THREE.Vector3(1, 1, 1) }, tintAmt: { value: 0 },
      rim: { value: 0 }, rimColor: { value: new THREE.Vector3(0.6, 0.62, 1.0) }, color: { value: new THREE.Vector3(1, 1, 1) }, glass: { value: 0 },
      edgeSoft: { value: 0 }, hole: { value: new THREE.Vector3(0.5, 0.5, 0) }, grad: { value: 0 }
    }
  });
  return m;
}
// A card mesh sized in world units. `crop` is a pixel rectangle [x, y, w, h]
// of an image `imgW` x `imgH`; the plane takes the crop's aspect.
export function card(map, { crop = null, imgW = 1, imgH = 1, width = 1, radiusPx = 0, blend = 'normal' } = {}) {
  const mat = cardMaterial({ map });
  let aspect = 1;
  if (crop) {
    const [x, y, w, h] = crop;
    mat.uniforms.uvRect.value.set(x / imgW, 1 - (y + h) / imgH, w / imgW, h / imgH);
    aspect = h / w;
  } else if (map && map.image && map.image.width) aspect = map.image.height / map.image.width;
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), mat);
  mesh.userData.aspect = aspect;
  setCardSize(mesh, width, width * aspect);
  if (crop) mat.uniforms.radius.value = (radiusPx / crop[2]) * width;
  if (blend === 'add') { mat.blending = THREE.AdditiveBlending; }
  return mesh;
}
export function setCardSize(mesh, w, h) {
  mesh.scale.set(w, h, 1);
  mesh.material.uniforms.size.value.set(w, h);
}

// Additive glow sprite: a soft radial falloff, for light sources and halos.
const GLOW_FS = `uniform vec3 color; uniform float opacity, power, core; varying vec2 vUv;
  void main(){ float r = length(vUv - 0.5) * 2.; float g = pow(max(0., 1. - r), power); g += core * exp(-r * r * 60.);
    gl_FragColor = vec4(color * g * opacity, 0.); }`;
export function glow(color = [1, 1, 1], power = 2.2) {
  const m = new THREE.ShaderMaterial({
    vertexShader: CARD_VS, fragmentShader: GLOW_FS, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, premultipliedAlpha: true,
    uniforms: { color: { value: new THREE.Vector3(...color) }, opacity: { value: 1 }, power: { value: power }, core: { value: 0 } }
  });
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), m);
  return mesh;
}

// A ribbon: a polyline drawn as a camera-facing strip of constant world
// width, revealed along its length, with a hot head. Points are set per frame.
const RIBBON_VS = `attribute vec3 other; attribute float side; attribute float along; uniform float width; varying float vAlong; varying float vSide;
  void main(){
    vec4 a = modelViewMatrix * vec4(position, 1.); vec4 b = modelViewMatrix * vec4(other, 1.);
    vec2 dir = normalize(b.xy - a.xy + vec2(1e-6, 0.)); vec2 n = vec2(-dir.y, dir.x);
    a.xy += n * side * width * 0.5;
    vAlong = along; vSide = side; gl_Position = projectionMatrix * a; }`;
const RIBBON_FS = `uniform vec3 color, color2; uniform float opacity, progress, head, fadeTail, softness, start; varying float vAlong; varying float vSide;
  void main(){
    if (vAlong > progress || vAlong < start) discard;
    float edge = 1. - smoothstep(1. - softness, 1., abs(vSide));
    float tail = fadeTail > 0. ? smoothstep(progress - fadeTail, progress, vAlong) : 1.;
    vec3 c = mix(color, color2, vAlong);
    float hot = head * exp(-(progress - vAlong) * 60.);
    gl_FragColor = vec4((c * (1. + hot * 3.)) * edge * tail * opacity, 0.);
  }`;
export class Ribbon {
  constructor(maxPts, { color = [1, 1, 1], color2 = null, width = 0.02, additive = true } = {}) {
    this.max = maxPts;
    const g = new THREE.BufferGeometry();
    this.pos = new Float32Array(maxPts * 2 * 3); this.oth = new Float32Array(maxPts * 2 * 3);
    const side = new Float32Array(maxPts * 2), along = new Float32Array(maxPts * 2); this.along = along;
    for (let i = 0; i < maxPts; i++) { side[i * 2] = -1; side[i * 2 + 1] = 1; }
    const idx = [];
    for (let i = 0; i < maxPts - 1; i++) { const a = i * 2; idx.push(a, a + 1, a + 2, a + 1, a + 3, a + 2); }
    g.setIndex(idx);
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3));
    g.setAttribute('other', new THREE.BufferAttribute(this.oth, 3));
    g.setAttribute('side', new THREE.BufferAttribute(side, 1));
    g.setAttribute('along', new THREE.BufferAttribute(along, 1));
    this.mat = new THREE.ShaderMaterial({
      vertexShader: RIBBON_VS, fragmentShader: RIBBON_FS, transparent: true, depthWrite: false, side: THREE.DoubleSide,
      blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending, premultipliedAlpha: true,
      uniforms: { color: { value: new THREE.Vector3(...color) }, color2: { value: new THREE.Vector3(...(color2 || color)) }, opacity: { value: 1 },
        progress: { value: 1 }, head: { value: 0 }, fadeTail: { value: 0 }, width: { value: width }, softness: { value: 0.6 }, start: { value: -1 } }
    });
    this.mesh = new THREE.Mesh(g, this.mat); this.mesh.frustumCulled = false;
    this.geo = g;
  }
  // pts: array of [x,y,z]; lengths normalised into `along` 0..1
  set(pts) {
    const n = Math.min(pts.length, this.max);
    let total = 0; const L = [0];
    for (let i = 1; i < n; i++) { const a = pts[i - 1], b = pts[i]; total += Math.hypot(b[0] - a[0], b[1] - a[1], b[2] - a[2]); L.push(total); }
    for (let i = 0; i < this.max; i++) {
      const j = Math.min(i, n - 1), p = pts[j], q = pts[Math.min(j + 1, n - 1)], r = pts[Math.max(j - 1, 0)];
      const o = j < n - 1 ? q : [p[0] + (p[0] - r[0]), p[1] + (p[1] - r[1]), p[2] + (p[2] - r[2])];
      for (let s = 0; s < 2; s++) {
        const k = (i * 2 + s) * 3;
        this.pos[k] = p[0]; this.pos[k + 1] = p[1]; this.pos[k + 2] = p[2];
        this.oth[k] = o[0]; this.oth[k + 1] = o[1]; this.oth[k + 2] = o[2];
        this.along[i * 2 + s] = total > 0 ? L[j] / total : 0;
      }
    }
    this.geo.attributes.position.needsUpdate = true; this.geo.attributes.other.needsUpdate = true; this.geo.attributes.along.needsUpdate = true;
    this.geo.setDrawRange(0, Math.max(0, (n - 1) * 6));
  }
}

// An arc on a quad: a ring drawn by its fragment shader, so it stays crisp at
// any size, with round caps and a gradient along its sweep.
const ARC_PAD = 1.3;
const ARC_FS = `#define ARC_PAD 1.3
  uniform vec3 color, color2; uniform float opacity, progress, thickness, start, glowAmt, track; varying vec2 vUv;
  void main(){
    vec2 p = (vUv - 0.5) * 2. * ARC_PAD;
    float r = length(p);
    float a = fract(atan(p.x, p.y) / 6.2831853 - start + 1.);
    float band = abs(r - (1. - thickness)) - thickness;
    float aa = fwidth(r) * 1.5;
    float ring = 1. - smoothstep(-aa, aa, band);
    // round caps at both ends of the sweep
    float R = 1. - thickness;
    vec2 c0 = R * vec2(sin(start * 6.2831853), cos(start * 6.2831853));
    float e = (start + progress) * 6.2831853; vec2 c1 = R * vec2(sin(e), cos(e));
    float caps = max(1. - smoothstep(thickness - aa, thickness + aa, length(p - c0)), 1. - smoothstep(thickness - aa, thickness + aa, length(p - c1)));
    float on = step(a, progress) * ring;
    on = max(on, progress > 0.001 ? caps : 0.);
    vec3 col = mix(color, color2, clamp(a / max(progress, 1e-3), 0., 1.));
    float halo = glowAmt * exp(-pow(band / (thickness * 3.), 2.)) * step(a, progress);
    float tr = track * ring * (1. - on);
    gl_FragColor = vec4(col * (on + halo) * opacity + vec3(1.) * tr * 0.06 * opacity, (on + tr * 0.06) * opacity);
  }`;
export function arc({ color = [1, 1, 1], color2 = null, thickness = 0.06 } = {}) {
  const m = new THREE.ShaderMaterial({
    vertexShader: CARD_VS, fragmentShader: ARC_FS, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, premultipliedAlpha: true, side: THREE.DoubleSide,
    uniforms: { color: { value: new THREE.Vector3(...color) }, color2: { value: new THREE.Vector3(...(color2 || color)) }, opacity: { value: 1 },
      progress: { value: 1 }, thickness: { value: thickness }, start: { value: 0 }, glowAmt: { value: 0.4 }, track: { value: 0 } }
  });
  // the quad is padded around the ring; scale the mesh by the ring's diameter
  return new THREE.Mesh(new THREE.PlaneGeometry(ARC_PAD, ARC_PAD), m);
}

// Particles: soft discs whose positions are mixed between two layouts per
// particle, each with its own delay, so a cloud can reorganise into a chart.
const PTS_VS = `attribute vec3 a, b; attribute float seed; attribute vec3 col; uniform float morph, time, size, spread, swirl, pxScale, sizeVar;
  varying vec3 vCol; varying float vA;
  void main(){
    float d = seed * spread;
    float k = clamp((morph - d) / max(1. - spread, 1e-3), 0., 1.);
    k = k * k * (3. - 2. * k);
    vec3 p = mix(a, b, k);
    float lift = sin(k * 3.14159) * swirl;
    p += vec3(sin(seed * 91. + time * 0.7) * lift, cos(seed * 57. + time * 0.6) * lift * 0.6 + lift, sin(seed * 13.) * lift);
    vec4 mv = modelViewMatrix * vec4(p, 1.);
    gl_Position = projectionMatrix * mv;
    gl_PointSize = size * pxScale / -mv.z * (1. - sizeVar * 0.5 + sizeVar * fract(seed * 7.13));
    vCol = col; vA = 1.;
  }`;
const PTS_FS = `uniform float opacity; varying vec3 vCol; varying float vA;
  void main(){ vec2 q = gl_PointCoord - 0.5; float r = length(q) * 2.; float g = exp(-r * r * 4.) ; if (r > 1.) discard;
    gl_FragColor = vec4(vCol * g * opacity * vA, 0.); }`;
export class Cloud {
  constructor(n, seed = 7) {
    this.n = n;
    const g = new THREE.BufferGeometry();
    this.a = new Float32Array(n * 3); this.b = new Float32Array(n * 3); this.col = new Float32Array(n * 3);
    const s = new Float32Array(n); const r = rng(seed); for (let i = 0; i < n; i++) s[i] = r();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(n * 3), 3));
    g.setAttribute('a', new THREE.BufferAttribute(this.a, 3)); g.setAttribute('b', new THREE.BufferAttribute(this.b, 3));
    g.setAttribute('seed', new THREE.BufferAttribute(s, 1)); g.setAttribute('col', new THREE.BufferAttribute(this.col, 3));
    this.geo = g;
    this.mat = new THREE.ShaderMaterial({
      vertexShader: PTS_VS, fragmentShader: PTS_FS, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, premultipliedAlpha: true,
      uniforms: { morph: { value: 0 }, time: { value: 0 }, size: { value: 0.05 }, spread: { value: 0.3 }, swirl: { value: 0 }, opacity: { value: 1 }, pxScale: { value: RH / 2 }, sizeVar: { value: 0.6 } }
    });
    this.points = new THREE.Points(g, this.mat); this.points.frustumCulled = false;
  }
  layout(which, fn) { const arr = which === 'a' ? this.a : this.b; for (let i = 0; i < this.n; i++) { const p = fn(i); arr[i * 3] = p[0]; arr[i * 3 + 1] = p[1]; arr[i * 3 + 2] = p[2]; } this.geo.attributes[which].needsUpdate = true; }
  colors(fn) { for (let i = 0; i < this.n; i++) { const c = fn(i); this.col[i * 3] = c[0]; this.col[i * 3 + 1] = c[1]; this.col[i * 3 + 2] = c[2]; } this.geo.attributes.col.needsUpdate = true; }
}

// ---------------------------------------------------------------- camera helpers
export function lookFrom(pos, target, roll = 0) {
  camera.position.set(pos[0], pos[1], pos[2]);
  camera.up.set(Math.sin(roll), Math.cos(roll), 0);
  camera.lookAt(target[0], target[1], target[2]);
  camera.updateMatrixWorld(true);   // so project() uses this frame's camera
}
// Project a world point to overlay pixels (CSS pixels, 1080x1920 space).
const _v = new THREE.Vector3();
export function project(p) {
  _v.set(p[0], p[1], p[2]).project(camera);
  return { x: (_v.x * 0.5 + 0.5) * W, y: (1 - (_v.y * 0.5 + 0.5)) * H, z: _v.z, behind: _v.z > 1 };
}
export function worldToScreenScale(p) {
  // CSS pixels per world unit at the depth of p
  const d = camera.position.distanceTo(new THREE.Vector3(...p));
  return H / (2 * d * Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2));
}
