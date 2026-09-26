# The launch film score: an original ambient piece, synthesised here so it
# carries no licence. Writes score.wav next to this file for render.js.
import numpy as np, wave
SR = 48000; DUR = 57.0; N = int(SR * DUR)
t = np.arange(N) / SR
rng = np.random.default_rng(3)
L = np.zeros(N); R = np.zeros(N)

def hz(m): return 440.0 * 2 ** ((m - 69) / 12)

def env(start, end, att, rel):
    e = np.zeros(N)
    a, b = int(start * SR), int(min(end, DUR) * SR)
    seg = np.arange(b - a) / SR
    e[a:b] = np.minimum(1, seg / att) * np.minimum(1, np.maximum(0, (end - start - seg) / rel))
    return e

def pad_voice(m, start, end, gain, pan):
    f = hz(m)
    e = env(start, end, 2.2, 2.6) ** 1.5
    ph = rng.random() * 6.28
    lfo = 1 + 0.004 * np.sin(2 * np.pi * 0.13 * t + ph)
    sig = np.zeros(N)
    for det, g in ((-0.07, 0.5), (0.0, 0.8), (0.06, 0.5)):
        w = 2 * np.pi * f * (1 + det / 100) * lfo
        phase = np.cumsum(w) / SR
        sig += g * (np.sin(phase + ph) + 0.18 * np.sin(2 * phase) + 0.05 * np.sin(3 * phase))
    sig *= e * gain
    return sig * (1 - pan), sig * pan

# Chords: (start, end, midi notes). D major world, ending home.
chords = [
    (0.0, 11.8,  [50, 57, 62, 66, 69, 76]),      # Dmaj9-ish: moon, the watch
    (11.2, 23.8, [47, 54, 59, 62, 66, 73]),      # Bm9: the night, tonight's need
    (23.0, 35.8, [43, 50, 55, 59, 66, 69]),      # Gmaj7 add9: coach, wind down
    (35.0, 47.0, [45, 52, 57, 61, 64, 71]),      # A6/9: body clock, everywhere
    (46.2, 57.0, [50, 57, 62, 66, 69, 73, 76]),  # Dmaj9 home: privacy, end card
]
for s, e, notes in chords:
    for i, m in enumerate(notes):
        pan = 0.3 + 0.4 * (i / (len(notes) - 1))
        g = 0.05 if m > 60 else 0.07
        l, r = pad_voice(m, s, e, g, pan); L += l; R += r

# Sub drone on the root of each chord.
for s, e, notes in chords:
    root = notes[0] - 12
    e_ = env(s, e, 2.5, 2.5)
    sub = 0.09 * np.sin(2 * np.pi * hz(root) * t) * e_
    L += sub; R += sub

# Bell motif on each scene change: soft FM-ish bell, pentatonic in D.
bells = [(1.7, 81), (2.6, 78), (5.6, 76), (8.6, 81), (11.4, 74), (17.4, 78), (23.2, 76),
         (29.4, 81), (29.8, 83), (35.2, 78), (40.8, 74), (46.8, 81), (51.6, 81), (52.4, 78), (53.4, 86)]
for when, m in bells:
    a = int(when * SR); n = int(4.5 * SR); b = min(N, a + n)
    tt = np.arange(b - a) / SR
    f = hz(m)
    dec = np.exp(-tt * 1.6)
    mod = 1.4 * np.exp(-tt * 3) * np.sin(2 * np.pi * f * 2.0 * tt)
    bell = (np.sin(2 * np.pi * f * tt + mod) + 0.25 * np.sin(2 * np.pi * f * 2.76 * tt) * np.exp(-tt * 3)) * dec
    bell *= np.minimum(1, tt / 0.004) * 0.06
    pan = 0.35 + 0.3 * rng.random()
    L[a:b] += bell * (1 - pan); R[a:b] += bell * pan

# A soft pulse at resting heart rate under the feature scenes.
bpm = 64; beat = 60 / bpm
for k in range(int((46.2 - 11.2) / beat)):
    when = 11.2 + k * beat
    a = int(when * SR); n = int(0.5 * SR); b = min(N, a + n)
    tt = np.arange(b - a) / SR
    swell = min(1, k / 6) * (1 - max(0, (when - 42.4) / 3.8))
    thump = np.sin(2 * np.pi * (58 + 40 * np.exp(-tt * 30)) * tt) * np.exp(-tt * 9) * 0.10 * swell
    L[a:b] += thump; R[a:b] += thump

# Air: filtered noise bed that breathes.
noise = rng.standard_normal((2, N))
k = np.exp(-2 * np.pi * 900 / SR)
for ch in range(2):
    y = np.zeros(N); acc = 0.0
    # vectorised one-pole low-pass via lfilter-like cumulative trick
    from itertools import accumulate
    y = np.array(list(accumulate(noise[ch], lambda p, x: k * p + (1 - k) * x)))
    breath = 0.012 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.07 * t + ch)) * env(0, DUR, 3, 3)
    (L if ch == 0 else R)[:] += y * breath

# Hall reverb: convolution with a decaying stereo noise tail.
def reverb(x, seed):
    ir_len = int(3.8 * SR)
    r = np.random.default_rng(seed).standard_normal(ir_len)
    tt = np.arange(ir_len) / SR
    ir = r * np.exp(-tt * 1.9)
    ir[: int(0.02 * SR)] *= np.linspace(0, 1, int(0.02 * SR))
    ir /= np.sqrt(np.sum(ir ** 2))
    n = len(x) + ir_len
    size = 1 << (n - 1).bit_length()
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x)]
    return y

wetL, wetR = reverb(L, 11), reverb(R, 12)
outL = 0.7 * L + 0.55 * wetL
outR = 0.7 * R + 0.55 * wetR

# Master: fade in and out, soft limit, normalise to -1 dBFS.
master = np.minimum(1, t / 1.5) * np.minimum(1, np.maximum(0, (DUR - t) / 2.5))
outL *= master; outR *= master
peak = max(np.abs(outL).max(), np.abs(outR).max())
outL, outR = np.tanh(outL / peak * 1.1) , np.tanh(outR / peak * 1.1)
peak = max(np.abs(outL).max(), np.abs(outR).max())
g = 10 ** (-1 / 20) / peak
stereo = np.stack([outL * g, outR * g], axis=1)
pcm = (stereo * 32767).astype('<i2')
import os
with wave.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'score.wav'), 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
print('ok', stereo.shape)
