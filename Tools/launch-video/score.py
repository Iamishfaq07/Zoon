# The launch film's sound: a nature soundscape with no musical instruments and
# no melody -- night wind and crickets, soft rain under the breathing scene, a
# guided breath, airy whooshes on the cuts, and birdsong at dawn. Synthesised
# here, so it carries no licence. Writes score.wav next to this file.
import os, wave
import numpy as np

SR = 48000
DUR = 69.0
N = int(SR * DUR)
t = np.arange(N) / SR
rng = np.random.default_rng(5)
L = np.zeros(N); R = np.zeros(N)

def band(x, lo, hi):
    """Band-limit a signal with a soft-edged FFT mask."""
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    m = 1 / (1 + (lo / np.maximum(f, 1)) ** 4) if lo > 0 else np.ones_like(f)
    m = m / (1 + (f / hi) ** 4)
    return np.fft.irfft(X * m, len(x))

def env(a, b, att, rel):
    e = np.zeros(N); i, j = int(a * SR), int(min(b, DUR) * SR)
    s = np.arange(j - i) / SR
    e[i:j] = np.clip(s / att, 0, 1) * np.clip((b - a - s) / rel, 0, 1)
    return e

def add(sig, start, pan=0.5):
    i = int(start * SR); j = min(N, i + len(sig)); sig = sig[: j - i]
    L[i:j] += sig * np.sqrt(1 - pan); R[i:j] += sig * np.sqrt(pan)

night = 1 - np.clip((t - 57.0) / 4.0, 0, 1)          # fades as dawn comes
dawn = np.clip((t - 56.6) / 3.0, 0, 1)

# 1. Wind: two decorrelated low bands that breathe slowly, all the way through.
for ch, out in ((0, L), (1, R)):
    w = band(rng.standard_normal(N), 60, 700)
    w /= np.abs(w).max()
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * 0.045 * t + ch * 1.7) * np.sin(2 * np.pi * 0.11 * t + 0.4)
    air = band(rng.standard_normal(N), 1500, 6000); air /= np.abs(air).max()
    out += (0.20 * w * gust + 0.018 * air * gust) * env(0, DUR, 3, 3)

# 2. Crickets: pulsed high tones in short chirps, three of them, at night only.
for f, pan, rate, off in ((4300, 0.25, 0.62, 0.0), (4750, 0.75, 0.71, 0.3), (5100, 0.5, 0.83, 0.55)):
    pulses = np.zeros(N)
    k = off
    while k < DUR:
        for p in range(3):
            c = int((k + p * 0.05) * SR)
            if c < N:
                pulses[c] = 1.0
        k += rate * (0.85 + 0.3 * rng.random())
    kern_t = np.arange(int(0.018 * SR)) / SR
    kern = np.sin(np.pi * kern_t / kern_t[-1]) ** 2
    shape = np.convolve(pulses, kern)[:N]
    cr = 0.022 * shape * np.sin(2 * np.pi * f * t) * night * env(0.5, DUR, 2, 1)
    L += cr * (1 - pan); R += cr * pan

# 3. Rain under the wind-down scene: a soft hiss plus scattered drops.
rain_env = env(28.6, 36.4, 1.6, 2.0)
hiss = band(rng.standard_normal(N), 900, 9000); hiss /= np.abs(hiss).max()
L += 0.07 * hiss * rain_env; R += 0.07 * np.roll(hiss, 2400) * rain_env
for _ in range(900):
    when = 28.8 + rng.random() * 7.2
    n = int(0.03 * SR); tt = np.arange(n) / SR
    f = 1800 + rng.random() * 4200
    drop = np.sin(2 * np.pi * f * tt * (1 + 3 * tt)) * np.exp(-tt * 180) * (0.02 + 0.03 * rng.random())
    add(drop * np.interp(when, [28.8, 30.0, 34.8, 36.0], [0, 1, 1, 0]), when, rng.random())

