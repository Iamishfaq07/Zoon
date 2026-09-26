# /brag sound: no instruments. Night wind and crickets, a whoosh on each cut,
# soft key taps under the typed Coach answer, birdsong at dawn. One room reverb.
import os, wave
import numpy as np
SR = 48000; DUR = 21.0; N = int(SR * DUR); t = np.arange(N) / SR
rng = np.random.default_rng(9); L = np.zeros(N); R = np.zeros(N)
def band(x, lo, hi):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    m = (1 / (1 + (lo / np.maximum(f, 1)) ** 4) if lo > 0 else 1) / (1 + (f / hi) ** 4)
    return np.fft.irfft(X * m, len(x))
def add(sig, start, pan=0.5):
    i = int(start * SR); j = min(N, i + len(sig))
    L[i:j] += sig[: j - i] * np.sqrt(1 - pan); R[i:j] += sig[: j - i] * np.sqrt(pan)
night = 1 - np.clip((t - 18.2) / 2.0, 0, 1)
fadein = np.clip(t / 0.8, 0, 1)
for ch, out in ((0, L), (1, R)):
    w = band(rng.standard_normal(N), 60, 700); w /= np.abs(w).max()
    gust = 0.6 + 0.4 * np.sin(2 * np.pi * 0.09 * t + ch * 1.7)
    air = band(rng.standard_normal(N), 1500, 6000); air /= np.abs(air).max()
    out += (0.2 * w + 0.016 * air) * gust * fadein
for f, pan, rate, off in ((4300, 0.25, 0.62, 0.1), (4750, 0.75, 0.71, 0.4), (5100, 0.5, 0.83, 0.6)):
    pulses = np.zeros(N); k = off
    while k < DUR:
        for p in range(3):
            c = int((k + p * 0.05) * SR)
            if c < N: pulses[c] = 1
        k += rate * (0.85 + 0.3 * rng.random())
    kt = np.arange(int(0.018 * SR)) / SR; kern = np.sin(np.pi * kt / kt[-1]) ** 2
    cr = 0.02 * np.convolve(pulses, kern)[:N] * np.sin(2 * np.pi * f * t) * night * fadein
    L += cr * (1 - pan); R += cr * pan
for k, when in enumerate([3.55, 6.95, 10.75, 15.55, 18.35]):
    n = int(1.3 * SR); tt = np.arange(n) / SR; x = rng.standard_normal(n)
    sw = np.clip(tt, 0, 1); wh = (band(x, 300, 1400) * (1 - sw) + band(x, 1400, 5000) * sw) / 3
    wh *= np.sin(np.pi * np.clip(tt / 1.3, 0, 1)) ** 2 * 0.1
    i = int((when - 0.6) * SR); j = min(N, i + n)
    pan = np.linspace(0.2, 0.8, n) if k % 2 == 0 else np.linspace(0.8, 0.2, n)
    L[i:j] += (wh * np.sqrt(1 - pan))[: j - i]; R[i:j] += (wh * np.sqrt(pan))[: j - i]
for i in range(14):   # key taps while the Coach answer types (12.05-12.85 s)
    when = 12.05 + i * 0.058 + rng.random() * 0.015
    n = int(0.025 * SR); tt = np.arange(n) / SR
    tap = band(rng.standard_normal(n), 1800, 7000) * np.exp(-tt * 260) * 0.05
    add(tap, when, 0.4 + 0.2 * rng.random())
def call():
    parts = []
    for _ in range(rng.integers(2, 6)):
        d = 0.05 + rng.random() * 0.1; f0 = 2600 + rng.random() * 3000; f1 = f0 * (0.7 + rng.random() * 0.8)
        n = int(d * SR); tt = np.arange(n) / SR
        f = np.linspace(f0, f1, n) * (1 + 0.02 * np.sin(2 * np.pi * 38 * tt))
        parts += [np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / d) ** 2, np.zeros(int((0.02 + rng.random() * 0.05) * SR))]
    return np.concatenate(parts)
when = 18.6
while when < 20.4:
    add(call() * (0.04 + 0.03 * rng.random()), when, 0.15 + 0.7 * rng.random()); when += 0.2 + rng.random() * 0.4
def reverb(x, s):
    n = int(2.0 * SR); ir = np.random.default_rng(s).standard_normal(n) * np.exp(-np.arange(n) / SR * 2.8); ir /= np.sqrt((ir ** 2).sum())
    size = 1 << (len(x) + n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x)]
oL = 0.8 * L + 0.35 * reverb(L, 1); oR = 0.8 * R + 0.35 * reverb(R, 2)
m = np.clip((DUR - 0.2 - t) / 1.0, 0, 1); oL *= m; oR *= m
assert np.isfinite(oL).all() and np.isfinite(oR).all()
pk = max(np.abs(oL).max(), np.abs(oR).max()); oL = np.tanh(oL / pk * 1.4); oR = np.tanh(oR / pk * 1.4)
g = 10 ** (-1 / 20) / max(np.abs(oL).max(), np.abs(oR).max())
pcm = (np.stack([oL, oR], 1) * g * 32767).astype('<i2')
with wave.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'score.wav'), 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
print('ok')
