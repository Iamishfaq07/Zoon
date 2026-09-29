# Sound design for the 100-second showreel. No instruments, no melody, no
# ambience of sleep: only designed sound, the way a motion designer scores a
# reel. Every event comes from cues100.json (exported by `node render100.js
# cues` from showreel.html), so each sound lands on the frame that causes it.
#
#   whoosh / whooshL / swipe / slide   air moved by camera and whip pans
#   hit / boom / land / latch / snap   impacts: sub drop, transient, room tail
#   riser / rev                        tension: filtered noise and an
#                                      accelerating tick train / reversed swell
#   tick / click / key / detent / pop  UI foley: clock ticks, taps, crown detents
#   blip / chime / data / ticks        data: tiny band-limited noise grains
#   glitch / draw / scan / stretch     textures: bit-crushed stutter, pen on glass
#   thump / haptic                     a heartbeat, a Taptic double tap
#   shimmer / tail                     air: bright noise that settles
#
# Everything is noise shaped by filters and envelopes, plus short decaying
# transients; nothing is pitched into notes.
import json, os, sys, wave
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
# CUES=cues-free.json scores another film; its export can carry `pulses`
# (sections for the clockwork bed), `swell` and `fadeout` (story seconds).
SPEC = json.load(open(os.path.join(HERE, os.environ.get('CUES', 'cues100.json'))))
# Optional cut list (see cuts90.json): story ranges left out of this mix.
# (pass '' as the cut list to write another output name without cutting)
CUTS = json.load(open(os.path.join(HERE, sys.argv[1])))['cuts'] if len(sys.argv) > 1 and sys.argv[1] else []
OUT = sys.argv[2] if len(sys.argv) > 2 else 'score100.wav'


def O(t):
    """Story time -> output time; None inside a cut."""
    out = t
    for a, b in CUTS:
        if t >= b: out -= b - a
        elif t > a: return None
    return out


SR = 48000
DUR = float(SPEC['duration']) - sum(b - a for a, b in CUTS)
N = int(SR * DUR)
rng = np.random.default_rng(100)
L = np.zeros(N); R = np.zeros(N)


def fft_filter(x, lo, hi, order=4):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    m = np.ones_like(f)
    if lo > 0: m *= 1 / (1 + (lo / np.maximum(f, 1)) ** order)
    if hi > 0: m *= 1 / (1 + (f / hi) ** order)
    return np.fft.irfft(X * m, len(x))


def noise(sec, lo=0, hi=0):
    x = rng.standard_normal(max(8, int(sec * SR)))
    if lo or hi: x = fft_filter(x, lo, hi)
    return x / (np.abs(x).max() + 1e-9)


def tt(sec):
    return np.arange(int(sec * SR)) / SR


def swept(sec, f0, f1, width=0.9, bands=16, shape=None):
    """Noise whose band centre travels f0 -> f1 (log), built from fixed bands
    that each open as the centre passes them."""
    n = int(sec * SR); t = np.arange(n) / sec / SR
    centre = np.exp(np.log(f0) + (np.log(f1) - np.log(f0)) * (t if shape is None else shape(t)))
    lo_f, hi_f = min(f0, f1) / 1.6, max(f0, f1) * 1.6
    edges = np.geomspace(lo_f, hi_f, bands + 1)
    out = np.zeros(n)
    base = rng.standard_normal(n)
    for a, b in zip(edges[:-1], edges[1:]):
        fc = np.sqrt(a * b)
        band = fft_filter(base, a, b, 6)
        g = np.exp(-0.5 * (np.log(centre / fc) / width) ** 2)
        out += band * g
    return out / (np.abs(out).max() + 1e-9)


def S(*parts):
    """Sum sounds of different lengths."""
    out = np.zeros(max(len(p) for p in parts))
    for p in parts: out[:len(p)] += p
    return out


def ping(sec, f, decay, phase=0.0):
    t = tt(sec)
    return np.sin(2 * np.pi * f * t + phase) * np.exp(-t / decay)


def drop(sec, f0, f1, decay):
    """A sine falling in pitch, as under an impact."""
    t = tt(sec)
    f = f1 + (f0 - f1) * np.exp(-t / (decay * 0.35))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t / decay)


