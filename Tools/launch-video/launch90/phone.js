// The phone: an iPhone 17 Pro's proportions (the captures are 1206 x 2622),
// an aluminium body with rounded edges, a black glass front and the app's
// real screen. Screens can be cut into layers: each layer is a crop of the
// capture that flies in on its own and lands exactly where the app drew it.
import { THREE, cardMaterial, setCardSize, lin, clamp, lerp } from './engine.js';

export const CAP_W = 1206, CAP_H = 2622;
export const SCREEN_W = 1, SCREEN_H = CAP_H / CAP_W;
const BORDER = 0.024, BEV = 0.028;
const GLASS_W = SCREEN_W + 2 * BORDER, GLASS_H = SCREEN_H + 2 * BORDER;
export const SCREEN_R = 0.1368;
const GLASS_R = SCREEN_R + BORDER;
export const BODY_W = GLASS_W + 2 * BEV, BODY_H = GLASS_H + 2 * BEV, DEPTH = 0.13;
export const FRONT = DEPTH / 2;

// A rounded rectangle, centred.
export function roundRect(w, h, r) {
  const s = new THREE.Shape(), x = -w / 2, y = -h / 2;
  s.moveTo(x + r, y);
  s.lineTo(x + w - r, y); s.absarc(x + w - r, y + r, r, -Math.PI / 2, 0, false);
  s.lineTo(x + w, y + h - r); s.absarc(x + w - r, y + h - r, r, 0, Math.PI / 2, false);
  s.lineTo(x + r, y + h); s.absarc(x + r, y + h - r, r, Math.PI / 2, Math.PI, false);
  s.lineTo(x, y + r); s.absarc(x + r, y + r, r, Math.PI, Math.PI * 1.5, false);
  return s;
}

// Capture pixels -> screen-local world units (origin at the screen centre).
export const capX = px => (px / CAP_W - 0.5) * SCREEN_W;
export const capY = py => (0.5 - py / CAP_H) * SCREEN_H;

const metal = (rgb, rough = 0.3) => new THREE.MeshPhysicalMaterial({
  color: new THREE.Color().setRGB(...lin(rgb)), metalness: 1, roughness: rough, envMapIntensity: 2.2
});

// The glass sheen: a soft diagonal reflection that slides as the phone turns.
const SHEEN_FS = `uniform vec2 size; uniform float radius, amt, pos, opacity; varying vec2 vUv;
  float sdRound(vec2 p, vec2 b, float r){ vec2 q = abs(p) - b + r; return length(max(q, 0.)) + min(max(q.x, q.y), 0.) - r; }
  void main(){
    vec2 p = (vUv - 0.5) * size;
    float d = sdRound(p, size * 0.5, radius);
    float mask = 1. - smoothstep(-fwidth(d), fwidth(d), d);
    float s = vUv.x * 0.82 + vUv.y * 0.58;
    float band = exp(-pow((s - pos) / 0.2, 2.)) * 0.55 + exp(-pow((s - pos - 0.32) / 0.05, 2.)) * 0.35;
    gl_FragColor = vec4(vec3(0.72, 0.78, 1.0) * band * amt * mask * opacity, 0.);
  }`;

