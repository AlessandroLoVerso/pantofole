#!/usr/bin/env python3
"""Genera le suonerie originali di Pantofole.

Ogni suono è sintetizzato da zero (sintesi additiva, modi smorzati, FM, rumore filtrato):
nessun campione, nessun audio di terzi. Solo libreria standard di Python 3.

Uscite:
  SvegliaNFC/Resources/Sounds/suoneria-<id>.caf   (mono, 22.05 kHz, IMA4, < 30 s)
  SvegliaNFC/Sounds/BuiltInRingtones.swift        (catalogo Swift generato)

Uso:  python3 tools/genera_suonerie.py [--solo id1,id2]
Richiede `afconvert` (macOS) per la conversione in CAF.
"""

import math
import os
import random
import struct
import subprocess
import sys
import tempfile
import wave
from operator import add

SR = 22050
TAU = 2.0 * math.pi
NYQ = SR * 0.45
CEILING_DB = -1.5          # picco massimo dopo il limitatore (margine per IMA4: resta < -1 dBFS)
TARGET_RMS_DB = -14.0      # loudness: RMS della finestra di 3 s più forte
GENTLE_TARGET_RMS_DB = -15.5

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "SvegliaNFC", "Resources", "Sounds")
SWIFT_OUT = os.path.join(ROOT, "SvegliaNFC", "Sounds", "BuiltInRingtones.swift")


# --------------------------------------------------------------------------- note e utilità

_NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    """"C#4" -> 61."""
    base = _NOTE[name[0]]
    rest = name[1:]
    while rest and rest[0] in "#b":
        base += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + base