def env(sec, att, rel, curve=2.0):
    n = int(sec * SR); t = np.arange(n) / SR
    a = np.clip(t / max(att, 1e-4), 0, 1) ** curve
    r = np.clip((sec - t) / max(rel, 1e-4), 0, 1) ** curve
    return a * r


def add(sig, start, pan=0.0, gain=1.0, travel=0.0):
    """Place a mono sound at `start` s. `travel` moves the pan across the sound."""
    i = int(round(start * SR))
    if i >= N or len(sig) == 0: return
    if i < 0: sig = sig[-i:]; i = 0
    sig = sig[:N - i]
    p = np.clip(pan + travel * np.linspace(-1, 1, len(sig)), -1, 1)
    th = (p + 1) * np.pi / 4
    L[i:i + len(sig)] += sig * np.cos(th) * gain
    R[i:i + len(sig)] += sig * np.sin(th) * gain


def add_st(l, r, start, gain=1.0):
    i = int(round(start * SR)); n = min(len(l), N - i)
    if n <= 0: return
    L[i:i + n] += l[:n] * gain; R[i:i + n] += r[:n] * gain


def tail(sec, lo, hi, decay):
    """A stereo room: two decorrelated decays."""
    t = tt(sec); e = np.exp(-t / decay)
    return noise(sec, lo, hi) * e, noise(sec, lo, hi) * e


# ---------------- the sounds ----------------
def s_whoosh(c, long=False):
    d = 1.25 if long else 0.62
    x = swept(d, 250 if long else 500, 5200 if long else 7000, 0.7, shape=lambda u: np.sin(np.pi * u) ** 1.2)
    e = env(d, d * 0.62, d * 0.38, 2.2)
    body = noise(d, 60, 400) * env(d, d * 0.6, d * 0.4, 2) * (0.8 if long else 0.35)
    start = c['t'] - d * 0.55
    add(x * e * 0.55 + body, start, c['pan'] * 0.4, c['gain'], travel=0.55 if c['pan'] >= 0 else -0.55)


def s_swipe(c):
    d = 0.28
    x = swept(d, 1500, 9000, 0.6, shape=lambda u: u) * env(d, 0.12, 0.14, 2)
    add(x * 0.35, c['t'] - 0.12, c['pan'], c['gain'], travel=0.4)


def s_slide(c):
    d = 0.4
    x = swept(d, 400, 2500, 0.8, shape=lambda u: u) * env(d, 0.18, 0.2, 2)
    add(x * 0.3, c['t'] - 0.15, c['pan'], c['gain'], travel=0.3)


def s_hit(c):
    d = 0.9
    sub = drop(d, 150, 48, 0.2) * 0.9
    click = noise(0.012, 2000, 0) * env(0.012, 0.0005, 0.01, 1) * 0.7
    body = noise(0.25, 80, 900) * env(0.25, 0.001, 0.22, 3) * 0.45
    add(sub, c['t'], 0, c['gain'] * 0.9)
    add(click, c['t'], c['pan'] * 0.5, c['gain'])
    add(body, c['t'], c['pan'] * 0.3, c['gain'])
    l, r = tail(1.0, 150, 3500, 0.22); add_st(l * 0.1, r * 0.1, c['t'] + 0.01, c['gain'])


def s_boom(c):
    d = 2.8
    sub = drop(d, 95, 30, 0.75)
    sub = np.tanh(sub * 1.8) * 0.85
    crack = noise(0.05, 900, 0) * env(0.05, 0.0005, 0.045, 2) * 0.8
    thump = noise(0.5, 30, 250) * env(0.5, 0.002, 0.45, 2) * 0.6
    add(sub, c['t'], 0, c['gain'] * 0.95)
    add(crack, c['t'], 0, c['gain'])
    add(thump, c['t'], 0, c['gain'])
    l, r = tail(3.2, 80, 5000, 0.8); add_st(l * 0.16, r * 0.16, c['t'] + 0.015, c['gain'])


def s_land(c):
    d = 0.5
    add(drop(d, 120, 55, 0.12) * 0.6, c['t'], 0, c['gain'])
    add(noise(0.18, 150, 1500) * env(0.18, 0.002, 0.16, 3) * 0.35, c['t'], c['pan'] * 0.4, c['gain'])


