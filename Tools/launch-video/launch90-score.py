#!/usr/bin/env python3
"""The Zoon launch film's score: launch90-score.wav.

Ninety seconds of cinematic electronic music on the film's 120 BPM clock, in D
minor until the last two seconds, where the sonic logo lands on D major -- the
one bright chord, for the better night the film ends on. Every sound effect the
film asks for (window.CUES) is synthesised here too, at its frame.

    node launch90-render.js cues    # the film's cues and section markers
    python launch90-score.py        # -> launch90-score.wav (48 kHz, 24-bit)

Nothing is sampled: sines, band-limited saws and shaped noise, a synthesised
room, sidechain, glue compression and a lookahead limiter, mastered to about
-14 LUFS with true peaks at or under -1 dBTP. Section boundaries come from the
film's MUSIC markers, so a re-cut film only needs the two commands above. The
script prints its loudness, an energy table per section and a click check, and
writes a spectrogram to %TEMP%/zoon-film/score-spectrum.png for review.
"""
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import time
import wave

import numpy as np
from scipy import signal
from scipy.ndimage import minimum_filter1d, uniform_filter1d

HERE = os.path.dirname(os.path.abspath(__file__))
CUES_PATH = os.path.join(HERE, 'launch90-cues.json')
OUT_PATH = os.path.join(HERE, 'launch90-score.wav')
SR = 48000
TARGET_LUFS = -14.0
TP_LIMIT = -1.0

with open(CUES_PATH, encoding='utf-8') as fh:
    FILM = json.load(fh)
DUR = float(FILM.get('duration', 90))
BPM = float(FILM.get('bpm', 120))
BEAT = 60.0 / BPM
N = int(round(DUR * SR))

# Where each section starts. The film's markers win; these are the brief's.
DEFAULT_MARKS = dict(intro=0, question=4, wave=8, reveal=11, build=13, score=18, stages=23, patterns=29, coach=39,
                     tonight=45, tools=50, drop=56, snore=61, watch=66, dawn=71, montage=76, pullback=82, moon=85, logo=88)


# ---------------------------------------------------------------- basics
def S(t):
    return int(round(t * SR))


def hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def rcos(n):
    """A raised-cosine ramp from 0 to 1 over n samples."""
    if n <= 0:
        return np.zeros(0)
    return 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, n))


def ar(n, attack, release):
    """Unity with a smooth attack and release, n samples long."""
    e = np.ones(n)
    a = min(n, max(1, S(attack)))
    e[:a] = rcos(a)
    r = min(n - a, max(1, S(release)))
    if r > 0:
        e[n - r:] *= rcos(r)[::-1]
    return e


def gate(n, hold, attack, release):
    """Attack, hold for `hold` seconds, then release to silence."""
    e = np.zeros(n)
    h = min(n, S(hold))
    a = min(h, max(1, S(attack)))
    e[:a] = rcos(a)
    e[a:h] = 1.0
    r = min(n - h, max(1, S(release)))
    e[h:h + r] = rcos(r)[::-1]
    return e


def pan_lr(pan):
    """A balance pan: centre is unity in both channels."""
    pan = min(1.0, max(-1.0, float(pan)))
    return math.cos(max(0.0, pan) * math.pi / 2), math.cos(max(0.0, -pan) * math.pi / 2)


def stereo(x, pan=0.0):
    if x.ndim == 2:
        return x
    gl, gr = pan_lr(pan)
    return np.vstack([x * gl, x * gr])


class Bus:
    def __init__(self, name):
        self.name = name
        self.x = np.zeros((2, N), np.float32)

    def put(self, t0, sig, pan=0.0, gain=1.0):
        """Mix a mono or stereo signal in, starting at t0 seconds."""
        sig = stereo(sig, pan) if sig.ndim == 1 else sig * np.array(pan_lr(pan))[:, None]
        i0 = S(t0)
        n = sig.shape[1]
        a, b = max(0, i0), min(N, i0 + n)
        if b > a:
            self.x[:, a:b] += (sig[:, a - i0:b - i0] * gain).astype(np.float32)


def keyfn(keys, log=False):
    """A function of absolute time through (t, value) keys, linear (or log)."""
    ts = np.array([k[0] for k in keys], float)
    vs = np.array([k[1] for k in keys], float)
    if log:
        lv = np.log(np.maximum(vs, 1e-9))
        return lambda t: np.exp(np.interp(t, ts, lv))
    return lambda t: np.interp(t, ts, vs)


def curve(keys, log=False):
    return keyfn(keys, log)(np.arange(N) / SR)


# ---------------------------------------------------------------- oscillators
def saw(freq, n, phase0=0.0):
    """A band-limited sawtooth (PolyBLEP); freq in Hz, scalar or per sample."""
    if np.isscalar(freq):
        dt = np.full(n, freq / SR)
        ph = (phase0 + (freq / SR) * np.arange(n)) % 1.0
    else:
        dt = np.asarray(freq, np.float64) / SR
        ph = (phase0 + np.cumsum(dt) - dt[0]) % 1.0
    y = 2.0 * ph - 1.0
    m = ph < dt
    u = ph[m] / dt[m]
    y[m] -= 2 * u - u * u - 1.0
    m = ph > 1.0 - dt
    u = (ph[m] - 1.0) / dt[m]
    y[m] -= u * u + 2 * u + 1.0
    return y


def saw_stack(f, n, voices, cents, width, rng):
    """Detuned saws spread across the stereo field."""
    L = np.zeros(n)
    R = np.zeros(n)
    for i in range(voices):
        k = (i / (voices - 1)) * 2 - 1 if voices > 1 else 0.0
        v = saw(f * 2 ** (k * cents / 1200.0), n, rng.random())
        gl, gr = pan_lr(k * width)
        L += v * gl
        R += v * gr
    return np.vstack([L, R]) / math.sqrt(voices)