export class Phone {
  constructor() {
    this.group = new THREE.Group();          // position / rotate this
    this.group.visible = false;
    const body = new THREE.ExtrudeGeometry(roundRect(GLASS_W, GLASS_H, GLASS_R), {
      depth: DEPTH - 2 * BEV, bevelEnabled: true, bevelThickness: BEV, bevelSize: BEV, bevelSegments: 10, curveSegments: 32
    });
    body.translate(0, 0, -(DEPTH - 2 * BEV) / 2);
    this.frameMat = metal([0.19, 0.22, 0.32], 0.3);   // the Deep Blue finish
    this.body = new THREE.Mesh(body, this.frameMat);
    this.group.add(this.body);

    this.glassMat = new THREE.MeshPhysicalMaterial({ color: 0x020203, metalness: 0, roughness: 0.07, clearcoat: 1, clearcoatRoughness: 0.03, envMapIntensity: 1.0 });
    const glass = new THREE.Mesh(new THREE.ShapeGeometry(roundRect(GLASS_W, GLASS_H, GLASS_R), 32), this.glassMat);
    glass.position.z = FRONT + 0.0004;
    this.group.add(glass);

    // buttons: action, volume up/down on the left; side button and camera control on the right
    const btn = (len, x, y, rough = 0.28) => {
      const g = new THREE.CapsuleGeometry(0.012, len, 6, 12);
      const m = new THREE.Mesh(g, this.frameMat);
      m.scale.set(0.55, 1, 1.6); m.position.set(x, y, 0); this.group.add(m); return m;
    };
    const L = -BODY_W / 2 - 0.002, R = BODY_W / 2 + 0.002;
    btn(0.07, L, 0.60); btn(0.13, L, 0.39); btn(0.13, L, 0.20); btn(0.2, R, 0.33); btn(0.1, R, -0.36);

    // the screen: a base capture, a second capture to crossfade into, and layers above
    this.screen = this._card(); this.screen.position.z = FRONT + 0.0012; this.screen.renderOrder = 1; this.group.add(this.screen);
    this.screenB = this._card(); this.screenB.position.z = FRONT + 0.0016; this.screenB.renderOrder = 2; this.group.add(this.screenB);
    this.layers = new THREE.Group(); this.layers.position.z = FRONT + 0.002; this.group.add(this.layers);
    this.sheenMat = new THREE.ShaderMaterial({
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }',
      fragmentShader: SHEEN_FS, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, premultipliedAlpha: true,
      uniforms: { size: { value: new THREE.Vector2(GLASS_W, GLASS_H) }, radius: { value: GLASS_R }, amt: { value: 0.045 }, pos: { value: 0.5 }, opacity: { value: 1 } }
    });
    this.sheen = new THREE.Mesh(new THREE.PlaneGeometry(GLASS_W, GLASS_H), this.sheenMat);
    this.sheen.position.z = FRONT + 0.004; this.sheen.renderOrder = 10;
    this.group.add(this.sheen);
    this._pool = [];
  }
  _card() {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), cardMaterial());
    setCardSize(m, SCREEN_W, SCREEN_H); m.material.uniforms.radius.value = SCREEN_R; m.visible = false;
    return m;
  }
  // Every frame starts from a phone with a dark screen and no layers.
  reset() {
    this.group.visible = false; this.group.scale.setScalar(1);
    for (const s of [this.screen, this.screenB]) {
      s.visible = false; const u = s.material.uniforms;
      u.opacity.value = 1; u.blur.value = 0; u.bright.value = 1.1; u.reveal.value = 1; u.revealMode.value = 0; u.tintAmt.value = 0;
      u.uvRect.value.set(0, 0, 1, 1);
    }
    for (const l of this._pool) l.visible = false;
    this._used = 0;
    this.sheenMat.uniforms.opacity.value = 1;
  }
  show(camera) {
    this.group.visible = true;
    // the sheen follows the camera's angle to the glass
    const v = camera.position.clone(); this.group.worldToLocal(v); v.normalize();
    this.sheenMat.uniforms.pos.value = 0.55 + v.x * 1.25 - v.y * 0.45;
  }
  setScreen(map, o = {}) {
    const s = o.b ? this.screenB : this.screen, u = s.material.uniforms;
    s.visible = true; u.map.value = map; u.hasMap.value = 1;
    u.opacity.value = o.opacity ?? 1; u.blur.value = o.blur ?? 0; u.bright.value = (o.bright ?? 1) * 1.1;
    return s;
  }
  // A layer: a crop [x, y, w, h] of a capture, in capture pixels, with its
  // own corner radius. It rests where the app drew it; `pose` moves it.
  layer(map, crop, o = {}) {
    let m = this._pool[this._used];
    if (!m) { m = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), cardMaterial()); m.renderOrder = 3 + this._pool.length; this._pool.push(m); this.layers.add(m); }
    this._used++;
    const [x, y, w, h] = crop, u = m.material.uniforms;
    u.map.value = map; u.hasMap.value = 1;
    u.uvRect.value.set(x / CAP_W, 1 - (y + h) / CAP_H, w / CAP_W, h / CAP_H);
    const ww = w / CAP_W * SCREEN_W, hh = h / CAP_H * SCREEN_H;
    setCardSize(m, ww, hh);
    u.radius.value = (o.radiusPx ?? 0) / CAP_W * SCREEN_W;
    u.opacity.value = o.opacity ?? 1; u.blur.value = o.blur ?? 0; u.bright.value = (o.bright ?? 1) * 1.1;
    u.reveal.value = o.reveal ?? 1; u.revealMode.value = o.revealMode ?? 0; u.revealSoft.value = o.revealSoft ?? 0.06;
    u.revealDir.value.set(...(o.revealDir || [1, 0])); u.revealCenter.value.set(...(o.revealCenter || [0.5, 0.5]));
    u.rim.value = o.rim ?? 0; u.tintAmt.value = 0; u.edgeSoft.value = 0; u.hole.value.set(0.5, 0.5, 0);
    m.position.set(capX(x + w / 2), capY(y + h / 2), (o.z ?? 0) + this._used * 0.0004);
    m.rotation.set(0, 0, 0); m.scale.z = 1;
    m.visible = true;
    m.userData.rest = m.position.clone();
    return m;
  }
}