def s_riser(c):
    d = c.get('dur', 1.5)
    u = np.linspace(0, 1, int(d * SR))
    x = swept(d, 300, 9000, 0.9, bands=18, shape=lambda v: v ** 1.6) * (u ** 2.4) * 0.5
    air = noise(d, 4000, 0) * u ** 3 * 0.15
    # an accelerating tick train that runs into the hit
    ticks = np.zeros_like(u); tpos = 0.0; k = 0
    while tpos < d - 0.02:
        idx = int(tpos * SR); g = ping(0.02, 2600, 0.003) * (0.15 + 0.6 * (tpos / d) ** 2)
        ticks[idx:idx + len(g)] += g[:len(ticks) - idx]
        tpos += max(0.035, 0.22 * (1 - tpos / d) ** 1.4); k += 1
    add(x + air, c['t'], c['pan'], c['gain'] * 0.8, travel=0.0)
    add(ticks, c['t'], 0.25, c['gain'] * 0.45)
    add(ticks, c['t'] + 0.009, -0.25, c['gain'] * 0.3)


def s_rev(c):
    d = c.get('dur', 0.8)
    u = np.linspace(0, 1, int(d * SR))
    x = noise(d, 300, 7000) * (np.exp(4 * u) - 1) / (np.e ** 4 - 1)
    x[-int(0.01 * SR):] *= np.linspace(1, 0, int(0.01 * SR))
    add(x * 0.5, c['t'] - d, c['pan'], c['gain'])


def s_tick(c):
    x = S(ping(0.03, 3300, 0.004) * 0.5, ping(0.03, 5100, 0.002) * 0.3, noise(0.003, 3000, 0) * 0.2)
    add(x, c['t'], c['pan'], c['gain'] * 0.6)


def s_click(c):
    x = ping(0.02, 4200, 0.0025) * 0.5
    y = ping(0.02, 3100, 0.002) * 0.35
    add(x, c['t'], c['pan'], c['gain'] * 0.6); add(y, c['t'] + 0.045, c['pan'], c['gain'] * 0.5)


def s_key(c):
    k = rng.uniform(0.85, 1.15)
    x = S(ping(0.03, 1800 * k, 0.004) * 0.35, noise(0.01, 1500, 7000) * env(0.01, 0.0005, 0.009, 1) * 0.35)
    add(x, c['t'] + rng.uniform(-0.01, 0.01), c['pan'], c['gain'] * 0.55)


def s_type(c):
    d = c.get('dur', 0.6); tpos = 0.0
    while tpos < d:
        s_key({'t': c['t'] + tpos, 'pan': c['pan'], 'gain': c['gain'] * (0.6 if c.get('soft') else 1)})
        tpos += rng.uniform(0.06, 0.13)


def s_pop(c):
    d = 0.09; t = tt(d)
    f = 380 + 1100 * (1 - np.exp(-t / 0.012))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.018)
    add(S(x * 0.45, noise(0.006, 2000, 0) * 0.08), c['t'], c['pan'], c['gain'] * 0.55)


def s_send(c):
    d = 0.22
    add(swept(d, 700, 6000, 0.6, shape=lambda u: u) * env(d, 0.08, 0.12) * 0.3, c['t'] - 0.1, c['pan'], c['gain'], travel=0.3)
    s_pop({'t': c['t'] + 0.05, 'pan': c['pan'], 'gain': c['gain']})


def s_blip(c):
    fc = [3600, 2600, 1900, 1300][c.get('lane', 1) % 4]
    x = noise(0.035, fc / 1.25, fc * 1.25) * env(0.035, 0.001, 0.03, 2)
    add(x * 0.7, c['t'], c['pan'], c['gain'])


def s_chime(c):
    d = 0.16
    x = S(noise(d, 5000, 13000) * env(d, 0.002, 0.15, 3) * 0.5, noise(0.03, 2200, 3200) * env(0.03, 0.001, 0.028, 2) * 0.35)
    add(x * 1.5, c['t'], c['pan'], c['gain'])