def pluck(f, dur, decay=6.0, tone=1.0, kmax=40, attack=0.0015, rng=None):
    """An additive pluck whose upper harmonics die first, like a closing filter."""
    n = S(dur)
    t = np.arange(n) / SR
    K = int(max(1, min(kmax, (SR * 0.45) // f)))
    y = np.zeros(n)
    for k in range(1, K + 1):
        dk = decay * (1.0 + (k - 1) * 0.5 / max(tone, 0.05))
        nk = min(n, S(9.2 / dk) + 1)
        ph = rng.random() * 6.2832 if rng is not None else 0.0
        y[:nk] += np.sin(2 * np.pi * k * f * t[:nk] + ph) * np.exp(-t[:nk] * dk) / k
    return y * ar(n, attack, min(0.03, dur * 0.25))


def fm_bell(f, dur, ratio=3.5, index=2.5, decay=2.2, idecay=7.0, attack=0.0015, octave=0.2):
    n = S(dur)
    t = np.arange(n) / SR
    mod = index * np.exp(-t * idecay) * np.sin(2 * np.pi * f * ratio * t)
    y = np.sin(2 * np.pi * f * t + mod) * np.exp(-t * decay)
    if octave:
        y += octave * np.sin(2 * np.pi * 2.0 * f * t + 0.5 * mod) * np.exp(-t * decay * 1.8)
    return y * ar(n, attack, min(0.08, dur * 0.2))


def glide_sine(f_of_t):
    return np.sin(2 * np.pi * np.cumsum(f_of_t) / SR)


# ---------------------------------------------------------------- filters
def sos(kind, f, order=2):
    btype = {'lp': 'lowpass', 'hp': 'highpass', 'bp': 'bandpass'}[kind]
    return signal.butter(order, f, btype, fs=SR, output='sos')


def filt(x, kind, f, order=2):
    return signal.sosfilt(sos(kind, f, order), x, axis=-1)


def biquad(kind, fc, q):
    fc = min(max(float(fc), 15.0), SR * 0.45)
    w = 2 * math.pi * fc / SR
    cw, sw = math.cos(w), math.sin(w)
    al = sw / (2 * q)
    if kind == 'lp':
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
    elif kind == 'hp':
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
    else:  # band-pass, 0 dB at the centre
        b = [al, 0.0, -al]
    a0 = 1 + al
    return np.array(b) / a0, np.array([1.0, -2 * cw / a0, (1 - al) / a0])


def tv_filter(x, fc, kind='lp', q=0.707, block=256, t0=0.0):
    """A biquad whose cutoff follows fc(t) (t in seconds from t0), per block."""
    x2 = np.atleast_2d(np.asarray(x, np.float64))
    n = x2.shape[1]
    nb = (n + block - 1) // block
    fcs = fc(t0 + (np.arange(nb) * block + block * 0.5) / SR)
    y = np.empty_like(x2)
    zi = np.zeros((x2.shape[0], 2))
    for i in range(nb):
        s, e = i * block, min(n, (i + 1) * block)
        b, a = biquad(kind, fcs[i], q)
        y[:, s:e], zi = signal.lfilter(b, a, x2[:, s:e], axis=-1, zi=zi)
    return y if np.ndim(x) == 2 else y[0]


# ---------------------------------------------------------------- harmony
PC = {'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 'E': 4, 'F': 5, 'F#': 6, 'Gb': 6, 'G': 7,
      'G#': 8, 'Ab': 8, 'A': 9, 'A#': 10, 'Bb': 10, 'B': 11}
CHORDS = {  # symbol: (bass, tones)
    'Dm9': ('D', ['D', 'F', 'A', 'E']), 'Dm': ('D', ['D', 'F', 'A']),
    'Bb': ('Bb', ['Bb', 'D', 'F']), 'Bb9': ('Bb', ['Bb', 'D', 'F', 'C']), 'Bb9/D': ('D', ['Bb', 'D', 'F', 'C']),
    'Bbmaj7': ('Bb', ['Bb', 'D', 'F', 'A']), 'C': ('C', ['C', 'E', 'G']), 'C/E': ('E', ['C', 'E', 'G']),
    'F': ('F', ['F', 'A', 'C']), 'F/A': ('A', ['F', 'A', 'C']), 'Gm': ('G', ['G', 'Bb', 'D']),
    'Gm7': ('G', ['G', 'Bb', 'D', 'F']), 'A': ('A', ['A', 'C#', 'E']), 'Asus4': ('A', ['A', 'D', 'E']),
    'A7sus4': ('A', ['A', 'D', 'E', 'G']), 'D9': ('D', ['D', 'F#', 'A', 'E']),
}
# The chart, per section: (chord, beats). The last chord of a section stretches
# (or is cut) to meet the next marker, so a re-timed film still lines up.
BLOCKS = [
    ('intro', [('Dm9', 8)]),
    ('question', [('Dm9', 4), ('Bb9/D', 4)]),
    ('wave', [('Bb9', 4), ('Asus4', 1), ('A', 1)]),
    ('reveal', [('Dm9', 4)]),
    ('build', [('Dm', 4), ('Bb', 4), ('C', 2)]),
    ('score', [('Dm', 4), ('Bb', 4), ('C', 2)]),
    ('stages', [('Dm', 4), ('Bb', 4), ('Gm', 2), ('A', 2)]),
    ('patterns', [('Dm', 4), ('Bb', 4), ('C', 2), ('F', 4), ('C', 4), ('A', 2)]),
    ('coach', [('Bbmaj7', 4), ('F/A', 4), ('Gm7', 2), ('A7sus4', 1), ('A', 1)]),
    ('tonight', [('Dm', 4), ('Bb', 4), ('C', 2)]),
    ('tools', [('F', 4), ('C', 4), ('Gm', 2), ('A', 2)]),
    ('drop', [('Dm', 4), ('Bb', 4), ('C', 2)]),
    ('snore', [('Dm', 4), ('Bb', 4), ('C', 2)]),
    ('watch', [('Bb', 4), ('F', 4), ('C', 2)]),
    ('dawn', [('Dm', 4), ('Bb', 4), ('A', 2)]),
    ('montage', [('Dm', 4), ('Bb', 4), ('C', 4)]),
    ('pullback', [('F', 4), ('C/E', 2)]),
    ('moon', [('Bb9', 3), ('Gm7', 1.5), ('A7sus4', 1.5)]),
    ('logo', [('D9', 4)]),
]


def chord_pcs(sym):
    return [PC[p] for p in CHORDS[sym][1]]


def chord_bass(sym):
    return PC[CHORDS[sym][0]]


def note_in(pc, lo):
    """The pitch class pc at or above MIDI note lo."""
    return lo + ((pc - lo) % 12)


def voice(sym, prev=None, lo=53, hi=79, center=65, count=4):
    """A close voicing near `center`, led smoothly from `prev`."""
    pcs = chord_pcs(sym)
    size = max(count, len(pcs))
    best, best_cost = None, 1e18
    for inv in range(len(pcs)):
        order = ((pcs[inv:] + pcs[:inv]) * 3)[:size]
        for base in range(lo, lo + 12):
            if base % 12 != order[0]:
                continue
            notes = [base]
            for pc in order[1:]:
                notes.append(notes[-1] + ((pc - notes[-1]) % 12 or 12))
            if notes[-1] > hi:
                continue
            cost = abs(sum(notes) / len(notes) - center) * 0.6
            if prev:
                cost += sum(min(abs(a - b) for b in prev) for a in notes) * 0.5
            if cost < best_cost:
                best, best_cost = notes, cost
    if best is None:
        best = sorted(note_in(pc, lo) for pc in pcs)
    return best


def arp_tones(sym, lo=62):
    """Four ascending chord tones from lo: the triad and its lowest note an octave up."""
    tri = chord_pcs(sym)[:3]
    notes = sorted(note_in(pc, lo) for pc in tri)
    return notes + [notes[0] + 12]


def build_chart(M):
    names = [b[0] for b in BLOCKS]
    edges = [M[n] for n in names] + [DUR]
    chart = []
    for i, (name, seq) in enumerate(BLOCKS):
        t0, t1 = edges[i], edges[i + 1]
        t = t0
        for j, (sym, beats) in enumerate(seq):
            if t >= t1 - 1e-6:
                break
            end = t1 if j == len(seq) - 1 else min(t1, t + beats * BEAT)
            chart.append((t, end, sym))
            t = end
    return chart


# ---------------------------------------------------------------- drums
def kick_sample(kind, rng):
    n = S(0.55)
    t = np.arange(n) / SR
    dec, drive, click, f0, fend = {'heart': (9.0, 1.6, 0.10, 88, 40), 'full': (7.2, 2.0, 0.40, 110, 44),
                                   'drop': (6.4, 2.5, 0.50, 120, 43), 'tight': (11.0, 2.0, 0.42, 110, 46)}[kind]
    f = fend + (f0 - fend) * np.exp(-t * 26) + 380 * np.exp(-t * 170)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * dec)
    body = np.tanh(body * drive) / math.tanh(drive)
    tick = filt(rng.standard_normal(n), 'bp', (1500, 6500)) * np.exp(-t * 420) * click
    tick += np.sin(2 * np.pi * 1850 * t) * np.exp(-t * 280) * click * 0.5
    return (body + tick) * ar(n, 0.0004, 0.04)


def clap_sample(rng):
    n = S(0.42)
    t = np.arange(n) / SR
    env = np.zeros(n)
    for k, d in enumerate((0.0, 0.0095, 0.0195, 0.031)):
        i = S(d)
        env[i:] += np.exp(-(t[i:] - d) * (240.0 if k < 3 else 19.0)) * (0.75 if k < 3 else 1.0)
    y = filt(rng.standard_normal(n), 'bp', (950, 5200)) * env
    return filt(y, 'hp', 650) * ar(n, 0.0004, 0.05)


def snare_sample(rng, dec=16.0):
    n = S(0.32)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * 188 * t) * np.exp(-t * 30) + 0.45 * np.sin(2 * np.pi * 332 * t) * np.exp(-t * 42)
    nz = filt(rng.standard_normal(n), 'hp', 1600) * np.exp(-t * dec)
    return (tone * 0.55 + nz * 0.85) * ar(n, 0.0004, 0.04)


def hat_sample(rng, open_=False):
    n = S(0.55 if open_ else 0.09)
    t = np.arange(n) / SR
    x = rng.standard_normal(n) * 0.7
    for f in (6120.0, 7430.0, 8210.0, 9570.0, 10950.0):
        x += 0.22 * np.sign(np.sin(2 * np.pi * f * t + rng.random() * 6.28))
    y = filt(x, 'hp', 7200, order=4) * np.exp(-t * (8.5 if open_ else 62.0))
    return y * ar(n, 0.0004, 0.01)


def crash_sample(rng, dur=2.8, dark=False):
    n = S(dur)
    t = np.arange(n) / SR
    x = rng.standard_normal((2, n))
    y = filt(x, 'hp', 2600 if dark else 3600) * np.exp(-t * 1.7)
    y += filt(x, 'bp', (5500, 12000)) * np.exp(-t * 2.6) * (0.25 if dark else 0.6)
    if dark:
        y = filt(y, 'lp', 7000)
    return y * ar(n, 0.001, 0.3)[None, :]


# ---------------------------------------------------------------- sound effects
def sfx_click(rng, **_):
    n = S(0.07)
    t = np.arange(n) / SR
    y = (np.sin(2 * np.pi * 1350 * t) * np.exp(-t * 170) * 0.7 + np.sin(2 * np.pi * 2450 * t) * np.exp(-t * 260) * 0.35
         + np.sin(2 * np.pi * 720 * t) * np.exp(-t * 110) * 0.35)
    y += filt(rng.standard_normal(n), 'bp', (900, 4000)) * np.exp(-t * 420) * 0.55
    return y * ar(n, 0.0004, 0.012)


def sfx_tick(rng, **_):
    n = S(0.035)
    t = np.arange(n) / SR
    y = np.sin(2 * np.pi * 4200 * t) * np.exp(-t * 420) + filt(rng.standard_normal(n), 'bp', (3000, 9500)) * np.exp(-t * 700) * 0.8
    return y * ar(n, 0.0003, 0.008)


def sfx_glint(rng, **_):
    n = S(0.55)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for f, a, d in ((3150, 1.0, 14), (4720, 0.7, 18), (6290, 0.45, 24), (2360, 0.4, 10)):
        y += a * np.sin(2 * np.pi * f * t + rng.random() * 6.28) * np.exp(-t * d)
    return y * ar(n, 0.001, 0.06)


def sfx_heartbeat(rng, **_):
    n = S(0.45)
    t = np.arange(n) / SR
    body = glide_sine(44 + 26 * np.exp(-t * 22)) * np.exp(-t * 11) * 0.62
    knock = np.sin(2 * np.pi * 180 * t) * np.exp(-t * 34) * 0.7 + np.sin(2 * np.pi * 360 * t) * np.exp(-t * 55) * 0.45
    thud = filt(rng.standard_normal(n), 'bp', (250, 1600)) * np.exp(-t * 40) * 0.9     # the chest-thump, on a phone
    return np.tanh((body + knock + thud) * 1.5) * ar(n, 0.004, 0.08)


def sfx_pulse(rng, **_):
    n = S(0.6)
    t = np.arange(n) / SR
    body = np.tanh((np.sin(2 * np.pi * 55 * t) * np.exp(-t * 6) * 0.6 + np.sin(2 * np.pi * 110 * t) * np.exp(-t * 9) * 0.5) * 1.5)
    click = filt(rng.standard_normal(n), 'bp', (700, 2500)) * np.exp(-t * 300) * 0.5
    knock = np.sin(2 * np.pi * 440 * t) * np.exp(-t * 50) * 0.55 + filt(rng.standard_normal(n), 'bp', (300, 1500)) * np.exp(-t * 55) * 0.6
    return (body + click + knock) * ar(n, 0.003, 0.1)


def sfx_draw(rng, dur=0.6, **_):
    dur = max(0.25, dur)
    n = S(dur + 0.08)
    t = np.arange(n) / SR
    x = rng.standard_normal(n)
    y = tv_filter(x, lambda tb: 2600 + 1700 * np.clip(tb / dur, 0, 1), 'bp', 2.4)
    grain = np.clip(1 + 3.0 * filt(rng.standard_normal(n), 'lp', 45), 0.2, 2.0)
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.4
    return y * grain * env * ar(n, 0.01, 0.04)


def sfx_rev(rng, dur=1.0, sym='Dm', ir=None, **_):
    """A chord through the room, backwards: it breathes in toward t + dur."""
    dur = max(0.2, dur)
    src_n = S(0.3)
    src = np.zeros(src_n)
    for m in voice(sym, None, lo=62, hi=86, center=72):
        src += pluck(hz(m), 0.3, decay=3.0, tone=2.0, rng=rng)
    tt = np.arange(src_n) / SR
    src += filt(rng.standard_normal(src_n), 'bp', (900, 7000)) * np.exp(-tt * 14) * 0.35
    out = []
    for ch in range(2):
        wet = signal.oaconvolve(src, ir[ch])
        out.append(wet[::-1])
    y = np.vstack(out)
    n = S(dur)
    y = y[:, -n:] if y.shape[1] >= n else np.pad(y, ((0, 0), (n - y.shape[1], 0)))
    ramp = (np.arange(n) / n) ** 1.5
    return y * ramp[None, :] * ar(n, 0.02, 0.004)[None, :]


def sfx_snap(rng, **_):
    n = S(0.25)
    t = np.arange(n) / SR
    tr = filt(rng.standard_normal(n), 'hp', 1500) * np.exp(-t * 500)
    blip = np.sin(2 * np.pi * 2100 * t) * np.exp(-t * 220) * 0.5
    sub = np.tanh((np.sin(2 * np.pi * 62 * t) * np.exp(-t * 22) + np.sin(2 * np.pi * 124 * t) * np.exp(-t * 30) * 0.35) * 1.4)
    return (tr + blip + sub) * ar(n, 0.0003, 0.05)


def sfx_tone(rng, sym='Dm', **_):
    m = note_in(chord_pcs(sym)[0], 74)          # the chord's root, around D5
    f = hz(m)
    n = S(1.7)
    t = np.arange(n) / SR
    mod = 0.9 * np.exp(-t * 5) * np.sin(2 * np.pi * f * 2 * t)
    y = (np.sin(2 * np.pi * f * t + mod) * np.exp(-t * 3.0) + 0.18 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 4.5)
         + 0.06 * np.sin(2 * np.pi * 3 * f * t) * np.exp(-t * 6))
    return y * ar(n, 0.006, 0.25)