def mtof(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def hz(name):
    return mtof(midi(name)) if isinstance(name, str) else mtof(name)


def db(x):
    return 20.0 * math.log10(max(x, 1e-12))


class Mix:
    def __init__(self, seconds):
        self.seconds = seconds
        self.n = int(seconds * SR)
        self.buf = [0.0] * self.n

    def put(self, t, samples, gain=1.0):
        i0 = int(round(t * SR))
        if i0 >= self.n or i0 < 0:
            return
        m = min(len(samples), self.n - i0)
        src = samples[:m] if gain == 1.0 else [s * gain for s in samples[:m]]
        self.buf[i0:i0 + m] = map(add, self.buf[i0:i0 + m], src)


# --------------------------------------------------------------------------- generatori di base

def add_partial(out, freq, amp, tau=None, phase=0.0):
    """Somma a `out` una sinusoide (eventualmente smorzata, costante di tempo `tau` in s)."""
    if freq <= 0 or freq >= NYQ or amp == 0:
        return
    n = len(out)
    w = TAU * freq / SR
    r = 1.0 if tau is None else math.exp(-1.0 / (tau * SR))
    if r < 1.0:
        n = min(n, int(math.log(1e-5 / amp) / math.log(r)) + 2)
    c = 2.0 * r * math.cos(w)
    r2 = r * r
    y2 = amp / r * math.sin(phase - w)
    y1 = amp * math.sin(phase)
    for i in range(n):
        out[i] += y1
        y = c * y1 - r2 * y2
        y2 = y1
        y1 = y


def fade(out, attack=0.003, release=0.01):
    n = len(out)
    a = min(n, max(1, int(attack * SR)))
    for i in range(a):
        x = i / a
        out[i] *= x * x * (3 - 2 * x)
    r = min(n, max(1, int(release * SR)))
    for i in range(r):
        x = i / r
        out[n - 1 - i] *= x * x * (3 - 2 * x)
    return out


def lowpass(out, cutoff):
    a = 1.0 - math.exp(-TAU * cutoff / SR)
    y = 0.0
    for i in range(len(out)):
        y += a * (out[i] - y)
        out[i] = y
    return out


def highpass(out, cutoff):
    a = math.exp(-TAU * cutoff / SR)
    y = 0.0
    xp = 0.0
    for i in range(len(out)):
        x = out[i]
        y = a * (y + x - xp)
        xp = x
        out[i] = y
    return out


_cache = {}


def cached(key, make):
    if key not in _cache:
        _cache[key] = make()
    return _cache[key]


_tables = {}


def table(kind, harmonics):
    """Tabella d'onda a banda limitata: 'saw', 'square', 'soft' (saw smorzata), 'organ'."""
    key = (kind, harmonics)
    if key in _tables:
        return _tables[key]
    size = 4096
    t = [0.0] * size
    for h in range(1, harmonics + 1):
        if kind == "saw":
            a = 1.0 / h
        elif kind == "square":
            a = 1.0 / h if h % 2 else 0.0
        elif kind == "soft":
            a = 1.0 / (h ** 1.6)
        elif kind == "organ":
            a = {1: 1.0, 2: 0.6, 3: 0.45, 4: 0.3, 6: 0.18, 8: 0.12}.get(h, 0.0)
        else:
            raise ValueError(kind)
        if a:
            for i in range(size):
                t[i] += a * math.sin(TAU * h * i / size)
    peak = max(abs(v) for v in t)
    t = [v / peak for v in t]
    _tables[key] = t
    return t


def tab_osc(kind, freq, n, max_h=24, phase=0.0):
    nh = max(1, min(max_h, int(NYQ / freq)))
    tbl = table(kind, nh)
    size = len(tbl)
    inc = freq * size / SR
    p = phase * size
    out = [0.0] * n
    for i in range(n):
        out[i] = tbl[int(p) % size]
        p += inc
    return out


# --------------------------------------------------------------------------- strumenti

# (rapporto, ampiezza, decadimento in s)
GLASS = [(1, 1.0, 2.4), (2.756, 0.38, 0.9), (5.404, 0.18, 0.4), (8.933, 0.07, 0.18)]
MARIMBA = [(1, 1.0, 0.5), (3.93, 0.32, 0.11), (9.24, 0.07, 0.035)]
KALIMBA = [(1, 1.0, 0.95), (2.0, 0.08, 0.35), (5.92, 0.22, 0.07), (8.4, 0.05, 0.03)]
MUSICBOX = [(1, 1.0, 1.1), (2.0, 0.28, 0.5), (3.0, 0.1, 0.28), (5.1, 0.07, 0.12)]
XYLO = [(1, 1.0, 0.32), (3.0, 0.42, 0.11), (6.1, 0.12, 0.045)]
CHURCH = [(0.5, 0.35, 3.6), (1, 1.0, 2.4), (1.19, 0.42, 1.8), (1.5, 0.28, 1.3), (2.0, 0.5, 1.1),
          (2.51, 0.22, 0.7), (3.0, 0.16, 0.5), (4.07, 0.1, 0.32)]
HANDBELL = [(1, 1.0, 1.6), (2.0, 0.2, 0.9), (2.98, 0.35, 0.6), (4.16, 0.12, 0.3), (5.43, 0.08, 0.2)]
CLOCKBELL = [(1, 1.0, 0.5), (2.32, 0.45, 0.28), (4.25, 0.25, 0.14), (6.63, 0.1, 0.07)]


def struck(name, partials, freq, dur=None, attack=0.002, gain=1.0):
    if dur is None:
        dur = min(6.0, max(tau for _, _, tau in partials) * 4.5)

    def make():
        out = [0.0] * int(dur * SR)
        for ratio, amp, tau in partials:
            add_partial(out, freq * ratio, amp * gain, tau)
        return fade(out, attack, 0.02)

    return cached(("struck", name, round(freq, 3), dur, attack, gain), make)


def glass(f, dur=None):
    return struck("glass", GLASS, f, dur)


def marimba(f):
    return struck("marimba", MARIMBA, f, 2.0, 0.002)


def kalimba(f):
    return struck("kalimba", KALIMBA, f, 3.5, 0.002)


def musicbox(f):
    return struck("musicbox", MUSICBOX, f, 4.0, 0.001)


def xylo(f):
    return struck("xylo", XYLO, f, 1.4, 0.001)


def church(f):
    return struck("church", CHURCH, f, 7.0, 0.004)


def handbell(f):
    return struck("handbell", HANDBELL, f, 5.0, 0.002)


def fm(f, dur, ratio=1.0, index=1.6, idecay=0.35, adecay=1.4, attack=0.003):
    def make():
        n = int(dur * SR)
        out = [0.0] * n
        wc = TAU * f / SR
        wm = wc * ratio
        ka = math.exp(-1.0 / (adecay * SR))
        ki = math.exp(-1.0 / (idecay * SR))
        a = 1.0
        idx = index
        sin = math.sin
        for i in range(n):
            out[i] = a * sin(wc * i + idx * sin(wm * i))
            a *= ka
            idx *= ki
        return fade(out, attack, 0.02)

    return cached(("fm", round(f, 3), dur, ratio, index, idecay, adecay, attack), make)


def epiano(f, dur=2.5):
    a = fm(f, dur, 1.0, 1.3, 0.5, 1.6)
    b = fm(f * 2, dur, 7.0, 0.6, 0.06, 0.4)
    return [x + 0.12 * y for x, y in zip(a, b)]


def pad(f, dur, attack=2.0, release=2.0, kind="soft", cutoff=2200.0, detune=0.004):
    def make():
        n = int(dur * SR)
        a = tab_osc(kind, f * (1 + detune), n, 12, 0.13)
        b = tab_osc(kind, f * (1 - detune), n, 12, 0.61)
        out = [(x + y) * 0.5 for x, y in zip(a, b)]
        lowpass(out, cutoff)
        lowpass(out, cutoff * 1.5)
        return fade(out, attack, release)

    return cached(("pad", round(f, 3), dur, attack, release, kind, cutoff, detune), make)


def pluck(f, dur=0.35, kind="saw", cutoff=2500.0, decay=0.18, max_h=24):
    def make():
        n = int(dur * SR)
        out = tab_osc(kind, f, n, max_h)
        k = math.exp(-1.0 / (decay * SR))
        a = 1.0
        for i in range(n):
            out[i] *= a
            a *= k
        lowpass(out, cutoff)
        return fade(out, 0.003, 0.02)

    return cached(("pluck", round(f, 3), dur, kind, cutoff, decay, max_h), make)


def tone(f, dur, kind="soft", max_h=6, attack=0.006, release=0.02, cutoff=None):
    def make():
        out = tab_osc(kind, f, int(dur * SR), max_h)
        if cutoff:
            lowpass(out, cutoff)
        return fade(out, attack, release)

    return cached(("tone", round(f, 3), dur, kind, max_h, attack, release, cutoff), make)


def beep(f, dur=0.1):
    def make():
        out = [0.0] * int(dur * SR)
        add_partial(out, f, 1.0)
        add_partial(out, f * 2, 0.12)
        add_partial(out, f * 3, 0.06)
        return fade(out, 0.006, 0.015)

    return cached(("beep", round(f, 3), dur), make)


_noise_rng = random.Random(1234)
_NOISE = [_noise_rng.uniform(-1, 1) for _ in range(SR)]


def kick(gain=1.0):
    def make():
        n = int(0.4 * SR)
        out = [0.0] * n
        ph = 0.0
        for i in range(n):
            t = i / SR
            f = 46 + 120 * math.exp(-t / 0.035)
            ph += TAU * f / SR
            out[i] = math.sin(ph) * math.exp(-t / 0.2)
        return fade(out, 0.001, 0.03)

    return [x * gain for x in cached(("kick",), make)]


def snare():
    def make():
        n = int(0.3 * SR)
        noise = highpass(_NOISE[:n], 900.0)
        out = [0.0] * n
        add_partial(out, 185.0, 0.6, 0.05)
        for i in range(n):
            out[i] += 0.7 * noise[i] * math.exp(-i / SR / 0.07)
        lowpass(out, 7000.0)
        return fade(out, 0.001, 0.03)

    return cached(("snare",), make)


def hihat(length=0.06):
    def make():
        n = int(length * 2 * SR)
        out = highpass(highpass(_NOISE[3000:3000 + n], 5000.0), 5000.0)
        for i in range(n):
            out[i] *= 2.2 * math.exp(-i / SR / (length / 2.5))
        return fade(out, 0.001, 0.01)

    return cached(("hihat", length), make)


def clap():
    def make():
        n = int(0.35 * SR)
        src = highpass(_NOISE[7000:7000 + n], 1200.0)
        out = [0.0] * n
        for burst in (0.0, 0.011, 0.022):
            b0 = int(burst * SR)
            for i in range(b0, n):
                out[i] += src[i] * math.exp(-(i - b0) / SR / (0.012 if burst < 0.02 else 0.09))
        lowpass(out, 6000.0)
        return fade([x * 0.6 for x in out], 0.001, 0.03)

    return cached(("clap",), make)


def tom(f):
    def make():
        n = int(0.5 * SR)
        out = [0.0] * n
        ph = 0.0
        for i in range(n):
            t = i / SR
            ph += TAU * f * (1 + 0.5 * math.exp(-t / 0.03)) / SR
            out[i] = math.sin(ph) * math.exp(-t / 0.16)
        return fade(out, 0.001, 0.03)

    return cached(("tom", round(f, 2)), make)


def sweep(f0, f1, dur, harmonics=((1, 1.0), (2, 0.25), (3, 0.12)), curve="exp", attack=0.02, release=0.04, vibrato=0.0):
    n = int(dur * SR)
    out = [0.0] * n
    ph = 0.0
    sin = math.sin
    for i in range(n):
        x = i / n
        f = f0 * (f1 / f0) ** x if curve == "exp" else f0 + (f1 - f0) * (0.5 - 0.5 * math.cos(math.pi * x))
        if vibrato:
            f *= 1 + 0.01 * sin(TAU * vibrato * i / SR)
        ph += TAU * f / SR
        s = 0.0
        for h, a in harmonics:
            if f * h < NYQ:
                s += a * sin(h * ph)
        out[i] = s
    return fade(out, attack, release)


def reverb(buf, wet=0.25, size=1.0, damp=0.35):
    """Riverbero di Schroeder (4 comb + 2 all-pass), mono."""
    n = len(buf)
    combs = [int(d * size) for d in (1557 // 2, 1617 // 2, 1491 // 2, 1422 // 2)]
    acc = [0.0] * n
    for d in combs:
        line = [0.0] * d
        idx = 0
        fb = 0.8
        lp = 0.0
        for i in range(n):
            y = line[idx]
            lp = y * (1 - damp) + lp * damp
            line[idx] = buf[i] + lp * fb
            acc[i] += y
            idx += 1
            if idx == d:
                idx = 0
    for d in (556 // 2, 441 // 2):
        line = [0.0] * d
        idx = 0
        for i in range(n):
            b = line[idx]
            x = acc[i]
            y = -x + b
            line[idx] = x + b * 0.5
            acc[i] = y
            idx += 1
            if idx == d:
                idx = 0
    g = wet * 0.25
    return [x * (1 - wet * 0.4) + y * g for x, y in zip(buf, acc)]


# --------------------------------------------------------------------------- suonerie: Dolci

def s_alba(rng):
    m = Mix(26)
    prog = [["D3", "A3", "C#4", "F#4"], ["B2", "F#3", "A3", "D4"], ["G2", "D3", "B3", "F#4"], ["A2", "E3", "G3", "C#4"]]
    for i, chord in enumerate(prog):
        for note in chord:
            m.put(i * 6.4, pad(hz(note), 8.6, 2.6, 2.8), 0.16)
    scale = ["D5", "E5", "F#5", "A5", "B5", "D6", "E6", "F#6"]
    t = 4.0
    while t < 25.0:
        m.put(t, musicbox(hz(rng.choice(scale))), rng.uniform(0.12, 0.2) * min(1.0, t / 12))
        t += rng.uniform(0.3, 0.75) * (1.3 - t / 40)
    m.buf = reverb(m.buf, 0.4, 1.2)
    return m


def s_rugiada(rng):
    m = Mix(24)
    pent = ["C5", "D5", "E5", "G5", "A5", "C6", "D6", "E6"]
    pattern = [0, 2, 4, 6, 5, 3, 1, 4]
    t = 0.2
    k = 0
    while t < 23:
        base = [0, 1, -1, 0][(k // 8) % 4]
        note = pent[max(0, min(len(pent) - 1, pattern[k % 8] + base))]
        m.put(t, glass(hz(note)), 0.32 if k % 8 == 0 else 0.22)
        if k % 16 == 0:
            m.put(t, glass(hz(note) / 2), 0.15)
        t += 0.42
        k += 1
    m.buf = reverb(m.buf, 0.4, 1.1)
    return m


def s_kalimba(rng):
    m = Mix(24)
    melody = ["C5", "E5", "G5", "E5", "D5", "G5", "A5", "G5", "E5", "G5", "C6", "A5", "G5", "E5", "D5", "E5"]
    roots = ["C4", "A3", "F3", "G3"]
    step = 0.26
    for bar in range(int(24 / (step * 16)) + 1):
        t0 = bar * step * 16
        m.put(t0, kalimba(hz(roots[bar % 4])), 0.35)
        m.put(t0 + step * 8, kalimba(hz(roots[bar % 4]) * 1.5), 0.25)
        for k, note in enumerate(melody):
            if bar % 2 and k in (6, 14):
                note = "B5" if note == "A5" else "C5"
            m.put(t0 + k * step, kalimba(hz(note)), 0.28 if k % 4 == 0 else 0.2)
    m.buf = reverb(m.buf, 0.22)
    return m


def s_marimba(rng):
    m = Mix(24)
    chords = [["F3", "A3", "C4", "F4"], ["Bb3", "D4", "F4", "Bb4"], ["D3", "F3", "A3", "D4"], ["C3", "E3", "G3", "C4"]]
    step = 0.25
    t = 0.0
    k = 0
    while t < 24:
        chord = chords[(k // 8) % 4]
        order = [0, 1, 2, 3, 2, 3, 1, 2]
        f = hz(chord[order[k % 8]]) * 2
        m.put(t, marimba(f), 0.32)
        if k % 4 == 0:
            m.put(t, marimba(hz(chord[0])), 0.3)
        t += step
        k += 1
    m.buf = reverb(m.buf, 0.2)
    return m


def s_carillon(rng):
    m = Mix(24)
    theme = ["F5", "A5", "C6", "A5", "Bb5", "G5", "E5", "C5", "D5", "F5", "A5", "G5", "F5", "C5", "F5", "-"]
    theme2 = ["A5", "C6", "F6", "C6", "D6", "Bb5", "G5", "E5", "F5", "A5", "C6", "Bb5", "A5", "G5", "F5", "-"]
    bass = ["F4", "C5", "Bb4", "F4", "D4", "A4", "C4", "G4"]
    step = 0.3
    for rep in range(6):
        t0 = rep * 16 * step
        line = theme if rep % 2 == 0 else theme2
        for k, note in enumerate(line):
            if note != "-":
                m.put(t0 + k * step, musicbox(hz(note)), 0.3)
        for k, note in enumerate(bass):
            m.put(t0 + k * 2 * step, musicbox(hz(note)), 0.18)
    m.buf = reverb(m.buf, 0.3)
    return m


def s_nuvole(rng):
    m = Mix(26)
    prog = [["E3", "G3", "B3", "D4"], ["A2", "G3", "C#4", "E4"], ["D3", "F#3", "A3", "C#4"], ["B2", "F#3", "A3", "D4"]]
    t = 0.0
    k = 0
    while t < 25:
        chord = prog[k % 4]
        for j, note in enumerate(chord):
            m.put(t + j * 0.045, epiano(hz(note), 3.2), 0.22)
        m.put(t + 1.6, epiano(hz(chord[-1]) * 2, 1.6), 0.12)
        for note in chord[:2]:
            m.put(t, pad(hz(note), 3.6, 0.8, 1.2), 0.07)
        t += 3.2
        k += 1
    m.buf = reverb(m.buf, 0.35)
    return m


def s_ruscello(rng):
    m = Mix(24)
    scale = [midi(n) for n in ["G4", "A4", "B4", "D5", "E5", "G5", "A5", "B5", "D6"]]
    pos = 4
    t = 0.1
    while t < 23.6:
        pos = max(0, min(len(scale) - 1, pos + rng.choice([-2, -1, -1, 1, 1, 2])))
        m.put(t, kalimba(mtof(scale[pos])), rng.uniform(0.12, 0.22))
        t += 0.14 * rng.choice([1, 1, 1, 2])
    for i in range(12):
        m.put(i * 2.0, kalimba(hz(["G3", "E3", "C3", "D3"][i % 4])), 0.3)
    m.buf = reverb(m.buf, 0.32)
    return m


def s_lucciole(rng):
    m = Mix(26)
    for i, chord in enumerate([["A2", "E3", "B3", "C4"], ["F2", "C3", "A3", "E4"], ["C3", "G3", "D4", "E4"], ["G2", "D3", "B3", "D4"]]):
        for note in chord:
            m.put(i * 6.4, pad(hz(note), 8.5, 3.0, 3.0, cutoff=1500), 0.15)
    pool = ["A5", "B5", "C6", "E6", "G6", "A6", "B6"]
    t = 0.5
    while t < 25:
        m.put(t, glass(hz(rng.choice(pool))), rng.uniform(0.07, 0.15))
        t += rng.expovariate(2.2)
    m.buf = reverb(m.buf, 0.45, 1.25)
    return m


def s_primavera(rng):
    m = Mix(24)
    step = 0.2
    bars = [["G4", "B4", "D5", "G5", "D5", "B4"], ["C5", "E5", "G5", "E5", "D5", "C5"],
            ["A4", "C5", "E5", "D5", "C5", "B4"], ["D5", "F#5", "A5", "F#5", "E5", "D5"]]
    roots = ["G3", "C3", "A3", "D3"]
    t = 0.0
    k = 0
    while t < 24:
        bar = bars[k % 4]
        for j, note in enumerate(bar):
            m.put(t + j * step, marimba(hz(note)), 0.3 if j % 3 == 0 else 0.22)
            if j % 3 == 0:
                m.put(t + j * step, marimba(hz(roots[k % 4])), 0.3)
        if k % 2:
            m.put(t + 0.1, kalimba(hz(bar[2]) * 2), 0.12)
        t += step * 6
        k += 1
    m.buf = reverb(m.buf, 0.2)
    return m


def s_tepore(rng):
    m = Mix(26)
    prog = [["C3", "E4", "G4", "C5"], ["E3", "B3", "E4", "G4"], ["F3", "A3", "C4", "F4"], ["F3", "Ab3", "C4", "F4"]]
    step = 0.3
    t = 0.0
    k = 0
    while t < 25.5:
        chord = prog[(k // 8) % 4]
        order = [0, 1, 2, 3, 2, 1, 3, 2]
        idx = order[k % 8]
        m.put(t, epiano(hz(chord[idx]) * (1 if idx else 1), 2.2), 0.24 if idx else 0.3)
        if k % 8 == 0:
            sub = [0.0] * int(2.4 * SR)
            add_partial(sub, hz(chord[0]) / 2, 1.0, 1.2)
            m.put(t, fade(sub, 0.02, 0.2), 0.3)
        t += step
        k += 1
    m.buf = reverb(m.buf, 0.3)
    return m


def s_campanelli(rng):
    m = Mix(24)
    tubes = [hz(n) for n in ["D5", "E5", "G5", "A5", "B5", "D6"]]
    t = 0.3
    while t < 23.5:
        density = 0.6 + t / 12
        gust = rng.random() < 0.18
        count = rng.randint(3, 6) if gust else 1
        for c in range(count):
            m.put(t + c * rng.uniform(0.06, 0.15), handbell(rng.choice(tubes)), rng.uniform(0.1, 0.2))
        t += rng.expovariate(density) + 0.12
    m.buf = reverb(m.buf, 0.4, 1.15)
    return m


# --------------------------------------------------------------------------- suonerie: Classiche

def s_campana(rng):
    m = Mix(24)
    bells = [hz("D4"), hz("A3")]
    t = 0.0
    k = 0
    while t < 22:
        m.put(t, church(bells[k % 2]), 0.45)
        t += 1.8
        k += 1
    m.buf = reverb(m.buf, 0.3, 1.2)
    return m


def s_sveglia_antica(rng):
    m = Mix(24)
    b1 = struck("clock", CLOCKBELL, 1180.0, 0.9, 0.0008)
    b2 = struck("clock", CLOCKBELL, 1265.0, 0.9, 0.0008)
    t = 0.0
    while t < 23:
        ring_end = t + 1.7
        s = t
        k = 0
        while s < ring_end:
            m.put(s, b1 if k % 2 == 0 else b2, rng.uniform(0.22, 0.3))
            s += 1 / 17.0
            k += 1
        t = ring_end + 0.6
    lowpass(m.buf, 6000)
    return m


def s_bip(rng):
    m = Mix(22)
    t = 0.2
    while t < 21.5:
        fast = t > 10
        for i in range(4):
            m.put(t + i * 0.15, beep(1320.0, 0.09), 0.5)
        t += 0.6 + (0.25 if fast else 0.55)
    return m


def s_pendolo(rng):
    m = Mix(24)
    tick = struck("tick", [(1, 1.0, 0.012), (2.7, 0.5, 0.006)], 2400.0, 0.08, 0.0005)
    tock = struck("tick", [(1, 1.0, 0.014), (2.7, 0.5, 0.007)], 1700.0, 0.08, 0.0005)
    for i in range(48):
        m.put(i * 0.5, tick if i % 2 == 0 else tock, 0.25)
    phrase = ["E5", "G5", "D5", "C5"]
    for rep, start in enumerate([0.5, 6.5, 12.5, 18.5]):
        for j, note in enumerate(phrase if rep % 2 == 0 else list(reversed(phrase))):
            m.put(start + j * 0.9, handbell(hz(note)), 0.32)
        m.put(start + 4.0, handbell(hz("C4")), 0.3)
    m.buf = reverb(m.buf, 0.25)
    return m


def s_digitale(rng):
    m = Mix(22)
    t = 0.2
    gap = 0.7
    while t < 21.5:
        for i in range(2):
            m.put(t + i * 0.28, beep(988.0, 0.12), 0.45)
            m.put(t + i * 0.28 + 0.14, beep(1318.5, 0.12), 0.45)
        t += 0.56 + gap
        gap = max(0.25, gap * 0.9)
    return m


def s_squillo(rng):
    m = Mix(24)
    t = 0.0
    while t < 23:
        for burst in range(2):
            b0 = t + burst * 1.6
            n = int(1.1 * SR)
            out = [0.0] * n
            ph = 0.0
            for i in range(n):
                f = 1020.0 if (i // (SR // 32)) % 2 == 0 else 1300.0
                ph += TAU * f / SR
                out[i] = math.sin(ph) + 0.15 * math.sin(2 * ph)
            lowpass(out, 3500)
            m.put(b0, fade(out, 0.02, 0.05), 0.4)
        t += 4.2
    return m


def s_sonar(rng):
    m = Mix(24)
    t = 0.2
    k = 0
    while t < 22.5:
        f = [hz("A5"), hz("A5"), hz("C6"), hz("E6")][k % 4]
        ping = struck("ping", [(1, 1.0, 0.6), (2.01, 0.1, 0.2)], f, 2.0, 0.003)
        m.put(t, ping, 0.42)
        m.put(t + 0.32, ping, 0.15)
        m.put(t + 0.64, ping, 0.06)
        t += 1.5
        k += 1
    m.buf = reverb(m.buf, 0.35, 1.2)
    return m


def s_campanile(rng):
    m = Mix(26)
    peal = [hz(n) for n in ["G5", "F5", "E5", "D5", "C5", "B4"]]
    t = 0.0
    k = 0
    while t < 25:
        order = list(range(6)) if (k // 6) % 3 != 2 else [0, 2, 1, 4, 3, 5]
        m.put(t, handbell(peal[order[k % 6]] * 0.5), 0.36)
        t += 0.36 + (0.36 if k % 6 == 5 else 0.0)
        k += 1
    m.buf = reverb(m.buf, 0.3, 1.2)
    return m


def s_xilofono(rng):
    m = Mix(22)
    chords = [["C5", "E5", "G5", "B5"], ["A4", "C5", "E5", "G5"], ["D5", "F5", "A5", "C6"], ["G4", "B4", "D5", "F5"]]
    step = 0.11
    t = 0.0
    k = 0
    while t < 21.8:
        chord = chords[(k // 16) % 4]
        up = [hz(n) for n in chord] + [hz(n) * 2 for n in chord]
        seq = up + list(reversed(up))
        m.put(t, xylo(seq[k % 16]), 0.36 if k % 4 == 0 else 0.26)
        t += step
        k += 1
    m.buf = reverb(m.buf, 0.15)
    return m


def s_organetto(rng):
    m = Mix(24)
    beat = 0.33
    harmony = [("C3", ["E4", "G4"]), ("G2", ["D4", "F4"]), ("A2", ["C4", "E4"]), ("F2", ["A3", "C4"])]
    melody = ["G5", "E5", "C5", "D5", "E5", "F5", "E5", "D5", "B4", "C5", "D5", "E5", "A4", "C5", "F5", "E5", "D5", "C5"]
    for bar in range(int(24 / (beat * 3))):
        t0 = bar * beat * 3
        root, chord = harmony[(bar // 2) % 4]
        m.put(t0, tone(hz(root), beat * 0.9, "organ", 8, 0.01, 0.05), 0.35)
        for b in (1, 2):
            for note in chord:
                m.put(t0 + b * beat, tone(hz(note), beat * 0.6, "organ", 8, 0.01, 0.05), 0.16)
        for b in range(3):
            note = melody[(bar * 3 + b) % len(melody)]
            m.put(t0 + b * beat, tone(hz(note), beat * 0.85, "organ", 6, 0.01, 0.06), 0.22)
    lowpass(m.buf, 4500)
    m.buf = reverb(m.buf, 0.2)
    return m


# --------------------------------------------------------------------------- suonerie: Energiche

def s_turbo(rng):
    m = Mix(24)
    step = 0.11
    chords = [["A3", "C4", "E4"], ["F3", "A3", "C4"], ["C4", "E4", "G4"], ["G3", "B3", "D4"]]
    k = 0
    t = 0.0
    while t < 24:
        chord = chords[(k // 16) % 4]
        notes = [hz(n) for n in chord] + [hz(chord[0]) * 2]
        f = notes[[0, 1, 2, 3, 2, 1, 3, 2][k % 8]] * (2 if (k // 8) % 2 else 1)
        m.put(t, pluck(f, 0.25, "saw", 2600, 0.12), 0.22)
        if k % 2 == 0:
            m.put(t, pluck(hz(chord[0]) / 2, 0.22, "saw", 700, 0.15), 0.3)
        if k % 4 == 0 and t > 3.5:
            m.put(t, kick(), 0.6)
        if k % 4 == 2 and t > 7:
            m.put(t, hihat(), 0.18)
        t += step
        k += 1
    return m


def s_pulsar(rng):
    m = Mix(24)
    e = 0.234
    chords = [["D3", "A3", "D4", "F4"], ["Bb2", "F3", "Bb3", "D4"], ["C3", "G3", "C4", "E4"], ["A2", "E3", "A3", "C#4"]]
    k = 0
    t = 0.0
    while t < 24:
        chord = chords[(k // 16) % 4]
        build = min(1.0, 0.55 + t / 20)
        cutoff = 900 + 2600 * min(1.0, t / 18)
        for note in chord:
            m.put(t, pluck(hz(note), 0.2, "saw", round(cutoff, -2), 0.09), 0.13 * build)
        if k % 2 == 0:
            m.put(t, kick(), 0.55 * build)
        else:
            m.put(t, hihat(0.05), 0.15)
            m.put(t, pluck(hz(chord[0]) / 2, 0.2, "square", 600, 0.1), 0.3)
        t += e
        k += 1
    return m


def s_sirena(rng):
    m = Mix(24)
    t = 0.0
    period = 2.4
    while t < 23.5:
        level = min(1.0, 0.45 + t / 20)
        half = period / 2
        m.put(t, sweep(620, 1150, half, curve="cos", attack=0.05, release=0.01), 0.4 * level)
        m.put(t + half, sweep(1150, 620, half, curve="cos", attack=0.01, release=0.05), 0.4 * level)
        t += period
        period = max(0.7, period * 0.88)
    lowpass(m.buf, 5000)
    return m


def s_allerta(rng):
    m = Mix(22)
    t = 0.0
    dur = 0.45
    k = 0
    while t < 21.6:
        f = 740.0 if k % 2 == 0 else 988.0
        m.put(t, tone(f, dur * 0.95, "soft", 6, 0.01, 0.02, 3500), 0.33)
        if k % 2 == 0:
            m.put(t, pluck(hz("E2"), dur * 1.8, "saw", 500, 0.2), 0.35)
        t += dur
        dur = max(0.22, dur * 0.985)
        k += 1
    return m


def s_scintille(rng):
    m = Mix(24)
    pent = [midi(n) for n in ["E5", "F#5", "A5", "B5", "C#6", "E6", "F#6", "A6"]]
    step = 0.1
    t = 0.0
    k = 0
    while t < 24:
        base = [0, 2, 1, 3][(k // 16) % 4]
        f = mtof(pent[(base + [0, 1, 2, 3, 4, 3, 2, 1][k % 8]) % len(pent)])
        m.put(t, fm(f, 0.7, 3.5, 1.2, 0.08, 0.3), 0.22 if k % 4 else 0.3)
        if k % 2 == 0:
            m.put(t, hihat(0.04), 0.12)
        if k % 8 == 0:
            m.put(t, pluck(hz(["E3", "C#3", "A2", "B2"][(k // 16) % 4]), 0.6, "saw", 800, 0.25), 0.35)
        t += step
        k += 1
    m.buf = reverb(m.buf, 0.15)
    return m


def s_carica(rng):
    m = Mix(24)
    beat = 0.48
    stabs = [["G3", "Bb3", "D4"], ["Eb3", "G3", "Bb3"], ["F3", "A3", "C4"], ["D3", "F#3", "A3"]]
    for b in range(int(24 / beat)):
        t = b * beat
        bar = b // 4
        m.put(t, kick(), 0.6)
        m.put(t + beat / 2, hihat(0.07), 0.2)
        for note in stabs[bar % 4]:
            m.put(t + beat / 2, pluck(hz(note) * 2, 0.18, "saw", 3000, 0.07), 0.1)
        if b % 2 == 1:
            m.put(t, clap(), 0.35)
        if b % 16 == 12:
            m.put(t, sweep(300, 2400, beat * 4, harmonics=((1, 1.0), (2, 0.3)), attack=1.2, release=0.05), 0.12)
    return m


def s_galoppo(rng):
    m = Mix(24)
    trip = 0.16
    bass = ["A2", "A2", "E3", "A2", "A2", "E3", "F2", "F2", "C3", "G2", "G2", "D3"]
    lead = ["A4", "C5", "E5", "D5", "C5", "B4", "C5", "A4", "G4", "B4", "D5", "-"]
    k = 0
    t = 0.0
    while t < 24:
        m.put(t, pluck(hz(bass[k % 12]), 0.15, "square", 900, 0.08), 0.3)
        if k % 3 == 0:
            note = lead[(k // 3) % 12]
            if note != "-":
                m.put(t, tone(hz(note), trip * 2.6, "square", 8, 0.01, 0.05, 2800), 0.18)
            m.put(t, kick(), 0.4)
        if k % 6 == 3:
            m.put(t, snare(), 0.3)
        t += trip
        k += 1
    return m


def s_decollo(rng):
    m = Mix(24)
    t = 0.0
    cycle = 0
    while t < 22:
        length = 3.6
        base = 220 * 2 ** (cycle / 12 * 2)
        riser = sweep(base, base * 2, length, harmonics=((1, 1.0), (2, 0.4), (3, 0.2), (4, 0.1)), attack=0.3, release=0.02)
        n = len(riser)
        for i in range(n):
            x = i / n
            trem = 0.75 + 0.25 * math.sin(TAU * (4 + 12 * x) * i / SR)
            riser[i] *= trem * (0.4 + 0.6 * x)
        m.put(t, riser, 0.3)
        hit = t + length
        for note in (1, 1.25, 1.5, 2):
            m.put(hit, pluck(base * 2 * note, 0.5, "saw", 3200, 0.2), 0.12)
        m.put(hit, kick(), 0.6)
        t = hit + 0.5
        cycle += 1
    return m


def s_festa(rng):
    m = Mix(24)
    beat = 0.42
    chords = [["C4", "E4", "G4"], ["A3", "C4", "F4"], ["G3", "B3", "D4"], ["C4", "E4", "G4"]]
    hook = ["E5", "G5", "A5", "G5", "E5", "D5", "C5", "D5", "E5", "E5", "D5", "-", "C5", "D5", "E5", "G5"]
    for b in range(int(24 / beat)):
        t = b * beat
        bar = b // 4
        m.put(t, kick(), 0.55)
        if b % 2:
            m.put(t, clap(), 0.3)
        for off in (0.0, 0.75):
            for note in chords[bar % 4]:
                m.put(t + beat * off, tone(hz(note), beat * 0.22, "organ", 8, 0.004, 0.03), 0.09)
        m.put(t, pluck(hz(chords[bar % 4][0]) / 2, beat * 0.9, "saw", 600, 0.2), 0.3)
        for half in (0, 1):
            note = hook[(b * 2 + half) % 16]
            if note != "-" and b >= 8:
                m.put(t + half * beat / 2, tone(hz(note), beat * 0.45, "square", 8, 0.005, 0.04, 3000), 0.15)
    return m


def s_tamburi(rng):
    m = Mix(24)
    s = 0.13
    for k in range(int(24 / s)):
        t = k * s
        layer = int(t // 6)
        step = k % 16
        if step in (0, 6, 10):
            m.put(t, kick(), 0.6)
        if layer >= 1 and step in (4, 12):
            m.put(t, snare(), 0.45)
        if layer >= 1:
            m.put(t, hihat(0.04), 0.14 if step % 2 else 0.2)
        if layer >= 2 and step in (0, 3, 6, 8, 11, 14):
            m.put(t, marimba(hz(["E4", "G4", "A4", "B4", "D5", "E5"][step % 6])), 0.3)
        if layer >= 3 and k % 64 >= 58:
            m.put(t, tom([180.0, 150.0, 120.0, 100.0, 90.0, 80.0][k % 64 - 58]), 0.45)
        elif layer >= 0 and step in (2, 13) and layer < 1:
            m.put(t, tom(140.0), 0.35)
    return m


def s_laser(rng):
    m = Mix(22)
    e = 0.2
    pattern = [1, 0, 1, 1, 0, 1, 0, 1]
    zap = sweep(1800, 220, 0.18, harmonics=((1, 1.0), (2, 0.35), (3, 0.2)), attack=0.002, release=0.02)
    zap2 = sweep(2400, 400, 0.12, harmonics=((1, 1.0), (3, 0.3)), attack=0.002, release=0.02)
    for k in range(int(22 / e)):
        t = k * e
        if pattern[k % 8]:
            m.put(t, zap if k % 3 else zap2, 0.3)
        if k % 2 == 0:
            m.put(t, pluck(hz(["E2", "E2", "G2", "D2"][(k // 16) % 4]), 0.18, "saw", 700, 0.1), 0.35)
        if k % 4 == 0 and t > 4:
            m.put(t, kick(), 0.5)
    lowpass(m.buf, 6500)
    return m


# --------------------------------------------------------------------------- catalogo

# (id, famiglia, nome italiano, funzione, dissolvenza iniziale in s)
SOUNDS = [
    ("alba", "gentle", "Alba", s_alba, 10.0),
    ("rugiada", "gentle", "Rugiada", s_rugiada, 7.0),
    ("kalimba", "gentle", "Kalimba", s_kalimba, 6.0),
    ("marimba", "gentle", "Marimba al sole", s_marimba, 6.0),
    ("carillon", "gentle", "Carillon", s_carillon, 6.0),
    ("nuvole", "gentle", "Nuvole", s_nuvole, 8.0),
    ("ruscello", "gentle", "Ruscello", s_ruscello, 7.0),
    ("lucciole", "gentle", "Lucciole", s_lucciole, 9.0),
    ("primavera", "gentle", "Primavera", s_primavera, 5.0),
    ("tepore", "gentle", "Tepore", s_tepore, 8.0),
    ("campanelli", "gentle", "Campanelli al vento", s_campanelli, 7.0),
    ("campana", "classic", "Campana", s_campana, 0.0),
    ("sveglia-antica", "classic", "Sveglia antica", s_sveglia_antica, 0.0),
    ("bip", "classic", "Bip bip", s_bip, 0.0),
    ("pendolo", "classic", "Pendolo", s_pendolo, 0.0),
    ("digitale", "classic", "Digitale", s_digitale, 0.0),
    ("squillo", "classic", "Squillo", s_squillo, 0.0),
    ("sonar", "classic", "Sonar", s_sonar, 0.0),
    ("campanile", "classic", "Campanile", s_campanile, 0.0),
    ("xilofono", "classic", "Xilofono", s_xilofono, 0.0),
    ("organetto", "classic", "Organetto", s_organetto, 0.0),
    ("turbo", "energetic", "Arpeggio turbo", s_turbo, 0.0),
    ("pulsar", "energetic", "Pulsar", s_pulsar, 0.0),
    ("sirena", "energetic", "Sirena", s_sirena, 0.0),
    ("allerta", "energetic", "Allerta", s_allerta, 0.0),
    ("scintille", "energetic", "Scintille", s_scintille, 0.0),
    ("carica", "energetic", "Carica", s_carica, 0.0),
    ("galoppo", "energetic", "Galoppo", s_galoppo, 0.0),
    ("decollo", "energetic", "Decollo", s_decollo, 0.0),
    ("festa", "energetic", "Festa", s_festa, 0.0),
    ("tamburi", "energetic", "Tamburi", s_tamburi, 0.0),
    ("laser", "energetic", "Laser", s_laser, 0.0),
]

DEFAULT_ID = "pulsar"


def file_name(sound_id):
    return "suoneria-%s.caf" % sound_id


# --------------------------------------------------------------------------- mastering

def loudest_rms(buf, window=3.0, hop=0.5):
    w = int(window * SR)
    h = int(hop * SR)
    best = 0.0
    for start in range(0, max(1, len(buf) - w + 1), h):
        seg = buf[start:start + w]
        best = max(best, math.sqrt(sum(x * x for x in seg) / len(seg)))
    return best


def master(buf, fade_in, gentle):
    n = len(buf)
    # Toglie la componente continua.
    mean = sum(buf) / n
    buf = [x - mean for x in buf]
    if fade_in > 0:
        k = int(fade_in * SR)
        floor = 10 ** (-26 / 20)
        for i in range(min(k, n)):
            x = i / k
            buf[i] *= floor ** (1 - x)  # da -26 dB a 0 dB, lineare in dB
    fade(buf, 0.01, 0.6)
    target = 10 ** ((GENTLE_TARGET_RMS_DB if gentle else TARGET_RMS_DB) / 20)
    gain = target / max(loudest_rms(buf), 1e-9)
    ceiling = 10 ** (CEILING_DB / 20)
    knee = ceiling * 0.6
    limited = 0
    out = [0.0] * n
    for i in range(n):
        x = buf[i] * gain
        a = abs(x)
        if a > knee:
            a = knee + (ceiling - knee) * math.tanh((a - knee) / (ceiling - knee))
            limited += 1
            x = a if x > 0 else -a
        out[i] = x
    peak = max(abs(x) for x in out)
    if peak > ceiling:
        out = [x * ceiling / peak for x in out]
    return out, gain, limited / n


def write_wav(path, buf):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(round(max(-1.0, min(1.0, x)) * 32767))) for x in buf))


def write_swift(entries):
    lines = [
        "// Generato da tools/genera_suonerie.py: non modificare a mano.",
        "",
        "extension RingtoneCatalog {",
        "    /// Le suonerie incluse nell'app, tutte originali (sintetizzate), in ordine di presentazione.",
        "    static let builtIn: [Ringtone] = [",
    ]
    for sound_id, family, title, _, _ in entries:
        lines.append('        Ringtone(fileName: "%s", name: "%s", family: .%s),' % (file_name(sound_id), title, family))
    lines += [
        "    ]",
        "",
        "    /// La suoneria proposta per le nuove sveglie.",
        '    static let defaultSoundName = "%s"' % file_name(DEFAULT_ID),
        "}",
        "",
    ]
    os.makedirs(os.path.dirname(SWIFT_OUT), exist_ok=True)
    with open(SWIFT_OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main():
    only = None
    if "--solo" in sys.argv:
        only = set(sys.argv[sys.argv.index("--solo") + 1].split(","))
    ids = [s[0] for s in SOUNDS]
    assert len(ids) == len(set(ids)), "id duplicati"
    assert DEFAULT_ID in ids
    os.makedirs(OUT_DIR, exist_ok=True)
    write_swift(SOUNDS)
    tmp = tempfile.mkdtemp(prefix="suonerie-")
    print("%-16s %-10s %6s %8s %8s %8s %7s" % ("id", "famiglia", "durata", "picco", "RMS3s", "guad.", "limit."))
    for sound_id, family, title, fn, fade_in in SOUNDS:
        if only and sound_id not in only:
            continue
        _cache.clear()
        rng = random.Random(sound_id)
        mix = fn(rng)
        gentle = family == "gentle"
        out, gain, limited = master(mix.buf, fade_in, gentle)
        peak = max(abs(x) for x in out)
        seconds = len(out) / SR
        assert seconds < 29.5, "%s: troppo lungo" % sound_id
        assert db(peak) <= -1.0, "%s: clipping" % sound_id
        wav = os.path.join(tmp, sound_id + ".wav")
        write_wav(wav, out)
        caf = os.path.join(OUT_DIR, file_name(sound_id))
        subprocess.run(["afconvert", wav, caf, "-f", "caff", "-d", "ima4"], check=True)
        os.remove(wav)
        print("%-16s %-10s %5.1fs %7.1fdB %7.1fdB %+7.1fdB %6.2f%%" % (
            sound_id, family, seconds, db(peak), db(loudest_rms(out)), db(gain), limited * 100))
        sys.stdout.flush()
    os.rmdir(tmp)
    total = sum(os.path.getsize(os.path.join(OUT_DIR, f)) for f in os.listdir(OUT_DIR) if f.endswith(".caf"))
    print("Totale: %.2f MB in %s" % (total / 1e6, OUT_DIR))


if __name__ == "__main__":
    main()