// The watch: an Apple Watch case in midnight aluminium, its band, and the
// watch app's real page (the captures are 324 x 394).
export const WCAP_W = 324, WCAP_H = 394;
export class Watch {
  constructor() {
    this.group = new THREE.Group(); this.group.visible = false;
    const CW = 0.82, CH = 1.0, CR = 0.25, D = 0.22, B = 0.045;
    const body = new THREE.ExtrudeGeometry(roundRect(CW - 2 * B, CH - 2 * B, CR - B), {
      depth: D - 2 * B, bevelEnabled: true, bevelThickness: B, bevelSize: B, bevelSegments: 10, curveSegments: 32 });
    body.translate(0, 0, -(D - 2 * B) / 2);
    this.caseMat = metal([0.16, 0.17, 0.22], 0.26);
    this.group.add(new THREE.Mesh(body, this.caseMat));
    const glass = new THREE.Mesh(new THREE.ShapeGeometry(roundRect(CW - 2 * B, CH - 2 * B, CR - B), 32),
      new THREE.MeshPhysicalMaterial({ color: 0x010102, metalness: 0, roughness: 0.06, clearcoat: 1, clearcoatRoughness: 0.03 }));
    glass.position.z = D / 2 + 0.0005; this.group.add(glass);
    this.SW = 0.64; this.SH = this.SW * WCAP_H / WCAP_W;
    this.screen = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), cardMaterial());
    setCardSize(this.screen, this.SW, this.SH); this.screen.material.uniforms.radius.value = 0.15;
    this.screen.position.z = D / 2 + 0.0012; this.screen.renderOrder = 1; this.group.add(this.screen);
    const crown = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.07, 0.07, 40), this.caseMat);
    crown.rotation.z = Math.PI / 2; crown.position.set(CW / 2 + 0.03, 0.2, 0); this.group.add(crown);
    const btn = new THREE.Mesh(new THREE.CapsuleGeometry(0.02, 0.16, 6, 12), this.caseMat);
    btn.position.set(CW / 2 + 0.005, -0.12, 0); btn.scale.set(0.8, 1, 1.6); this.group.add(btn);
    // the band: a sport loop, top and bottom, falling away into the dark
    const bandMat = new THREE.MeshPhysicalMaterial({ color: new THREE.Color().setRGB(...lin([0.1, 0.11, 0.18])), roughness: 0.55, metalness: 0, clearcoat: 0.25, envMapIntensity: 0.8 });
    const bandGeo = new THREE.ExtrudeGeometry(roundRect(0.58, 1.5, 0.12), { depth: 0.05, bevelEnabled: true, bevelThickness: 0.02, bevelSize: 0.02, bevelSegments: 4, curveSegments: 12 });
    bandGeo.translate(0, 0, -0.045);
    for (const s of [1, -1]) { const b = new THREE.Mesh(bandGeo, bandMat); b.position.set(0, s * (CH / 2 + 0.68), -0.02); b.rotation.x = s * 0.12; this.group.add(b); }
    this.sheenMat = new THREE.ShaderMaterial({
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }',
      fragmentShader: SHEEN_FS, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, premultipliedAlpha: true,
      uniforms: { size: { value: new THREE.Vector2(CW - 2 * B, CH - 2 * B) }, radius: { value: CR - B }, amt: { value: 0.05 }, pos: { value: 0.5 }, opacity: { value: 1 } }
    });
    const sheen = new THREE.Mesh(new THREE.PlaneGeometry(CW - 2 * B, CH - 2 * B), this.sheenMat);
    sheen.position.z = D / 2 + 0.003; sheen.renderOrder = 10; this.group.add(sheen);
    this.FRONT = D / 2;
  }
  show(camera, map) {
    this.group.visible = true;
    const u = this.screen.material.uniforms; u.map.value = map; u.hasMap.value = 1; u.bright.value = 1.1;
    const v = camera.position.clone(); this.group.worldToLocal(v); v.normalize();
    this.sheenMat.uniforms.pos.value = 0.55 + v.x * 1.25 - v.y * 0.45;
  }
}

// Fly a layer in: k runs 0 -> 1; `from` is an offset in screen units and
// radians. The layer blurs and fades while it travels.
export function pose(m, k, from = {}) {
  const r = m.userData.rest, e = 1 - k;
  m.position.set(r.x + (from.x || 0) * e, r.y + (from.y || 0) * e, r.z + (from.z ?? 0.35) * e);
  m.rotation.set((from.rx || 0) * e, (from.ry || 0) * e, (from.rz || 0) * e);
  const s = lerp(from.s ?? 1, 1, k);
  m.scale.x *= s; m.scale.y *= s;
  const u = m.material.uniforms;
  u.opacity.value *= clamp(k * 2.2);
  u.blur.value = Math.max(u.blur.value, (from.blur ?? 0.5) * e * e);
  return m;
}