def sfx_whoosh(rng, dur=0.8, **_):
    dur = max(0.3, dur)
    n = S(dur)
    t = np.arange(n) / SR
    u = t / dur
    x = rng.standard_normal((2, n))
    y = tv_filter(x, lambda tb: 350 * 10 ** (np.sin(np.pi * np.clip(tb / dur, 0, 1)) ** 1.2), 'bp', 1.1)
    env = np.where(u < 0.62, (u / 0.62) ** 2, np.cos(np.clip((u - 0.62) / 0.38, 0, 1) * np.pi / 2) ** 1.5)
    sweep = np.clip(u * 2 - 1, -1, 1) * 0.55           # travels left to right around the cue's pan
    gl = np.cos(np.maximum(0, sweep) * np.pi / 2)
    gr = np.cos(np.maximum(0, -sweep) * np.pi / 2)
    return np.vstack([y[0] * env * gl, y[1] * env * gr]) * ar(n, 0.01, 0.02)[None, :]


def sfx_swell(rng, dur=0.8, sym='Dm', **_):
    dur = max(0.2, dur)
    n = S(dur + 0.25)
    t = np.arange(n) / SR
    v = voice(sym, None, lo=57, hi=81, center=69)
    x = sum(saw_stack(hz(m), n, 5, 14, 0.9, rng) for m in v) / len(v)
    y = tv_filter(x, lambda tb: 300 * (4800 / 300) ** np.clip(tb / dur, 0, 1), 'lp', 1.2)
    env = np.where(t < dur, np.clip(t / dur, 0, 1) ** 2.2, np.exp(-(t - dur) * 14))
    return y * env[None, :] * ar(n, 0.01, 0.05)[None, :]


def sfx_impact(rng, **_):
    n = S(2.4)
    t = np.arange(n) / SR
    sub = glide_sine(30 + 70 * np.exp(-t * 3.5)) * np.exp(-t * 1.6)
    punch = np.sin(2 * np.pi * 95 * t) * np.exp(-t * 14)
    body = np.tanh((sub * 0.9 + punch * 0.8) * 2.2)
    nz = rng.standard_normal((2, n))
    y = body[None, :] + filt(nz, 'lp', 5200) * np.exp(-t * 9) * 0.55
    y += filt(nz, 'hp', 2500) * np.exp(-t * 40) * 0.35
    y += filt(nz, 'bp', (180, 900)) * np.exp(-t * 6) * 0.8       # the thump a phone speaker can play
    return y * ar(n, 0.0005, 0.4)[None, :]


def sfx_boom(rng, **_):
    n = S(1.4)
    t = np.arange(n) / SR
    sub = glide_sine(38 + 30 * np.exp(-t * 8)) * np.exp(-t * 3)
    body = np.sin(2 * np.pi * 118 * t) * np.exp(-t * 16) * 0.5
    thud = filt(rng.standard_normal(n), 'bp', (200, 1200)) * np.exp(-t * 16) * 0.55
    return (np.tanh((sub + body) * 1.8) + thud) * ar(n, 0.0008, 0.3)


def sfx_shimmer(rng, sym='Dm', **_):
    n = S(2.6)
    t = np.arange(n) / SR
    pcs = chord_pcs(sym)
    tones = [note_in(pc, 86) for pc in pcs] + [note_in(pcs[0], 98)]
    y = np.zeros((2, n))
    for m in tones:
        for c, p in ((-6, -0.5), (6, 0.5)):
            s = np.sin(2 * np.pi * hz(m) * 2 ** (c / 1200) * t + rng.random() * 6.28)
            y += stereo(s, p) / len(tones)
    env = ar(n, 0.08, 0.4) * np.exp(-t * 1.4)
    y *= env[None, :]
    for _i in range(26):
        s0 = rng.uniform(0, 1.5)
        bn = S(0.03)
        bt = np.arange(bn) / SR
        b = np.sin(2 * np.pi * rng.uniform(5000, 9000) * bt) * np.exp(-bt * 140) * 0.35 * np.exp(-s0 * 1.2)
        i0 = S(s0)
        gl, gr = pan_lr(rng.uniform(-0.8, 0.8))
        y[0, i0:i0 + bn] += b * gl
        y[1, i0:i0 + bn] += b * gr
    return y


def sfx_riser(rng, dur=2.0, sym='Dm', noise_amt=0.8, **_):
    dur = max(0.3, dur)
    n = S(dur)
    t = np.arange(n) / SR
    u = t / dur
    root = note_in(chord_bass(sym), 45)
    glide = 2 ** (u ** 1.6)                                 # an octave, accelerating
    tone = (saw(hz(root) * glide, n, 0.0) + saw(hz(root + 7) * glide, n, 0.3) * 0.7
            + saw(hz(root + 12) * glide * 1.003, n, 0.6) * 0.5)
    tone = tv_filter(tone, lambda tb: 400 * (6000 / 400) ** np.clip(tb / dur, 0, 1), 'lp', 1.4)
    noise = tv_filter(rng.standard_normal((2, n)), lambda tb: 500 * (9000 / 500) ** np.clip(tb / dur, 0, 1), 'bp', 1.3)
    y = tone[None, :] * 0.5 + noise * noise_amt
    return y * (u ** 2.4)[None, :] * ar(n, 0.01, 0.006)[None, :]


DATA_SCALE = [2, 5, 7, 9, 0]     # D minor pentatonic


def sfx_data(rng, dur=0.8, **_):
    dur = max(0.15, dur)
    n = S(dur + 0.1)
    y = np.zeros((2, n))
    t = 0.0
    while t < dur:
        m = note_in(DATA_SCALE[rng.integers(0, 5)], 86 + 12 * int(rng.random() < 0.3))
        bn = S(rng.uniform(0.025, 0.045))
        bt = np.arange(bn) / SR
        b = (np.sin(2 * np.pi * hz(m) * bt) + 0.3 * np.sin(4 * np.pi * hz(m) * bt)) * np.exp(-bt * 60) * rng.uniform(0.5, 1.0)
        b *= ar(bn, 0.001, 0.006) * math.sin(math.pi * min(1.0, t / dur)) ** 0.5
        i0 = S(t)
        gl, gr = pan_lr(rng.uniform(-0.6, 0.6))
        y[0, i0:i0 + bn] += b[:max(0, min(bn, n - i0))] * gl
        y[1, i0:i0 + bn] += b[:max(0, min(bn, n - i0))] * gr
        t += rng.uniform(0.035, 0.08)
    return y


def sfx_glass(rng, sym='Dm', **_):
    m = note_in(chord_pcs(sym)[2 % len(chord_pcs(sym))], 81)   # the chord's fifth, around A5
    return fm_bell(hz(m), 1.9, ratio=2.76, index=2.2, decay=2.6, idecay=11, octave=0.25)


def sfx_bass(rng, sym='Dm', **_):
    m = note_in(chord_bass(sym), 26)
    n = S(0.9)
    t = np.arange(n) / SR
    ph = 2 * np.pi * np.cumsum(hz(m) * (1 + 0.5 * np.exp(-t * 40))) / SR
    y = np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph)
    y = np.tanh(y * 1.8) * np.exp(-t * 3.2)
    y += filt(rng.standard_normal(n), 'bp', (800, 3000)) * np.exp(-t * 300) * 0.3
    return y * ar(n, 0.001, 0.1)


