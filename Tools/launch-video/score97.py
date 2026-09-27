# The launch film's sound, scored to the picture. No musical instruments and no
# melody: every sound is something you would hear at night or on a phone, and
# each one lands on something that happens on screen.
#
#   hook       a bedside clock ticking; a soft low thump under "So why are you tired?"
#   moon       wind rising with the moon, a shimmer as the shooting star crosses
#   AI         five soft pops as the readings leave the Watch, data crackle along
#              the streams, an airy swell as the network lights, a bloom at the moon
#   night      a sleeper's slow breathing and a quiet heartbeat under the chart
#   tour       finger taps, a swish as each screen slides, a push-in as it zooms
#   coach      message sent, key taps under the typed answer, a pop for the chip
#   ladder     four steps, each a little brighter
#   breathing  a real in-hold-out breath with the circle, rain for Sleep Sounds
#   body clock clock ticking as the hand sweeps, a click at each marker
#   tools      three phones swoosh in, a soft snore under Snore Check
#   watch      a haptic double tap as each face arrives
#   plan       a click for each time on the line
#   privacy    a latch snapping shut as the cloud link breaks
#   morning    crickets give way to birds and a stream
#   end        a soft landing under the icon
#
# Scene times are on the story clock (65.9 s); timemap.json (exported by dur.js
# from film60.html) maps them to output time so sound and picture stay locked.
import json, os, wave
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TM = json.load(open(os.path.join(HERE, 'timemap.json')))
_x = np.arange(len(TM['out'])) * TM['step']; _y = np.array(TM['out'])
def O(t):
    """Story time -> output time."""
    return float(np.interp(t, _x, _y))

SR = 48000
DUR = _y[-1]
N = int(SR * DUR)
t = np.arange(N) / SR
rng = np.random.default_rng(11)
L = np.zeros(N); R = np.zeros(N)

def band(x, lo, hi):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    m = 1 / (1 + (lo / np.maximum(f, 1)) ** 4) if lo > 0 else np.ones_like(f)
    m = m / (1 + (f / hi) ** 4)
    return np.fft.irfft(X * m, len(x))

def noise(sec, lo, hi):
    x = band(rng.standard_normal(int(sec * SR)), lo, hi)
    return x / (np.abs(x).max() + 1e-9)

def span(a, b, att, rel):
    """Envelope over output seconds a..b."""
    e = np.zeros(N); i, j = int(a * SR), int(min(b, DUR) * SR)
    s = np.arange(j - i) / SR
    e[i:j] = np.clip(s / att, 0, 1) * np.clip((b - a - s) / rel, 0, 1)
    return e

def add(sig, start, pan=0.5, gain=1.0):
    i = int(start * SR)
    if i >= N: return
    if i < 0: sig = sig[-i:]; i = 0
    j = min(N, i + len(sig)); sig = sig[: j - i] * gain
    L[i:j] += sig * np.sqrt(1 - pan); R[i:j] += sig * np.sqrt(pan)

def dec(sec, rate):
    return np.exp(-np.arange(int(sec * SR)) / SR * rate)

# ---------- sound objects ----------
def tick(bright=1.0):
    n = 0.03; return noise(n, 1500 * bright, 7000) * dec(n, 220) * 0.5 + noise(n, 300, 1200) * dec(n, 120) * 0.25

def thump(sec=0.6, lo=40, hi=160):
    return noise(sec, lo, hi) * dec(sec, 7) * np.sin(np.pi * np.clip(np.arange(int(sec * SR)) / SR / 0.02, 0, 0.5))

def pop(bright=1.0):
    n = 0.09; x = noise(n, 500 * bright, 3500 * bright) * dec(n, 60)
    return x + noise(n, 90, 300) * dec(n, 40) * 0.6

def tap():
    n = 0.07; return noise(n, 700, 5000) * dec(n, 140) * 0.8 + noise(n, 120, 500) * dec(n, 70) * 0.5

def swish(sec=0.5, lo=900, hi=7000):
    tt = np.arange(int(sec * SR)) / SR
    return noise(sec, lo, hi) * np.sin(np.pi * tt / sec) ** 2