def s_ticks(c):
    d, n = c.get('dur', 0.7), c.get('n', 20)
    for i in range(n):
        s_tick({'t': c['t'] + d * i / n, 'pan': -0.6 + 1.2 * i / n, 'gain': c['gain'] * 0.55})


def s_detent(c):
    for i in range(c.get('n', 4)):
        x = S(ping(0.015, 2400, 0.0018) * 0.4, noise(0.004, 1500, 6000) * 0.15)
        add(x, c['t'] + i * 0.065, c['pan'], c['gain'] * 0.5)


def s_haptic(c):
    for k in (0, 0.075):
        t = tt(0.03)
        x = np.sin(2 * np.pi * 165 * t) * np.sin(np.pi * t / 0.03) ** 2
        add(x * 0.5, c['t'] + k, c['pan'], c['gain'] * 0.6)


def s_data(c):
    d = c.get('dur', 0.7); tpos = 0.0
    while tpos < d:
        s_blip({'t': c['t'] + tpos, 'pan': c['pan'] + rng.uniform(-0.2, 0.2), 'gain': c['gain'] * 0.6, 'lane': int(rng.integers(0, 4))})
        tpos += rng.uniform(0.03, 0.07)


def s_draw(c):
    d = c.get('dur', 1.0)
    x = noise(d, 1800, 6500)
    jitter = np.repeat(rng.uniform(0.5, 1, int(d * 200) + 1), SR // 200)[:len(x)]
    x = x * jitter * env(d, 0.05, 0.12, 1) * 0.16
    add(x, c['t'], c['pan'], c['gain'], travel=0.5)


def s_scan(c):
    d = c.get('dur', 3.5)
    x = swept(d, 900, 4000, 1.0, bands=10, shape=lambda u: u) * env(d, 0.4, 0.5, 1) * 0.1
    add(x, c['t'], -0.3, c['gain'], travel=0.7)


def s_stretch(c):
    d = c.get('dur', 0.8)
    x = swept(d, 5000, 300, 0.7, shape=lambda u: u) * env(d, 0.15, 0.3, 2) * 0.4
    add(x, c['t'], c['pan'], c['gain'])


def s_glitch(c):
    d = c.get('dur', 0.4); n = int(d * SR)
    x = noise(d, 200, 9000)
    hold = np.repeat(x[::24], 24)[:n]  # sample-and-hold crush
    gate = np.repeat(rng.random(int(d * 40) + 1) > 0.35, SR // 40)[:n].astype(float)
    y = np.round(hold * 6) / 6 * gate * env(d, 0.002, 0.08, 1)
    add(y * 0.35, c['t'], -0.3, c['gain']); add(np.roll(y, 311) * 0.35, c['t'], 0.3, c['gain'])


def s_thump(c):
    x = S(drop(0.35, 90, 42, 0.07) * 0.9, noise(0.05, 30, 300) * env(0.05, 0.002, 0.045, 2) * 0.3)
    add(x, c['t'], c['pan'] * 0.3, c['gain'] * 0.8)


def s_snap(c):
    x = S(noise(0.02, 1500, 0) * env(0.02, 0.0003, 0.018, 3) * 0.7, ping(0.08, 1900, 0.01) * 0.3)
    add(x, c['t'], c['pan'], c['gain'] * 0.7)
    add(drop(0.25, 140, 60, 0.05) * 0.4, c['t'], 0, c['gain'])


def s_latch(c):
    metal = sum(ping(0.25, f, dcy) * a for f, dcy, a in [(1870, 0.05, 0.3), (2930, 0.035, 0.22), (4410, 0.02, 0.15), (6120, 0.012, 0.1)])
    for k, g in ((0, 0.7), (0.055, 1.0)):
        add(S(noise(0.008, 2000, 0) * 0.5, metal * g), c['t'] + k, c['pan'], c['gain'] * 0.7)
    add(drop(0.5, 130, 45, 0.12) * 0.7, c['t'] + 0.055, 0, c['gain'])
    l, r = tail(0.8, 400, 6000, 0.18); add_st(l * 0.08, r * 0.08, c['t'] + 0.06, c['gain'])


def s_shimmer(c):
    d = c.get('dur', 1.2)
    t = np.linspace(0, 1, int(d * SR))
    am = 0.7 + 0.3 * np.sin(2 * np.pi * 7 * t * d)
    l = noise(d, 6000, 15000) * np.exp(-t * 3) * am * 0.12
    r = noise(d, 6000, 15000) * np.exp(-t * 3) * am * 0.12
    add_st(l, r, c['t'], c['gain'])


def s_cut(c):
    s_swipe({'t': c['t'], 'pan': c['pan'], 'gain': c['gain'] * 0.8})
    add(drop(0.2, 110, 60, 0.05) * 0.45, c['t'], 0, c['gain'])
    s_tick({'t': c['t'], 'pan': c['pan'], 'gain': c['gain'] * 0.7})


def s_tail(c):
    d = c.get('dur', 1.0)
    l, r = tail(d + 1.0, 100, 3000, 0.5); add_st(l * 0.05, r * 0.05, c['t'], c['gain'])


PLAY = {
    'whoosh': s_whoosh, 'whooshL': lambda c: s_whoosh(c, True), 'swipe': s_swipe, 'slide': s_slide,
    'hit': s_hit, 'boom': s_boom, 'land': s_land, 'riser': s_riser, 'rev': s_rev,
    'tick': s_tick, 'click': s_click, 'key': s_key, 'type': s_type, 'pop': s_pop, 'send': s_send,
    'blip': s_blip, 'chime': s_chime, 'ticks': s_ticks, 'detent': s_detent, 'haptic': s_haptic, 'data': s_data,
    'draw': s_draw, 'scan': s_scan, 'stretch': s_stretch, 'glitch': s_glitch, 'thump': s_thump,
    'snap': s_snap, 'latch': s_latch, 'shimmer': s_shimmer, 'cut': s_cut, 'tail': s_tail,
}
missing = sorted({c['kind'] for c in SPEC['cues']} - PLAY.keys())
assert not missing, missing
for c in SPEC['cues']:
    ot = O(c['t'])
    if ot is not None:
        PLAY[c['kind']](dict(c, t=ot))

# A clockwork pulse under the quieter scenes, so the reel keeps moving
# between its hits: a tick and a softer tock every half second, a low thud on
# the bar, all noise and transients.
for a, b in SPEC.get('pulses', [(25.9, 32.3), (45.8, 52.9), (65.0, 72.5), (74.2, 81.3), (84.0, 88.7)]):
    k, tpos = 0, a
    while tpos < b:
        ramp = min(1, (tpos - a) / 0.8, (b - tpos) / 0.8)
        hi = noise(0.012, 5000 if k % 2 == 0 else 3200, 11000) * env(0.012, 0.0005, 0.011, 2)
        ot = O(tpos)
        if ot is None: k += 1; tpos += 0.5; continue
        add(hi, ot, 0.35 if k % 2 == 0 else -0.35, 0.16 * ramp)
        if k % 4 == 0:
            add(drop(0.25, 75, 45, 0.06), ot, 0, 0.3 * ramp)
        k += 1; tpos += 0.5

# A low room tone under everything after the cold open, so silence between
# events has a floor. It dips at the start and swells into the final hit.
t = np.arange(N) / SR
room_env = np.clip((t - 2.5) / 3, 0, 1) * (1 - np.clip((t - O(SPEC.get('fadeout', 98.8))) / 1.2, 0, 1))
room_env *= 1 + 0.8 * np.exp(-((t - O(SPEC.get('swell', 94.5))) / 1.5) ** 2)
L += noise(DUR, 35, 220) * room_env * 0.035
R += noise(DUR, 35, 220) * room_env * 0.035

# master: gentle glue, then peak at -1 dBFS
mix = np.stack([L, R])
mix = np.tanh(mix * 1.6) / np.tanh(1.6)
mix *= 10 ** (-1 / 20) / np.abs(mix).max()
fade = np.ones(N); fade[:int(0.01 * SR)] = np.linspace(0, 1, int(0.01 * SR))
mix *= fade
pcm = (mix.T * 32767).astype('<i2')
with wave.open(os.path.join(HERE, OUT), 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
rms = np.sqrt((mix ** 2).mean())
print(f'{OUT} {DUR:.1f}s  {len(SPEC["cues"])} cues  rms {20 * np.log10(rms):.1f} dBFS')