def sfx_pop(rng, **_):
    n = S(0.12)
    t = np.arange(n) / SR
    y = glide_sine(380 + 540 * (1 - np.exp(-t * 90))) * np.exp(-t * 45)
    y += filt(rng.standard_normal(n), 'hp', 3000) * np.exp(-t * 600) * 0.3
    return y * ar(n, 0.001, 0.02)


def sfx_sweep(rng, dur=1.0, sym='Dm', **_):
    dur = max(0.2, dur)
    n = S(dur)
    t = np.arange(n) / SR
    v = voice(sym, None, lo=57, hi=81, center=69)
    x = rng.standard_normal((2, n)) * 0.6 + sum(saw_stack(hz(m), n, 3, 12, 0.8, rng) for m in v) / len(v) * 0.5
    y = tv_filter(x, lambda tb: 300 * (6500 / 300) ** np.clip(tb / dur, 0, 1), 'bp', 1.6)
    return y * (np.sin(np.pi * t / dur) ** 1.2)[None, :]


# kind: (synth, peak level dBFS before mastering, reverb send)
SFX = {
    'impact': (sfx_impact, -3, 0.45), 'boom': (sfx_boom, -6, 0.3), 'snap': (sfx_snap, -7, 0.2),
    'heartbeat': (sfx_heartbeat, -5, 0.15), 'pulse': (sfx_pulse, -5, 0.2), 'bass': (sfx_bass, -6, 0.15),
    'riser': (sfx_riser, -4, 0.25), 'whoosh': (sfx_whoosh, -3, 0.2), 'swell': (sfx_swell, -6, 0.3),
    'rev': (sfx_rev, -5, 0.1), 'shimmer': (sfx_shimmer, -8, 0.6), 'glint': (sfx_glint, -9, 0.5),
    'tone': (sfx_tone, -6, 0.45), 'glass': (sfx_glass, -4, 0.5), 'tick': (sfx_tick, -1, 0.12),
    'click': (sfx_click, -2, 0.12), 'pop': (sfx_pop, -3, 0.15), 'data': (sfx_data, -4, 0.35),
    'draw': (sfx_draw, -6, 0.2), 'sweep': (sfx_sweep, -6, 0.3),
}


# ---------------------------------------------------------------- the room and the echoes
def room_ir(rt60=2.5, length=3.2, predelay=0.014, seed=7):
    """A stereo room: two-band decaying noise (the highs die first) and a few early reflections."""
    rng = np.random.default_rng(seed)
    n = S(length)
    t = np.arange(n) / SR
    out = []
    for _ch in range(2):
        noise = rng.standard_normal(n)
        lo = filt(noise, 'lp', 3200)
        hi = noise - lo
        ir = lo * 10 ** (-3 * t / rt60) + hi * 10 ** (-3 * t / (rt60 * 0.42)) * 0.6
        ir[:S(predelay)] = 0.0
        ir[S(predelay):S(predelay) + S(0.006)] *= rcos(S(0.006))
        for k in range(10):
            ir[S(predelay + rng.uniform(0.003, 0.075))] += rng.uniform(0.4, 1.0) * (-1) ** k * 3.0
        ir = filt(ir, 'hp', 160)
        out.append(ir)
    ir = np.vstack(out)
    return ir / math.sqrt(np.sum(ir ** 2) / 2)


def convolve(x, ir):
    y = np.zeros((2, x.shape[1]))
    for ch in range(2):
        other = x[1 - ch].astype(np.float64)
        y[ch] = signal.oaconvolve(x[ch].astype(np.float64) + 0.25 * other, ir[ch])[:x.shape[1]]
    return y


def pingpong(x, delay, fb=0.42, repeats=6, lp=4200):
    """Echoes that alternate sides and darken as they fade."""
    mono = (x[0].astype(np.float64) + x[1]) * 0.5
    d = S(delay)
    y = np.zeros((2, x.shape[1]))
    tap = mono
    s = sos('lp', lp, 1)
    for r in range(1, repeats + 1):
        tap = signal.sosfilt(s, tap)
        k = r * d
        if k >= x.shape[1]:
            break
        y[r % 2, k:] += fb ** r * tap[:x.shape[1] - k]
    return y


# ---------------------------------------------------------------- dynamics and loudness
def k_weight(x):
    b1 = [1.53512485958697, -2.69169618940638, 1.19839281085285]
    a1 = [1.0, -1.69065929318241, 0.73248077421585]
    b2 = [1.0, -2.0, 1.0]
    a2 = [1.0, -1.99004745483398, 0.99007225036621]
    return signal.lfilter(b2, a2, signal.lfilter(b1, a1, np.asarray(x, np.float64), axis=-1), axis=-1)


def lufs(x):
    """Integrated loudness, ITU-R BS.1770-4 (400 ms blocks, 75% overlap, both gates)."""
    y = k_weight(x)
    n = y.shape[1]
    blk, hop = S(0.4), S(0.1)
    if n < blk:
        return -np.inf
    c = np.concatenate([np.zeros((2, 1)), np.cumsum(y * y, axis=1)], axis=1)
    st = np.arange(0, n - blk + 1, hop)
    z = (c[:, st + blk] - c[:, st]) / blk
    lk = -0.691 + 10 * np.log10(z.sum(axis=0) + 1e-30)
    g1 = lk > -70
    if not g1.any():
        return -np.inf
    la = -0.691 + 10 * np.log10(z[:, g1].mean(axis=1).sum() + 1e-30)
    g2 = g1 & (lk > la - 10)
    return -0.691 + 10 * np.log10(z[:, g2].mean(axis=1).sum() + 1e-30)


def loudness_of(y_kw, t0, t1):
    """Ungated K-weighted loudness of a stretch (y_kw already K-weighted)."""
    a, b = S(t0), S(t1)
    ms = np.mean(y_kw[:, a:b] ** 2, axis=1).sum()
    return -0.691 + 10 * np.log10(ms + 1e-30)


def true_peak_db(x):
    peak, n, chunk, pad = 0.0, x.shape[1], S(5.0), 256
    for s in range(0, n, chunk):
        a, e = max(0, s - pad), min(n, s + chunk)
        b = min(n, e + pad)
        up = signal.resample_poly(np.asarray(x[:, a:b], np.float64), 4, 1, axis=1)
        peak = max(peak, float(np.max(np.abs(up[:, (s - a) * 4:(e - a) * 4]))))
    return 20 * math.log10(peak + 1e-12)


def glue(x, thresh=-20.0, ratio=2.0, knee=6.0, attack=0.012, release=0.2):
    """A gentle RMS bus compressor with a soft knee, on a 1 ms grid."""
    B = 48
    n = x.shape[1]
    nb = (n + B - 1) // B
    p = np.zeros(nb * B)
    p[:n] = (x[0].astype(np.float64) ** 2 + x[1].astype(np.float64) ** 2) * 0.5
    ldb = 10 * np.log10(p.reshape(nb, B).mean(axis=1) + 1e-12)
    over = ldb - thresh
    gr = np.where(over <= -knee / 2, 0.0, np.where(over >= knee / 2, over * (1 - 1 / ratio),
                                                   (1 - 1 / ratio) * (over + knee / 2) ** 2 / (2 * knee)))
    aa, rr = math.exp(-1 / (attack * 1000)), math.exp(-1 / (release * 1000))
    out = np.empty(nb)
    cur = 0.0
    for i, v in enumerate(gr.tolist()):
        cur = aa * cur + (1 - aa) * v if v > cur else rr * cur + (1 - rr) * v
        out[i] = cur
    g = uniform_filter1d(10 ** (-np.repeat(out, B)[:n] / 20), size=B)
    return x * g[None, :], out


def tp_envelope(x):
    """Per sample, the largest |x| among 4x-interpolated points, both channels: true peaks."""
    n = x.shape[1]
    out = np.empty(n)
    chunk, pad = S(5.0), 256
    for s in range(0, n, chunk):
        a, e = max(0, s - pad), min(n, s + chunk)
        b = min(n, e + pad)
        up = signal.resample_poly(np.asarray(x[:, a:b], np.float64), 4, 1, axis=1)
        out[s:e] = np.abs(up[:, (s - a) * 4:(e - a) * 4]).max(axis=0).reshape(-1, 4).max(axis=1)
    return np.maximum(out, np.max(np.abs(x), axis=0))


def limiter(x, ceiling_db, lookahead=0.005, release=0.09):
    """Lookahead true-peak limiter: nothing, between samples or on them, passes the ceiling."""
    c = 10 ** (ceiling_db / 20)
    n = x.shape[1]
    need = np.minimum(1.0, c / np.maximum(tp_envelope(x), 1e-12))
    A = S(lookahead)
    g = minimum_filter1d(need, size=2 * A + 1)
    B = 48
    nb = (n + B - 1) // B
    gp = np.ones(nb * B)
    gp[:n] = g
    gb = gp.reshape(nb, B).min(axis=1)
    rr = math.exp(-1 / (release * 1000))
    out = np.empty(nb)
    cur = 1.0
    for i, v in enumerate(gb.tolist()):
        cur = v if v < cur else v + (cur - v) * rr
        out[i] = cur
    gs = np.minimum(np.repeat(out, B)[:n], g)
    gs = uniform_filter1d(gs, size=2 * A + 1)
    return x * gs[None, :], gs


def write_wav24(path, x):
    rng = np.random.default_rng(1)
    full = 2 ** 23 - 1
    tpdf = (rng.random(x.shape) - rng.random(x.shape)) / full
    q = np.clip(np.round((np.clip(x, -1.0, 1.0) + tpdf) * full), -full - 1, full).astype('<i4')
    raw = q.T.reshape(-1).view(np.uint8).reshape(-1, 4)[:, :3].tobytes()
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(3)
        w.setframerate(SR)
        w.writeframes(raw)