# 4. A guided breath in the breathing scene: in, hold, out, following the circle.
bt = t - 29.5
u = np.mod(bt, 6.0)
breath = np.where(u < 1.6, np.sin(np.pi / 2 * u / 1.6) ** 2,
         np.where(u < 3.0, 0.0, np.clip(np.sin(np.pi * np.clip((u - 3.0) / 2.6, 0, 1)), 0, 1) ** 1.5))
breath *= (bt > 0) & (bt < 5.9)
air_b = band(rng.standard_normal(N), 250, 2200); air_b /= np.abs(air_b).max()
L += 0.12 * air_b * breath; R += 0.12 * np.roll(air_b, 900) * breath

# 5. Whooshes on the cuts: rising band of air, panned across.
cuts = [5.4, 11.2, 17.2, 23.0, 29.2, 35.0, 40.6, 46.6, 52.0, 56.6, 62.8]
for k, when in enumerate(cuts):
    n = int(1.3 * SR); tt = np.arange(n) / SR
    x = rng.standard_normal(n)
    lo = band(x, 300, 1400); hi = band(x, 1400, 5000)
    sweep = np.clip(tt / 1.0, 0, 1)
    wh = (lo * (1 - sweep) + hi * sweep) / 3.0
    e = np.sin(np.pi * np.clip(tt / 1.3, 0, 1)) ** 2
    wh *= e * 0.09
    start = when - 0.55
    i = int(start * SR); j = min(N, i + n)
    pan = np.linspace(0.2, 0.8, n) if k % 2 == 0 else np.linspace(0.8, 0.2, n)
    L[i:j] += (wh * np.sqrt(1 - pan))[: j - i]; R[i:j] += (wh * np.sqrt(pan))[: j - i]

# 6. Dawn birdsong: short sweeping calls and trills, thickening into morning.
def call():
    notes = []
    for _ in range(rng.integers(2, 7)):
        d = 0.05 + rng.random() * 0.11
        f0 = 2600 + rng.random() * 3000; f1 = f0 * (0.7 + rng.random() * 0.8)
        n = int(d * SR); tt = np.arange(n) / SR
        f = np.linspace(f0, f1, n) * (1 + 0.02 * np.sin(2 * np.pi * 38 * tt))
        ph = 2 * np.pi * np.cumsum(f) / SR
        notes.append(np.sin(ph) * np.sin(np.pi * tt / d) ** 2)
        notes.append(np.zeros(int((0.02 + rng.random() * 0.06) * SR)))
    return np.concatenate(notes)
when = 57.2
while when < 67.5:
    add(call() * (0.035 + 0.035 * rng.random()) * min(1, (when - 57.0) / 3), when, 0.15 + 0.7 * rng.random())
    when += 0.25 + rng.random() * (1.4 - 0.9 * min(1, (when - 57) / 6))

# Space: a short, soft room reverb by convolution.
def reverb(x, s):
    n = int(2.2 * SR); r = np.random.default_rng(s).standard_normal(n)
    ir = r * np.exp(-np.arange(n) / SR * 2.6); ir /= np.sqrt(np.sum(ir ** 2))
    size = 1 << (len(x) + n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x)]
outL = 0.8 * L + 0.35 * reverb(L, 21)
outR = 0.8 * R + 0.35 * reverb(R, 22)

# Master: fade in and out, gentle limiting, -1 dBFS peak.
m = np.clip(t / 1.5, 0, 1) * np.clip((DUR - 0.5 - t) / 2.0, 0, 1)
outL *= m; outR *= m
assert np.isfinite(outL).all() and np.isfinite(outR).all(), 'mix has NaN/inf'
pk = max(np.abs(outL).max(), np.abs(outR).max())
outL = np.tanh(outL / pk * 1.4); outR = np.tanh(outR / pk * 1.4)
g = 10 ** (-1 / 20) / max(np.abs(outL).max(), np.abs(outR).max())
pcm = (np.stack([outL, outR], 1) * g * 32767).astype('<i2')
with wave.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'score.wav'), 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
print('ok', pcm.shape)