def whoosh(sec=1.6):
    tt = np.arange(int(sec * SR)) / SR; u = tt / sec; x = rng.standard_normal(len(tt))
    y = band(x, 200, 1100) * (1 - u) + band(x, 1100, 5000) * u
    return y / np.abs(y).max() * np.sin(np.pi * u) ** 2

def rise(sec, lo=(200, 900), hi=(2500, 7000)):
    tt = np.arange(int(sec * SR)) / SR; u = tt / sec; x = rng.standard_normal(len(tt))
    y = band(x, *lo) * (1 - u) + band(x, *hi) * u
    return y / np.abs(y).max() * np.sin(np.pi * np.clip(u * 0.5 + 0.5 * u ** 2, 0, 1)) ** 1.5

def shimmer(sec):
    tt = np.arange(int(sec * SR)) / SR; u = tt / sec
    y = noise(sec, 5000, 12000) * (0.4 + 0.6 * (np.sin(2 * np.pi * 23 * tt) > 0.6))
    return y * np.sin(np.pi * u) ** 2

# ---------- beds (each scene has its own air) ----------
def bed(fr, to, lo, hi, gain, att=1.2, rel=1.5, flutter=0.0, seed=0):
    a, b = O(fr), O(to)
    for pan, out in ((0, L), (1, R)):
        x = band(np.random.default_rng(seed + pan).standard_normal(N), lo, hi); x /= np.abs(x).max()
        g = 1 + flutter * np.sin(2 * np.pi * 0.09 * t + pan * 1.9) * np.sin(2 * np.pi * 0.23 * t)
        out += x * g * span(a, b, att, rel) * gain

# night air: low wind under the whole night, quieter than before so events read
bed(0, 60.5, 60, 600, 0.10, 2.5, 3.0, flutter=0.45, seed=1)
bed(3.3, 7.4, 150, 1400, 0.12, 2.0, 1.2, flutter=0.3, seed=3)          # moon: wind rises
bed(7.1, 12.3, 1200, 6000, 0.025, 1.0, 1.0, seed=5)                    # AI: faint electric air
bed(12.0, 16.4, 80, 500, 0.06, 1.0, 1.0, seed=7)                       # night room
bed(59.1, 66.4, 200, 2500, 0.05, 2.5, 2.0, seed=9)                     # morning air

# crickets from the moon to the privacy scene, very light
for f, pan, rate, off in ((4300, 0.25, 0.62, 0.0), (4750, 0.75, 0.71, 0.3)):
    pulses = np.zeros(N); k = O(3.8) + off
    while k < O(60.5):
        for p in range(3):
            c = int((k + p * 0.05) * SR)
            if c < N: pulses[c] = 1.0
        k += rate * (0.85 + 0.3 * rng.random())
    kt = np.arange(int(0.018 * SR)) / SR; kern = np.sin(np.pi * kt / kt[-1]) ** 2
    cr = 0.010 * np.convolve(pulses, kern)[:N] * np.sin(2 * np.pi * f * t)
    cr *= span(O(3.8), O(60.5), 3, 3) * (1 - 0.7 * span(O(7.1), O(12.1), 0.8, 0.8)) * (1 - 0.7 * span(O(16.1), O(35.1), 1, 1))
    L += cr * (1 - pan); R += cr * pan

# ---------- H. hook: a bedside clock ----------
k = O(0.1); i = 0
while k < O(3.45):
    add(tick(1.0 if i % 2 == 0 else 0.7), k, 0.62 if i % 2 == 0 else 0.58, 0.16); k += 0.52; i += 1
add(thump(0.9, 35, 140), O(1.15), 0.5, 0.55)
add(swish(0.9, 300, 2500) * 0.4, O(1.05), 0.5, 0.25)

# ---------- 1. moon ----------
add(rise(O(5.8) - O(3.3), (150, 700), (700, 2500)), O(3.3), 0.5, 0.12)
add(shimmer(O(5.8) - O(5.1)), O(5.1), 0.8, 0.10); add(shimmer(O(5.8) - O(5.1)), O(5.15), 0.4, 0.07)
add(thump(1.2, 30, 110), O(4.3), 0.5, 0.25)

# ---------- 2. AI ----------
for i in range(5):
    add(pop(1 + 0.12 * i), O(7.1 + 0.65 + i * 0.12), 0.3 + 0.1 * i, 0.22)