# ---------------------------------------------------------------- the arrangement
def render(M, chart, cues):
    chord_at_ts = np.array([c[0] for c in chart])

    def chord_at(t):
        i = int(np.searchsorted(chord_at_ts, t + 1e-6, side='right')) - 1
        return chart[max(0, min(i, len(chart) - 1))][2]

    def beats(t0, t1, step=None, offset=0.0):
        """Grid times from t0 (inclusive) to t1 (exclusive)."""
        step = BEAT if step is None else step
        k0 = math.ceil((t0 - offset) / step - 1e-6)
        out = []
        t = offset + k0 * step
        while t < t1 - 1e-6:
            out.append(round(t, 6))
            t += step
        return out

    B = {k: Bus(k) for k in ('drone', 'pad', 'air', 'bells', 'pulse', 'arp', 'lead', 'saws', 'stabs', 'bass',
                             'kick', 'clap', 'snare', 'hats', 'crash', 'rise', 'sfx', 'send', 'echo')}
    ir = room_ir()

    # --- the kick first: everything else breathes around it
    rng = np.random.default_rng(3)
    kicks = []                                              # (t, velocity, kind, lowpass Hz or None)
    for t in beats(M['build'], M['score'], 2 * BEAT):       # a heartbeat: lub on the beat, dub a 16th later
        lp = float(np.exp(np.interp(t, [M['build'], M['score']], np.log([220, 1100]))))
        kicks += [(t, 0.95, 'heart', lp), (t + BEAT / 2, 0.5, 'heart', lp)]
    for t in beats(M['score'], M['stages']):
        kicks.append((t, 0.92, 'full', float(np.exp(np.interp(t, [M['score'], M['stages']], np.log([1100, 9000]))))))
    for t in beats(M['stages'], M['coach'] - BEAT):
        kicks.append((t, 1.0, 'full', None))
    for t in beats(M['tonight'], M['drop'] - BEAT):
        kicks.append((t, 1.0, 'full', None))
    for t in beats(M['drop'], M['montage']):
        kicks.append((t, 1.0, 'drop', None))
    for t in beats(M['montage'], M['pullback']):
        kicks.append((t, 0.9, 'tight', None))
    for t in beats(M['moon'], M['logo'], 2 * BEAT):         # the heartbeat comes back under the last line
        kicks += [(t, 0.55, 'heart', 320.0), (t + BEAT / 2, 0.3, 'heart', 320.0)]
    kick_cache = {k: kick_sample(k, np.random.default_rng(40 + i)) for i, k in enumerate(('heart', 'full', 'drop', 'tight'))}
    for t, v, kind, lp in kicks:
        s = kick_cache[kind]
        if lp:
            s = filt(s, 'lp', lp)
        B['kick'].put(t, s, gain=v)

    def pump(depth, release=0.34):
        g = np.ones(N, np.float32)
        L = S(release + 0.005)
        tt = np.arange(L) / SR
        shape = np.where(tt < 0.004, tt / 0.004, 0.5 + 0.5 * np.cos(np.pi * np.clip((tt - 0.004) / release, 0, 1)))
        for t, v, kind, lp in kicks:
            i0 = S(t)
            b = min(N, i0 + L)
            d = depth * min(1.0, v) * (0.45 if kind == 'heart' else 1.0)
            g[i0:b] = np.minimum(g[i0:b], 1 - d * shape[:b - i0])
        return g

    # --- drone: the night's floor, under the opening and the last lines
    rng = np.random.default_rng(5)
    for t0, t1, lvl, fi, fo in ((0.0, M['build'] + 1.5, 1.0, 3.0, 2.5), (M['coach'], M['tonight'], 0.55, 1.0, 1.0),
                                (M['pullback'], DUR, 0.8, 1.5, 0.9)):
        n = S(t1 - t0)
        t = np.arange(n) / SR
        root = 26 if t0 < M['pullback'] else 26
        y = 0.35 * np.sin(2 * np.pi * hz(root) * t + rng.random() * 6.28) + 0.6 * np.sin(2 * np.pi * hz(root + 12) * t)
        y = np.tanh(y * 1.7) / 1.2 * (1 + 0.1 * np.sin(2 * np.pi * 0.25 * t))
        B['drone'].put(t0, y * ar(n, fi, fo) * lvl)

    # --- pads: warm detuned saws through a filter that opens with the film
    rng = np.random.default_rng(11)
    raw = np.zeros((2, N))
    prev = None
    for i, (t0, t1, sym) in enumerate(chart):
        v = voice(sym, prev)
        prev = v
        a0 = max(0.0, t0 - 0.03)
        n = S(t1 - a0 + 1.2)
        env = gate(n, t1 - a0, 3.0 if t0 < 0.01 else 0.2, 1.1)
        sig = sum(saw_stack(hz(m), n, 5, 11.0, 0.85, rng) for m in v) / len(v)
        i0 = S(a0)
        b = min(N, i0 + n)
        raw[:, i0:b] += (sig * env[None, :])[:, :b - i0]
    pad_fc = keyfn([(0, 520), (M['question'], 700), (M['wave'], 950), (M['reveal'] - 0.1, 3200), (M['reveal'] + 0.8, 3600),
                    (M['build'], 1500), (M['score'], 1900), (M['stages'], 2400), (M['patterns'], 3000), (M['coach'], 2600),
                    (M['tonight'] - 0.5, 3400), (M['tonight'], 3000), (M['drop'], 3600), (M['montage'], 2300),
                    (M['pullback'], 3200), (M['moon'], 2400), (M['logo'] - 0.1, 4200), (M['logo'], 5200), (DUR, 4000)], log=True)
    pad = filt(tv_filter(raw, pad_fc, 'lp', 0.8, block=512), 'hp', 140)
    pad *= curve([(0, 0.0), (0.4, 0.3), (M['question'], 0.38), (M['wave'], 0.5), (M['reveal'] - 0.3, 0.95), (M['reveal'], 1.0),
                  (M['build'], 0.55), (M['score'], 0.55), (M['stages'], 0.5), (M['patterns'], 0.5), (M['coach'] - 0.25, 0.5),
                  (M['coach'] + 0.4, 0.42), (M['tonight'] - 0.3, 0.5), (M['tonight'], 0.48), (M['drop'], 0.36),
                  (M['montage'], 0.58), (M['pullback'], 0.8), (M['moon'], 0.55), (M['logo'] - 0.05, 1.05), (M['logo'], 1.0),
                  (DUR - 0.9, 0.9), (DUR - 0.05, 0.0), (DUR, 0.0)])[None, :]
    B['pad'].x += pad.astype(np.float32)

    # --- supersaw chords: the drop's wall, and a lighter one before it
    rng = np.random.default_rng(13)
    raw = np.zeros((2, N))
    prev = None
    for t0, t1, sym in chart:
        if t1 <= M['tonight'] or t0 >= M['montage']:
            continue
        v = voice(sym, prev, lo=57, hi=86, center=70, count=5)
        prev = v
        n = S(t1 - t0 + 0.6)
        env = gate(n, t1 - t0, 0.012, 0.35)
        sig = sum(saw_stack(hz(m), n, 7, 19.0, 1.0, rng) for m in v) / len(v)
        i0 = S(t0)
        b = min(N, i0 + n)
        raw[:, i0:b] += (sig * env[None, :])[:, :b - i0]
    saw_fc = keyfn([(M['tonight'], 1700), (M['tools'], 2100), (M['drop'] - 2.5, 2100), (M['drop'] - 0.1, 7000),
                    (M['drop'], 6500), (M['montage'], 5200)], log=True)
    saws = filt(tv_filter(raw, saw_fc, 'lp', 1.1, block=512), 'hp', 180)
    saws *= curve([(M['tonight'], 0.0), (M['tonight'] + 0.05, 0.28), (M['tools'], 0.34), (M['drop'] - 2.0, 0.5),
                   (M['drop'] - 0.01, 0.75), (M['drop'], 1.0), (M['montage'] - 0.4, 0.95), (M['montage'], 0.0), (DUR, 0.0)])[None, :]
    B['saws'].x += saws.astype(np.float32)

    # --- chord stabs on the big arrivals
    rng = np.random.default_rng(17)
    for t, sym, lvl in ((M['reveal'], 'Dm9', 1.0), (M['patterns'], chord_at(M['patterns']), 0.7),
                        (M['tonight'], chord_at(M['tonight']), 0.75), (M['drop'], chord_at(M['drop']), 0.9), (M['logo'], 'D9', 0.8)):
        v = voice(sym, None, lo=50, hi=86, center=66, count=6)
        n = S(2.8)
        tt = np.arange(n) / SR
        sig = sum(saw_stack(hz(m), n, 7, 22.0, 1.0, rng) for m in v) / len(v)
        sig = tv_filter(sig, lambda tb: 900 + 5200 * np.exp(-tb * 2.5), 'lp', 0.9)
        B['saws'].put(t, sig * (np.exp(-tt * 1.3) * ar(n, 0.004, 0.3))[None, :], gain=lvl * 0.9)

    # --- offbeat chord stabs in the full sections
    rng = np.random.default_rng(18)
    for a, b in ((M['stages'] + 2 * BEAT * 4, M['coach'] - BEAT), (M['tonight'], M['drop'] - BEAT)):
        for t in beats(a, b, BEAT, offset=BEAT / 2):
            v = voice(chord_at(t), None, lo=60, hi=84, center=70)
            y = sum(pluck(hz(m), 0.26, decay=11.0, tone=1.3, kmax=20, rng=rng) for m in v) / len(v)
            k = int(round((t - BEAT / 2) / BEAT)) % 2
            B['stabs'].put(t, y, pan=0.22 if k else -0.22, gain=1.0 if k else 0.7)

    # --- bass
    rng = np.random.default_rng(19)
    bass_notes = []                                         # (t, midi, dur, bright, drive, gain)
    for t0, t1, sym in chart:
        root = note_in(chord_bass(sym), 34)
        for sec_a, sec_b, mode, gain in ((M['score'], M['coach'] - BEAT, 'off8', 1.0), (M['tonight'], M['drop'] - BEAT, 'off8', 1.0),
                                         (M['drop'], M['montage'], 'roll', 1.05), (M['montage'], M['pullback'], 'off8', 0.8)):
            a, b = max(t0, sec_a), min(t1, sec_b)
            if b <= a:
                continue
            if mode == 'off8':
                for bt in beats(a, b, BEAT, offset=BEAT / 2):
                    g = gain * float(np.interp(bt, [M['score'], M['stages'], M['patterns']], [0.7, 0.85, 1.0]))
                    bass_notes.append((bt, root, 0.2, 0.9 + 0.3 * (bt >= M['patterns']), 1.6, g))
            else:
                for bt in beats(a, b, BEAT / 4):
                    pos = int(round((bt - M['drop']) / (BEAT / 4))) % 4
                    if pos == 0:
                        continue
                    m = root + (12 if pos == 2 else 0)
                    bass_notes.append((bt, m, 0.11, 1.25, 2.1, gain * (1.0 if pos != 2 else 0.8)))
    for t, m, dur, bright, drive, g in bass_notes:
        f = hz(m)
        n = S(dur + 0.03)
        tt = np.arange(n) / SR
        x = saw(f, n, rng.random()) * 0.8 + np.sin(2 * np.pi * f / 2 * tt) * 0.55
        y = tv_filter(x, lambda tb, br=bright: 170 + 2300 * br * np.exp(-tb * 17), 'lp', 3.0, block=64)
        y = np.tanh(y * drive) * gate(n, dur, 0.002, 0.025)
        B['bass'].put(t, y, gain=g)
    # sustained sub under the quieter stretches
    for t0, t1, sym in chart:
        for sec_a, sec_b, gain in ((M['build'], M['score'], 0.6), (M['coach'], M['tonight'], 0.18), (M['pullback'], M['logo'], 0.5),
                                   (M['logo'], DUR, 0.7)):
            a, b = max(t0, sec_a), min(t1, sec_b)
            if b <= a:
                continue
            m = note_in(chord_bass(sym), 34)
            n = S(b - a + 0.3)
            tt = np.arange(n) / SR
            x = np.sin(2 * np.pi * hz(m) * tt) + 0.25 * filt(saw(hz(m), n, 0.0), 'lp', 300)
            x = np.tanh(x * 1.3) * gate(n, b - a, 0.06, 0.3)
            if sec_b == DUR:
                x *= np.clip((DUR - 0.05 - (a + tt)) / 0.8, 0, 1)
            B['bass'].put(a, x, gain=gain)

    # --- the pulse: a soft muted 8th-note heartbeat of the harmony
    rng = np.random.default_rng(23)
    pulse_lvl = keyfn([(M['question'], 0.0), (M['question'] + 1.5, 0.55), (M['wave'], 0.7), (M['reveal'], 1.0), (M['build'], 0.75),
                       (M['score'], 0.55), (M['score'] + 3.0, 0.0), (M['coach'], 0.0), (M['coach'] + 1.0, 0.6), (M['tonight'] - 0.01, 0.8),
                       (M['tonight'], 0.0), (M['montage'], 0.0), (M['montage'] + 0.01, 0.85), (M['pullback'] - 0.01, 0.95),
                       (M['pullback'], 0.0)])
    pulse_times = beats(M['question'], M['wave'] + 2 * BEAT * 2, BEAT / 2) + beats(M['wave'] + 4 * BEAT, M['reveal'], BEAT / 4) \
        + beats(M['reveal'], M['score'] + 3.0, BEAT / 2) + beats(M['coach'], M['tonight'], BEAT / 2) + beats(M['montage'], M['pullback'], BEAT / 2)
    for i, t in enumerate(sorted(set(pulse_times))):
        lvl = float(pulse_lvl(t))
        if lvl <= 0.001:
            continue
        sym = chord_at(t)
        root = note_in(chord_bass(sym), 50)
        m = root + (12 if (int(round(t / (BEAT / 2))) % 2) else 0)
        tone = float(np.interp(t, [M['question'], M['reveal'], M['coach'], M['montage']], [0.35, 0.9, 0.6, 0.8]))
        y = pluck(hz(m), 0.24, decay=14.0, tone=tone, kmax=18, rng=rng)
        B['pulse'].put(t, y, pan=(-0.18 if i % 2 else 0.18), gain=lvl)

    # --- the arp: 16ths from the score onward, sparse and high in the Coach break
    rng = np.random.default_rng(29)
    pattern = [0, 1, 2, 3, 2, 1, 3, 2]
    arp_bright = keyfn([(M['score'], 0.6), (M['stages'], 0.9), (M['patterns'], 1.4), (M['coach'], 1.2), (M['tonight'], 1.5),
                        (M['drop'], 2.1), (M['montage'], 1.6)])
    arp_lvl = keyfn([(M['score'], 0.8), (M['stages'], 0.85), (M['patterns'], 1.0), (M['coach'] - 0.01, 1.0), (M['coach'], 0.36),
                     (M['tonight'] - 0.01, 0.4), (M['tonight'], 0.8), (M['drop'], 1.0), (M['montage'] - 0.01, 1.0), (M['montage'], 0.0)])
    arp_times = [(t, 16) for t in beats(M['score'], M['coach'] - BEAT, BEAT / 4)] + [(t, 8) for t in beats(M['coach'], M['tonight'], BEAT / 2)] \
        + [(t, 16) for t in beats(M['tonight'], M['montage'], BEAT / 4)]
    for t, div in arp_times:
        step = int(round((t - M['score']) / (BEAT / 4)))
        sym = chord_at(t)
        tones = arp_tones(sym, 74 if div == 8 else 62)
        m = tones[pattern[(step // (1 if div == 16 else 2)) % 8]]
        acc = 1.0 if step % 4 == 0 else 0.72
        y = pluck(hz(m), 0.34, decay=9.0 if div == 16 else 5.0, tone=float(arp_bright(t)), kmax=24, rng=rng)
        B['arp'].put(t, y, pan=0.28 if step % 2 else -0.28, gain=float(arp_lvl(t)) * acc * rng.uniform(0.92, 1.05))

    # --- the lead: the Zoon motif (A - D - F - E), sung out over the drop
    rng = np.random.default_rng(31)
    MELODY = {
        'drop': [(0, 69, .5), (.5, 74, .5), (1, 77, 1), (2, 76, .5), (2.5, 74, 1.5), (4, 74, .5), (4.5, 77, .5), (5, 81, 1),
                 (6, 79, .5), (6.5, 77, 1.5), (8, 76, 1), (9, 79, 1)],
        'snore': [(0, 69, .5), (.5, 74, .5), (1, 77, 1), (2, 76, .5), (2.5, 81, 1.5), (4, 82, 1), (5, 81, .5), (5.5, 77, .5),
                  (6, 74, 1), (7, 77, 1), (8, 79, 1), (9, 76, 1)],
        'watch': [(0, 77, .5), (.5, 82, .5), (1, 86, 1.5), (2.5, 84, .5), (3, 82, 1), (4, 81, .5), (4.5, 84, .5), (5, 81, 1),
                  (6, 79, .5), (6.5, 77, 1.5), (8, 76, .5), (8.5, 79, .5), (9, 84, 1)],
        'dawn': [(0, 86, 1), (1, 81, .5), (1.5, 77, .5), (2, 76, .5), (2.5, 74, 1.5), (4, 77, 1), (5, 74, .5), (5.5, 77, .5),
                 (6, 79, 1), (7, 81, 1), (8, 85, 1), (9, 81, 1)],
    }
    s3k = sos('lp', 3400)
    for name, mel in MELODY.items():
        for b, m, d in mel:
            t = M[name] + b * BEAT
            if t >= M['montage'] - 0.01:
                continue
            dur = d * BEAT
            f = hz(m)
            n = S(dur + 0.5)
            p = pluck(f, dur + 0.5, decay=3.2, tone=2.2, kmax=24, rng=rng) * 0.8
            p += pluck(f / 2, dur + 0.5, decay=4.0, tone=1.2, kmax=16, rng=rng) * 0.35
            s = signal.sosfilt(s3k, saw_stack(f, n, 3, 9.0, 0.6, rng), axis=-1) * gate(n, dur, 0.008, 0.25)[None, :]
            B['lead'].put(t, stereo(p) + s * 0.55)
    # the same motif, in glass, as the name appears
    for k, (dt, m) in enumerate(((0.5, 69), (0.75, 74), (1.0, 77), (1.5, 76))):
        B['bells'].put(M['reveal'] + dt, fm_bell(hz(m), 2.4, ratio=2.0, index=1.2, decay=1.6, idecay=5, octave=0.3),
                       pan=-0.3 + 0.2 * k, gain=0.55)

    # --- air and glass: the texture of the quiet parts
    rng = np.random.default_rng(37)
    for t0, t1, sym in chart:
        for sec_a, sec_b, lvl in ((0.0, M['build'], 1.0), (M['coach'], M['tonight'], 0.6), (M['pullback'], DUR, 1.0)):
            a, b = max(t0, sec_a), min(t1, sec_b)
            if b <= a:
                continue
            n = S(b - a + 1.5)
            tt = np.arange(n) / SR
            y = np.zeros((2, n))
            for m in [note_in(pc, 86) for pc in chord_pcs(sym)]:
                for c, p in ((-5, -0.6), (5, 0.6)):
                    y += stereo(np.sin(2 * np.pi * hz(m) * 2 ** (c / 1200) * tt + rng.random() * 6.28), p)
            trem = 1 + 0.25 * np.sin(2 * np.pi * 0.3 * tt + rng.random() * 6.28)
            env = gate(n, b - a, 0.9 if a > 0 else 3.0, 1.4) * trem
            if sec_b == DUR:
                env *= np.clip((DUR - 0.05 - (a + tt)) / 0.8, 0, 1)
            B['air'].put(a, y * env[None, :] / 6, gain=lvl)
    bell_times = [(t, 0.7) for t in beats(0.75, M['reveal'] - 0.5, 1.25 * BEAT * 2)] \
        + [(t, 0.5) for t in beats(M['coach'] + 0.25, M['tonight'] - 0.5, 1.5 * BEAT)] \
        + [(t, 0.6) for t in beats(M['moon'] + 0.25, M['logo'] - 0.2, 1.5 * BEAT)]
    for t, lvl in bell_times:
        pcs = chord_pcs(chord_at(t))
        m = note_in(pcs[rng.integers(0, len(pcs))], 74 + 12 * int(rng.random() < 0.4))
        B['bells'].put(t, fm_bell(hz(m), 2.2, ratio=3.5, index=1.1, decay=1.8, idecay=6), pan=rng.uniform(-0.7, 0.7),
                       gain=lvl * rng.uniform(0.6, 1.0))

    # --- the sonic logo: A, D, F#, E -- the motif, in major -- over D major
    for dt, m, g, p in ((0.0, 69, 1.0, -0.35), (BEAT / 4, 74, 0.95, -0.1), (BEAT / 2, 78, 0.95, 0.12), (BEAT, 88, 0.85, 0.3)):
        y = fm_bell(hz(m), max(0.4, DUR - M['logo'] - dt), ratio=2.0, index=1.6, decay=1.1, idecay=4.0, octave=0.35)
        y += 0.5 * fm_bell(hz(m) * 2, max(0.4, DUR - M['logo'] - dt), ratio=3.5, index=0.8, decay=2.0, idecay=8.0, octave=0)
        B['bells'].put(M['logo'] + dt, y, pan=p, gain=g * 1.25)

    # --- snare, clap, hats
    rng = np.random.default_rng(41)
    clap = clap_sample(rng)
    snr = snare_sample(rng)
    roll_snr = snare_sample(rng, dec=24.0)
    for t in beats(M['stages'], M['coach'] - BEAT, 2 * BEAT, offset=BEAT):
        B['clap'].put(t, clap, gain=0.7 if t < M['patterns'] else 1.0)
    for t in beats(M['tonight'], M['drop'] - BEAT, 2 * BEAT, offset=BEAT):
        B['clap'].put(t, clap, gain=1.0)
    for t in beats(M['drop'], M['montage'], 2 * BEAT, offset=BEAT):
        B['clap'].put(t, clap, gain=1.05)
        B['snare'].put(t, snr, gain=0.8)

    def roll(t0, t1, v0, v1):
        mid = t0 + (t1 - t0) * 0.5
        for t in beats(t0, mid, BEAT / 4) + beats(mid, t1, BEAT / 8):
            k = (t - t0) / max(1e-6, t1 - t0)
            B['snare'].put(t, roll_snr, gain=v0 + (v1 - v0) * k ** 1.5)
    roll(M['patterns'] - 2 * BEAT, M['patterns'], 0.25, 0.9)
    roll(M['tonight'] - 4 * BEAT, M['tonight'], 0.15, 0.85)
    roll(M['drop'] - 4 * BEAT, M['drop'] - BEAT / 4, 0.25, 1.1)

    hat_c = hat_sample(rng)
    hat_o = hat_sample(rng, open_=True)
    for t in beats(M['score'], M['stages'], BEAT, offset=BEAT / 2):
        B['hats'].put(t, hat_c, pan=0.15, gain=1.0)
    for t in beats(M['stages'], M['patterns'], BEAT / 4):
        pos = int(round((t - M['stages']) / (BEAT / 4))) % 4
        B['hats'].put(t, hat_c, pan=0.15, gain=0.8 if pos == 2 else 0.28)
    for a, b in ((M['patterns'], M['coach'] - BEAT), (M['tonight'], M['drop'] - BEAT), (M['drop'], M['montage'])):
        for t in beats(a, b, BEAT / 4):
            pos = int(round((t - a) / (BEAT / 4))) % 4
            if pos == 2:
                B['hats'].put(t, hat_o, pan=-0.1, gain=0.55 if a < M['drop'] else 0.65)
            else:
                B['hats'].put(t, hat_c, pan=0.15, gain=(0.45 if pos == 0 else 0.32) * rng.uniform(0.9, 1.08))
    for t in beats(M['montage'], M['pullback'], BEAT / 4):   # the montage rides on tight ticks
        pos = int(round((t - M['montage']) / (BEAT / 4))) % 4
        B['hats'].put(t, hat_c, pan=0.2 if pos % 2 else -0.2, gain=0.75 if pos == 2 else 0.4)

    # --- crashes, booms and risers on the arrivals
    rng = np.random.default_rng(43)
    crash = crash_sample(rng)
    crash_dark = crash_sample(rng, 3.2, dark=True)
    boom = sfx_boom(rng)
    for name, lvl in (('reveal', 0.85), ('score', 0.6), ('stages', 0.65), ('patterns', 1.0), ('tonight', 0.9), ('tools', 0.75),
                      ('drop', 1.0), ('snore', 0.75), ('watch', 0.8), ('dawn', 0.8), ('montage', 0.55)):
        B['crash'].put(M[name], crash, gain=lvl)
        B['crash'].put(M[name], stereo(boom), gain=lvl * 0.55)
    B['crash'].put(M['logo'], crash_dark, gain=0.55)
    B['crash'].put(M['logo'], stereo(boom), gain=0.6)
    for a, b, lvl, nz in ((M['wave'] + 1.0, M['reveal'], 0.55, 0.8), (M['patterns'] - 2.0, M['patterns'], 0.7, 0.8),
                          (M['tonight'] - 2.0, M['tonight'], 0.62, 0.8), (M['drop'] - 3.0, M['drop'], 1.0, 0.8),
                          (M['moon'] - 0.5, M['logo'] - BEAT / 4, 0.4, 0.35)):
        B['rise'].put(a, sfx_riser(rng, dur=b - a, sym=chord_at(a), noise_amt=nz), gain=lvl)
    for a, b, lvl in ((M['coach'] - 1.0, M['coach'], 0.5), (M['pullback'] - 1.0, M['pullback'], 0.7),
                      (M['logo'] - 1.5, M['logo'] - BEAT / 4, 0.8)):
        B['rise'].put(a, sfx_rev(rng, dur=b - a, sym=chord_at(b), ir=ir), gain=lvl)

    # --- the film's own cues
    rng = np.random.default_rng(47)
    sfx_log = []
    for c in cues:
        kind = c.get('kind', 'click')
        if kind not in SFX:
            print(f'  warning: unknown cue kind {kind!r} at {c.get("t")} s; using click', file=sys.stderr)
            kind = 'click'
        fn, level_db, send = SFX[kind]
        t = float(c.get('t', 0.0))
        if t < 0 or t >= DUR:
            continue
        dur = float(c.get('dur', 0.0) or {'riser': 2.0, 'rev': 1.0, 'swell': 0.8, 'whoosh': 0.8, 'data': 0.8,
                                           'draw': 0.6, 'sweep': 1.0}.get(kind, 0.0))
        y = fn(rng, dur=dur, sym=chord_at(t + (dur if kind in ('rev', 'riser', 'swell') else 0.0)), ir=ir)
        y = stereo(y)
        pk = float(np.max(np.abs(y))) or 1.0
        y = y / pk * 10 ** (level_db / 20)
        start = t        # every effect starts on its cue; risers and swells end at t + dur
        gain = float(c.get('gain', 1.0))
        pan = float(c.get('pan', 0.0))
        B['sfx'].put(start, y, pan=pan, gain=gain)
        B['send'].put(start, y, pan=pan, gain=gain * send)
        sfx_log.append((t, kind, start, y.shape[1] / SR))

    return B, kicks, pump, ir, sfx_log


# ---------------------------------------------------------------- mix and master
def rms_db(x, t0, t1):
    a, b = S(t0), S(t1)
    seg = np.asarray(x[:, a:b], np.float64)
    return 10 * math.log10(np.mean(seg ** 2) + 1e-20)


def main():
    t_start = time.time()
    M = dict(DEFAULT_MARKS)
    film_marks = {m['name']: float(m['t']) for m in FILM.get('music', [])}
    unknown = [k for k in film_marks if k not in M]
    M.update({k: v for k, v in film_marks.items() if k in M})
    if unknown:
        print('  (markers not used by the score:', ', '.join(unknown) + ')')
    order = [b[0] for b in BLOCKS]
    for a, b in zip(order, order[1:]):
        if M[b] <= M[a]:
            sys.exit(f'markers out of order: {a} {M[a]} >= {b} {M[b]}')
    chart = build_chart(M)
    cues = sorted(FILM.get('cues', []), key=lambda c: c.get('t', 0))
    print(f'score: {DUR:.0f} s at {BPM:.0f} BPM, {len(chart)} chords, {len(cues)} cues, markers from the film: {len(film_marks)}')

    B, kicks, pump, ir, sfx_log = render(M, chart, cues)
    t_synth = time.time()

    # staging: each stem to its level where it matters most
    stage = {  # stem: (from, to, RMS dBFS)
        'kick': (M['patterns'], M['coach'] - 1, -16.0), 'bass': (M['patterns'], M['coach'] - 1, -18.5),
        'pad': (M['patterns'], M['coach'] - 1, -26.0), 'saws': (M['drop'], M['montage'], -19.0),
        'clap': (M['patterns'], M['coach'] - 1, -24.0), 'snare': (M['drop'], M['montage'], -29.0),
        'hats': (M['patterns'], M['coach'] - 1, -28.5), 'arp': (M['patterns'], M['coach'] - 1, -24.5),
        'lead': (M['drop'], M['montage'], -20.5), 'pulse': (M['question'], M['reveal'], -29.0),
        'drone': (0.5, M['wave'], -32.0), 'air': (M['coach'], M['tonight'], -37.0), 'bells': (M['coach'], M['tonight'], -33.0),
        'crash': (M['patterns'], M['patterns'] + 1.5, -21.0), 'rise': (M['drop'] - 1.0, M['drop'], -19.0),
        'stabs': (M['patterns'], M['coach'] - 1, -25.0),
    }
    for k, (a, b, target) in stage.items():
        cur = rms_db(B[k].x, a, b)
        if cur > -120:
            B[k].x *= np.float32(10 ** ((target - cur) / 20))

    # a short breath of silence right before the drop
    gap = np.ones(N, np.float32)
    g0, g1 = S(M['drop'] - BEAT / 4), S(M['drop'])
    gap[g0:g1] = 0.0
    gap[g0 - S(0.004):g0] = rcos(S(0.004))[::-1]
    gap[g1:g1 + S(0.003)] = rcos(S(0.003))
    for k in ('pad', 'saws', 'bass', 'arp', 'hats', 'pulse', 'stabs'):
        B[k].x *= gap[None, :]
    lgap = np.ones(N, np.float32)
    g0, g1 = S(M['logo'] - BEAT / 4), S(M['logo'])
    lgap[g0:g1] = 0.12
    lgap[g0 - S(0.01):g0] = 0.12 + 0.88 * rcos(S(0.01))[::-1]
    lgap[g1:g1 + S(0.004)] = 0.12 + 0.88 * rcos(S(0.004))
    for k in ('pad', 'air', 'drone', 'bass'):
        B[k].x *= lgap[None, :]

    # sidechain: the harmony ducks under the kick
    for k, depth in (('pad', 0.45), ('saws', 0.7), ('bass', 0.85), ('arp', 0.28), ('pulse', 0.3), ('lead', 0.15), ('air', 0.2),
                     ('stabs', 0.3)):
        B[k].x *= pump(depth)[None, :]

    # sends: the room, and echoes on the melodic parts
    for k, s in (('pad', 0.22), ('arp', 0.3), ('lead', 0.28), ('stabs', 0.25), ('bells', 0.6), ('air', 0.5), ('clap', 0.22), ('snare', 0.2),
                 ('crash', 0.25), ('pulse', 0.2), ('rise', 0.25), ('saws', 0.12)):
        B['send'].x += B[k].x * np.float32(s)
    for k, s in (('arp', 0.35), ('lead', 0.32), ('pulse', 0.3), ('bells', 0.3)):
        B['echo'].x += B[k].x * np.float32(s)
    echoes = pingpong(B['echo'].x, 3 * BEAT / 4, fb=0.42)
    B['send'].x += (echoes * 0.3).astype(np.float32)
    wet = convolve(B['send'].x, ir) * 0.32

    music = np.zeros((2, N))
    for k in ('drone', 'pad', 'air', 'bells', 'pulse', 'arp', 'lead', 'saws', 'stabs', 'bass', 'kick', 'clap', 'snare', 'hats',
              'crash', 'rise'):
        music += B[k].x
    music += echoes * 0.55 + wet
    music = filt(music, 'hp', 24)
    fx = filt(np.asarray(B['sfx'].x, np.float64), 'hp', 30)

    # master: glue the music, lay the effects on top, then limit to loudness
    pre = 10 ** ((-20.0 - lufs(music)) / 20)
    music *= pre
    fx *= pre
    music, gr = glue(music, thresh=-21.0, ratio=2.0)
    mix = filt(music + fx, 'hp', 12)
    fade = np.ones(N)
    fade[:S(0.005)] = rcos(S(0.005))
    tail0 = S(DUR - 0.7)
    fade[tail0:] = rcos(N - tail0)[::-1] ** 0.8
    mix *= fade[None, :]

    ceiling = -1.15
    gain = 10 ** ((TARGET_LUFS - lufs(mix)) / 20)
    for _it in range(6):
        out, lim_g = limiter(mix * gain, ceiling)
        L = lufs(out)
        tp = true_peak_db(out)
        if tp > TP_LIMIT - 0.05:
            ceiling -= (tp - TP_LIMIT) + 0.1
        if abs(L - TARGET_LUFS) < 0.05 and tp <= TP_LIMIT:
            break
        gain *= 10 ** ((TARGET_LUFS - L) / 20)
    write_wav24(OUT_PATH, out)
    t_done = time.time()

    # ---------------------------------------------------------------- review
    print(f'wrote {OUT_PATH}  ({out.shape[1] / SR:.3f} s, 48 kHz, 24-bit)')
    print(f'render {t_done - t_start:.1f} s  (synthesis {t_synth - t_start:.1f} s)')
    print(f'integrated loudness {lufs(out):.2f} LUFS   true peak {true_peak_db(out):.2f} dBTP   '
          f'sample peak {20 * math.log10(np.max(np.abs(out))):.2f} dBFS   ceiling {ceiling:.2f}')
    print(f'glue: up to {np.max(gr):.1f} dB of gain reduction   limiter: up to {-20 * math.log10(np.min(lim_g)):.1f} dB '
          f'(at {np.argmin(lim_g) / SR:.2f} s), {np.mean(lim_g < 0.891) * 100:.1f}% of samples beyond 1 dB')
    if os.environ.get('SCORE_DEBUG'):
        print('chart: ' + '  '.join(f'{a:.2f} {sym}' for a, b, sym in chart))
    dc = np.mean(out, axis=1)
    print(f'DC offset L {dc[0]:+.2e}  R {dc[1]:+.2e}')
    if os.environ.get('SCORE_DEBUG'):
        print('\nstem RMS dBFS by section (pre-master)')
        secs = sorted(M.items(), key=lambda kv: kv[1])
        print('stem    ' + ' '.join(f'{n[:6]:>6s}' for n, _ in secs))
        for k in ('drone', 'pad', 'air', 'bells', 'pulse', 'arp', 'lead', 'saws', 'stabs', 'bass', 'kick', 'clap', 'snare', 'hats',
                  'crash', 'rise', 'sfx'):
            row = []
            for i, (n, t0) in enumerate(secs):
                t1 = secs[i + 1][1] if i + 1 < len(secs) else DUR
                v = rms_db(B[k].x, t0, t1) if t1 - t0 > 0.3 else -99
                row.append(f'{v:6.0f}' if v > -90 else '     .')
            print(f'{k:7s} ' + ' '.join(row))
    ykw = k_weight(out)
    phone = k_weight(filt(filt(out, 'hp', 280, order=4), 'lp', 11000))
    names = sorted(M.items(), key=lambda kv: kv[1])
    print('\nsection        from    to   RMS dBFS   loudness LUFS   music-only LUFS   on a phone')
    mkw = k_weight(np.clip(music * gain, -4, 4))
    for i, (name, t0) in enumerate(names):
        t1 = names[i + 1][1] if i + 1 < len(names) else DUR
        if t1 - t0 < 0.3:
            continue
        print(f'{name:12s} {t0:6.2f} {t1:6.2f}   {rms_db(out, t0, t1):7.1f}   {loudness_of(ykw, t0, t1):12.1f}   '
              f'{loudness_of(mkw, t0, t1):12.1f}   {loudness_of(phone, t0, t1):12.1f}')
    mono = k_weight(np.repeat(((out[0] + out[1]) * 0.5)[None, :], 2, axis=0))
    worst = min(((loudness_of(mono, t0, (names[i + 1][1] if i + 1 < len(names) else DUR)) - loudness_of(ykw, t0, (names[i + 1][1] if i + 1 < len(names) else DUR)), n)
                 for i, (n, t0) in enumerate(names)))
    print(f'mono fold-down: at worst {worst[0]:+.1f} LU against stereo ({worst[1]})')
    # clicks: sample-to-sample jumps far beyond the local high-frequency level
    d = np.abs(np.diff(out, axis=1)).max(axis=0)
    local = np.sqrt(uniform_filter1d(d ** 2, size=S(0.01))) + 1e-4
    flags = np.where((d > 10 * local) & (d > 0.02))[0]
    print(f'\nclick check: {len(flags)} suspicious jumps' + (': ' + ', '.join(f'{f / SR:.3f}' for f in flags[:12]) if len(flags) else ''))
    env = np.sqrt(uniform_filter1d(np.mean(out.astype(np.float64) ** 2, axis=0), size=S(0.01)))
    breath = float(np.median(env[S(M['logo'] - BEAT / 4) + S(0.02):S(M['logo'])]))
    a = S(M['logo'] - BEAT / 4) + S(0.02)
    onset = a + int(np.argmax(env[a:S(M['logo'] + 0.3)] > breath * 4))
    lvl = lambda t: 20 * math.log10(env[S(t)] + 1e-9)
    print(f'logo: breath {20 * math.log10(breath + 1e-9):.1f} dBFS, the hit crosses 4x at {onset / SR:.3f} s (marker {M["logo"]:.2f}); '
          f'{lvl(M["logo"] + 0.05):.1f} dBFS at +50 ms, {lvl(M["logo"] + 1.0):.1f} at +1 s, {lvl(DUR - 0.05):.1f} at {DUR - 0.05:.2f} s')
    # effects against the music under them
    print('\ncue            t      effect vs music (dB, 300 Hz - 8 kHz, over the cue)')
    fxo = filt(fx * gain, 'bp', (300, 8000))
    mus_b = filt(music * gain, 'bp', (300, 8000))
    for t, kind, start, length in sfx_log:
        if kind in ('riser', 'rev', 'swell'):           # these arrive at their end
            a0, b0 = start + length * 0.6, min(DUR, start + length)
        else:
            a0, b0 = start, min(DUR, start + max(0.03, min(length, 0.4)))
        e = rms_db(fxo, a0, b0)
        m = rms_db(mus_b, a0, b0)
        print(f'{kind:10s} {t:7.2f}   {e - m:+6.1f}')
    ff = shutil.which('ffmpeg') or os.path.expanduser('~/scoop/shims/ffmpeg')
    png = os.path.join(tempfile.gettempdir(), 'zoon-film', 'score-spectrum.png')
    os.makedirs(os.path.dirname(png), exist_ok=True)
    try:
        subprocess.run([ff, '-v', 'error', '-y', '-i', OUT_PATH, '-lavfi',
                        'showspectrumpic=s=1600x600:legend=1:scale=log:fscale=log:color=intensity', png], check=True)
        print(f'spectrogram {png}')
    except (OSError, subprocess.CalledProcessError) as err:
        print(f'(no spectrogram: {err})')


if __name__ == '__main__':
    main()