for _ in range(160):                                          # data crackle along the streams
    w = O(8.2) + rng.random() * (O(10.9) - O(8.2))
    add(noise(0.012, 3000, 10000) * dec(0.012, 400), w, 0.25 + 0.5 * rng.random(), 0.05 + 0.04 * rng.random())
add(rise(O(10.3) - O(8.2)), O(8.2), 0.4, 0.16); add(rise(O(10.3) - O(8.2)), O(8.25), 0.6, 0.12)
bloom = noise(2.2, 60, 400) * dec(2.2, 2.2) * np.sin(np.pi * np.clip(np.arange(int(2.2 * SR)) / SR / 0.3, 0, 0.5))
add(bloom, O(9.1), 0.7, 0.45); add(shimmer(1.4), O(9.15), 0.75, 0.07)
add(swish(0.8, 400, 3000), O(9.2), 0.5, 0.10)                 # caption change

# ---------- 3. night: breathing sleeper and a heartbeat ----------
k = O(12.3)
while k < O(16.1) - 0.4:
    add(thump(0.22, 35, 120), k, 0.5, 0.26); add(thump(0.2, 35, 110), k + 0.28, 0.5, 0.16); k += 1.05
sl = np.zeros(N); u = t - O(12.2)
sl = np.where((u > 0) & (t < O(16.1)), np.sin(np.pi * np.mod(u, 4.2) / 4.2) ** 2, 0)
air = band(rng.standard_normal(N), 200, 1500); air /= np.abs(air).max()
L += 0.05 * air * sl; R += 0.05 * np.roll(air, 700) * sl
add(swish(O(15.0) - O(12.4), 1500, 6000) * 0.5, O(12.4), 0.5, 0.05)  # the playhead sweeping

# ---------- T. tour ----------
TOUR = [0.6, 3.0, 5.6]
for i, at in enumerate(TOUR):
    s = 16.1 + at
    add(tap(), O(s + 0.3), 0.6, 0.30)
    if i: add(swish(0.45, 1200, 6500), O(s + 0.15), 0.7, 0.09)
    zs = s + (0.35 if i == 0 else 0.75); ze = s + (1.0 if i == 0 else 1.35)
    add(rise(O(ze) - O(zs) + 0.25, (200, 800), (800, 3500)), O(zs), 0.5, 0.10)
    if i < 2: add(swish(0.6, 400, 2500) * 0.6, O(s + 2.0), 0.4, 0.06)

# ---------- 5. coach ----------
s = 24.4
add(swish(0.35, 1500, 7000), O(s + 1.0), 0.7, 0.10); add(pop(1.3), O(s + 1.05), 0.7, 0.14)
n = 16; a, b = O(s + 2.0), O(s + 2.8)
for i in range(n):
    add(tick(1.2), a + (b - a) * i / n + rng.random() * 0.02, 0.35 + 0.1 * rng.random(), 0.10)
add(pop(1.1), O(s + 2.9), 0.4, 0.16)

# ---------- L. evidence ladder: four steps, brighter each time ----------
for i in range(4):
    w = O(29.9 + 1.0 + i * 0.75)
    add(pop(0.8 + 0.35 * i), w, 0.25 + 0.17 * i, 0.22); add(thump(0.3, 50 + 15 * i, 220), w, 0.5, 0.18)
add(rise(O(33.3) - O(30.6), (150, 600), (600, 2500)) * 0.6, O(30.6), 0.5, 0.08)

# ---------- 6. breathing + rain ----------
s6 = 35.1
rain = span(O(s6 + 0.6), O(39.4), 1.5, 1.2)
hiss = band(rng.standard_normal(N), 800, 9000); hiss /= np.abs(hiss).max()
L += 0.05 * hiss * rain; R += 0.05 * np.roll(hiss, 2400) * rain
for _ in range(700):
    w = O(s6 + 0.7) + rng.random() * (O(39.2) - O(s6 + 0.7))
    n = int(0.025 * SR); tt = np.arange(n) / SR
    add(np.sin(2 * np.pi * (1800 + rng.random() * 3500) * tt * (1 + 3 * tt)) * np.exp(-tt * 190), w, rng.random(), 0.012 + 0.02 * rng.random())
# the breath follows the circle: story u in [0,1.6) in, [1.6,3.0) hold, [3.0,5.6) out
def story_of(T):
    return np.interp(T, _y, _x)
st = story_of(t) - (s6 + 0.3)
u = np.mod(st, 6.0)
br = np.where(u < 1.6, np.sin(np.pi / 2 * u / 1.6) ** 2 * 0.8,
     np.where(u < 3.0, 0.0, np.sin(np.pi * np.clip((u - 3.0) / 2.6, 0, 1)) ** 1.2))
br *= (st > 0) & (story_of(t) < 39.1)
airb = band(rng.standard_normal(N), 250, 2400); airb /= np.abs(airb).max()
L += 0.10 * airb * br; R += 0.10 * np.roll(airb, 900) * br

# ---------- 7. body clock: ticking as the hand sweeps, a click per marker ----------
s7 = 39.2; sweep_a, sweep_b = O(s7 + 0.4), O(s7 + 3.0)
k = sweep_a; i = 0
while k < sweep_b:
    add(tick(0.9 if i % 2 else 1.1), k, 0.5, 0.09); p = (k - sweep_a) / (sweep_b - sweep_a)
    k += 0.09 + 0.25 * abs(p - 0.5) * 2; i += 1       # quicker mid-sweep, like the eased hand
MARKS = [6.77, 8.27, 10.45, 13.58, 22.37]           # the film's MARKS (hours)
for j, h in enumerate(MARKS):
    f = (h - 5.5) / (23.2 - 5.5)
    # the hand is eased, so invert easeIO to find when it reaches the marker
    xs = np.linspace(0, 1, 2001); e = np.where(xs < 0.5, 4 * xs ** 3, 1 - (-2 * xs + 2) ** 3 / 2)
    lt = s7 + 0.4 + 2.6 * np.interp(f, e, xs)
    add(pop(1.4), O(lt), 0.3 + 0.1 * j, 0.10)

# ---------- P. sleep tools ----------
s = 43.3
for i, d in enumerate([0.45, 0.25, 0.65]):
    add(swish(0.55, 500, 4000), O(s + d), [0.25, 0.5, 0.75][i], 0.10)
sn_a, sn_b = O(s + 1.1), O(46.9)
sn = np.zeros(N); v = t - sn_a
cyc = np.mod(v, 2.6)
sn = np.where((v > 0) & (t < sn_b), np.clip(np.sin(np.pi * cyc / 1.1), 0, 1) * (cyc < 1.1), 0)
flutter = 0.5 + 0.5 * np.sin(2 * np.pi * 28 * t)
snore = band(rng.standard_normal(N), 70, 520); snore /= np.abs(snore).max()
L += 0.07 * snore * sn * flutter * span(sn_a, sn_b, 0.5, 0.8)
R += 0.035 * snore * sn * flutter * span(sn_a, sn_b, 0.5, 0.8)

# ---------- W. watch faces: a haptic double tap each ----------
s = 47.4
for i in range(5):
    d = 0.2 if i == 2 else 1.0 + [0, 0.12, 0, 0.24, 0.36][i]
    w = O(s + d + 0.35)
    add(thump(0.12, 60, 200), w, 0.2 + 0.15 * i, 0.30 if i == 2 else 0.16)
    add(thump(0.12, 60, 200), w + 0.11, 0.2 + 0.15 * i, 0.20 if i == 2 else 0.11)
add(shimmer(1.6), O(s + 0.3), 0.5, 0.05)

# ---------- 8. plan: a click per time ----------
s = 51.7
add(swish(0.6, 500, 4000), O(s + 0.4), 0.75, 0.08)
for i in range(5):
    add(pop(1.0 + 0.1 * i), O(s + 0.8 + i * 0.45), 0.2 + 0.15 * i, 0.15)

# ---------- 9. privacy: the latch ----------
s = 55.6
add(rise(O(s + 1.8) - O(s + 0.6), (200, 900), (900, 3000)) * 0.7, O(s + 0.6), 0.7, 0.07)
snap = noise(0.05, 1500, 8000) * dec(0.05, 120)
add(snap, O(s + 1.8), 0.7, 0.30); add(thump(0.5, 40, 180), O(s + 1.82), 0.5, 0.40)

# ---------- M. morning: birds and a stream ----------
def call():
    notes = []
    for _ in range(rng.integers(2, 7)):
        d = 0.05 + rng.random() * 0.11
        f0 = 2600 + rng.random() * 3000; f1 = f0 * (0.7 + rng.random() * 0.8)
        n = int(d * SR); tt = np.arange(n) / SR
        f = np.linspace(f0, f1, n) * (1 + 0.02 * np.sin(2 * np.pi * 38 * tt))
        notes.append(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / d) ** 2)
        notes.append(np.zeros(int((0.02 + rng.random() * 0.06) * SR)))
    return np.concatenate(notes)
w = O(59.4); a = O(59.3)
while w < DUR - 1.2:
    ramp = min(1, (w - a) / 3)
    add(call(), w, 0.15 + 0.7 * rng.random(), 0.02 + 0.03 * rng.random() * ramp + 0.01)
    w += 0.3 + rng.random() * (1.2 - 0.7 * ramp)
stream = span(O(59.3), DUR, 3.0, 2.0)
for pan, out in ((0, L), (1, R)):
    x = band(np.random.default_rng(40 + pan).standard_normal(N), 400, 5000); x /= np.abs(x).max()
    gurgle = 0.6 + 0.4 * np.abs(np.sin(2 * np.pi * (3.1 + pan) * t) * np.sin(2 * np.pi * 0.7 * t))
    out += 0.035 * x * gurgle * stream
add(swish(0.7, 800, 4000), O(59.1 + 1.0), 0.5, 0.08)          # notification drops in

# ---------- 10. end card: a soft landing ----------
add(thump(1.6, 30, 120), O(62.6), 0.5, 0.45); add(shimmer(1.8), O(62.6), 0.5, 0.05)

# ---------- cuts: a slow, soft whoosh through every dissolve ----------
for k_, c in enumerate([3.3, 7.1, 12.0, 16.1, 24.4, 29.9, 35.1, 39.2, 43.3, 47.4, 51.7, 55.6, 59.1, 62.5]):
    a, b = O(c - 0.55), O(c + 0.55)
    wh = whoosh(b - a); n = len(wh)
    pan = np.linspace(0.25, 0.75, n) if k_ % 2 == 0 else np.linspace(0.75, 0.25, n)
    i = int(a * SR); j = min(N, i + n)
    L[i:j] += (0.07 * wh * np.sqrt(1 - pan))[: j - i]; R[i:j] += (0.07 * wh * np.sqrt(pan))[: j - i]

# ---------- space and master ----------
def reverb(x, s, sec=2.4, decay=2.4):
    n = int(sec * SR); r = np.random.default_rng(s).standard_normal(n)
    ir = r * np.exp(-np.arange(n) / SR * decay); ir = band(ir, 150, 7000); ir /= np.sqrt(np.sum(ir ** 2))
    size = 1 << (len(x) + n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x)]
outL = 0.82 * L + 0.30 * reverb(L, 21); outR = 0.82 * R + 0.30 * reverb(R, 22)
# gentle high-shelf tame so nothing is hissy on phone speakers
outL = outL - 0.35 * band(outL, 9000, 20000); outR = outR - 0.35 * band(outR, 9000, 20000)
m = np.clip(t / 1.2, 0, 1) * np.clip((DUR - 0.3 - t) / 2.5, 0, 1)
outL *= m; outR *= m
assert np.isfinite(outL).all() and np.isfinite(outR).all(), 'mix has NaN/inf'
pk = max(np.abs(outL).max(), np.abs(outR).max())
outL = np.tanh(outL / pk * 1.6); outR = np.tanh(outR / pk * 1.6)
g = 10 ** (-1 / 20) / max(np.abs(outL).max(), np.abs(outR).max())
pcm = (np.stack([outL, outR], 1) * g * 32767).astype('<i2')
with wave.open(os.path.join(HERE, 'score97.wav'), 'wb') as w_:
    w_.setnchannels(2); w_.setsampwidth(2); w_.setframerate(SR); w_.writeframes(pcm.tobytes())
rms = np.sqrt(np.mean((pcm / 32767.0) ** 2))
print('ok', pcm.shape, f'{DUR:.2f}s', f'rms {20*np.log10(rms):.1f} dBFS')
