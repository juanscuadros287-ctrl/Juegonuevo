#!/usr/bin/env python3
"""Genera TODA la música y los efectos de sonido de Dinastía de forma procedimental.

Sin muestras de terceros: cada sonido sale de síntesis (Karplus-Strong, aditiva, FM, ruido
filtrado) con envolventes ADSR, escalas/modos coherentes, acordes con conducción de voces y una
reverb por convolución con respuesta al impulso sintética. Ver docs/AUDIO.md.

Uso:
    python3 tools/make_audio.py              # todo (música + efectos + ambientes)
    python3 tools/make_audio.py music        # solo música
    python3 tools/make_audio.py sfx amb      # solo efectos y ambientes
    python3 tools/make_audio.py --only colonial_1,ui_click
    python3 tools/make_audio.py --check      # estadísticas (pico, RMS, DC, recorte) sin escribir

Requisitos: numpy y scipy. Para OGG Vorbis: el módulo `soundfile` (libsndfile ≥ 1.0.29) o los
programas `oggenc` / `ffmpeg`. Sin ninguno de ellos escribe WAV de 16 bits (módulo `wave`).
Todo es determinista: la misma semilla produce los mismos archivos.
"""
import math
import os
import shutil
import subprocess
import sys
import wave
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from scipy import signal

SR = 32000
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "assets", "audio")

# ---------------------------------------------------------------------------------------------
# Utilidades de señal
# ---------------------------------------------------------------------------------------------


def midi_hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def t_axis(n, sr=SR):
    return np.arange(n, dtype=np.float64) / sr


def adsr(n, a, d, s, r, hold=None, sr=SR):
    """Envolvente ADSR de n muestras. hold = duración (s) antes del release (por defecto n - r)."""
    env = np.zeros(n)
    na, nd, nr = int(a * sr), int(d * sr), int(r * sr)
    nh = int(hold * sr) if hold is not None else max(0, n - nr)
    nh = min(nh, n)
    i = 0
    if na > 0:
        k = min(na, nh)
        env[:k] = np.linspace(0, 1, na, endpoint=False)[:k] ** 1.5 if k > 0 else 0
        i = k
    if i < nh and nd > 0:
        k = min(nd, nh - i)
        env[i:i + k] = 1.0 - (1.0 - s) * (np.linspace(0, 1, nd, endpoint=False)[:k])
        i += k
    if i < nh:
        env[i:nh] = s
    level = env[nh - 1] if nh > 0 else 0.0
    if nh < n:
        tail = n - nh
        rr = max(1, nr)
        x = np.arange(tail) / rr
        env[nh:] = level * np.exp(-5.0 * x)
    return env


def lp(x, fc, order=2, sr=SR):
    fc = min(fc, sr * 0.45)
    b, a = signal.butter(order, fc / (sr / 2), "low")
    return signal.lfilter(b, a, x, axis=0)


def hp(x, fc, order=2, sr=SR):
    b, a = signal.butter(order, fc / (sr / 2), "high")
    return signal.lfilter(b, a, x, axis=0)


def bp(x, lo, hi, order=2, sr=SR):
    hi = min(hi, sr * 0.45)
    b, a = signal.butter(order, [lo / (sr / 2), hi / (sr / 2)], "band")
    return signal.lfilter(b, a, x, axis=0)


def one_pole(x, coef):
    return signal.lfilter([1 - coef], [1, -coef], x, axis=0)


def pink(n, rng):
    """Ruido rosa por conformado espectral (1/f)."""
    w = rng.standard_normal(n)
    f = np.fft.rfft(w)
    k = np.arange(len(f))
    k[0] = 1
    f /= np.sqrt(k)
    y = np.fft.irfft(f, n)
    return y / (np.std(y) + 1e-9)


def brown(n, rng):
    y = np.cumsum(rng.standard_normal(n))
    y = hp(y, 20.0)
    return y / (np.std(y) + 1e-9)


def smooth_noise(n, rate_hz, rng, sr=SR):
    """Curva aleatoria suave (0..1) que cambia unas `rate_hz` veces por segundo."""
    pts = max(4, int(n / sr * rate_hz) + 4)
    v = rng.random(pts)
    xp = np.linspace(0, n, pts)
    y = np.interp(np.arange(n), xp, v)
    k = max(3, int(sr / rate_hz / 2))
    win = np.hanning(k)
    y = signal.fftconvolve(np.pad(y, k, mode="edge"), win / np.sum(win), mode="same")[k:-k]
    return np.clip(y, 0, 1)


def pan2(x, pan):
    """Paneo de potencia constante: pan en -1..1."""
    a = (pan + 1) * math.pi / 4
    return np.stack([x * math.cos(a), x * math.sin(a)], axis=1)


def add_at(buf, x, start):
    if start >= len(buf):
        return
    if start < 0:
        x = x[-start:]
        start = 0
    end = min(len(buf), start + len(x))
    buf[start:end] += x[:end - start]


_IR_CACHE = {}


def reverb_ir(t60=1.8, length=2.6, predelay=0.02, seed=7, damp=3500.0):
    key = (t60, length, predelay, seed, damp)
    if key in _IR_CACHE:
        return _IR_CACHE[key]
    rng = np.random.default_rng(seed)
    n = int(length * SR)
    t = t_axis(n)
    chans = []
    for c in range(2):
        nz = rng.standard_normal(n)
        low = lp(nz, damp) * 10 ** (-3 * t / t60)
        high = hp(nz, damp) * 10 ** (-3 * t / (t60 * 0.45))
        ir = low + 0.5 * high
        # Primeras reflexiones dispersas.
        for _ in range(10):
            p = int(rng.uniform(0.005, 0.07) * SR)
            ir[p] += rng.uniform(-1, 1) * 1.8
        ir = np.concatenate([np.zeros(int(predelay * SR)), ir])
        chans.append(ir)
    ir = np.stack(chans, axis=1)
    ir /= np.sqrt(np.sum(ir ** 2) / 2)
    _IR_CACHE[key] = ir
    return ir


def reverb(x, wet=0.25, t60=1.8, damp=3500.0, seed=7):
    """x estéreo (n, 2). Reverb por convolución; devuelve n + cola muestras."""
    ir = reverb_ir(t60=t60, damp=damp, seed=seed)
    ys = [signal.fftconvolve(x[:, c], ir[:, c]) for c in range(2)]
    y = np.stack(ys, axis=1)
    out = np.zeros_like(y)
    out[:len(x)] += x * (1 - wet * 0.5)
    out += y * wet
    return out


def loop_wrap(y, n):
    """Pliega la cola (reverb, notas sonando) sobre el inicio: el bucle queda sin cortes."""
    out = y[:n].copy()
    tail = y[n:]
    while len(tail) > 0:
        k = min(n, len(tail))
        out[:k] += tail[:k]
        tail = tail[k:]
    return out


def loop_crossfade(y, n, fade):
    """Para ruidos: y tiene n + fade muestras; mezcla el final sobre el inicio con igual potencia."""
    out = y[:n].copy()
    f = np.linspace(0, 1, fade)
    if y.ndim == 2:
        f = f[:, None]
    out[:fade] = y[:fade] * np.sqrt(f) + y[n:n + fade] * np.sqrt(1 - f)
    return out


def finalize(y, rms_db=-19.0, peak=0.89, fade_in=0.0, fade_out=0.0):
    y = y - np.mean(y, axis=0)
    rms = np.sqrt(np.mean(y ** 2)) + 1e-12
    y = y * (10 ** (rms_db / 20) / rms)
    # Limitador suave: por encima de 0.6 comprime con tanh hasta `peak`.
    knee = 0.6
    a = np.abs(y)
    over = a > knee
    y[over] = np.sign(y[over]) * (knee + (peak - knee) * np.tanh((a[over] - knee) / (peak - knee)))
    n = len(y)
    if fade_in > 0:
        k = int(fade_in * SR)
        e = np.linspace(0, 1, k) ** 2
        y[:k] *= e[:, None] if y.ndim == 2 else e
    if fade_out > 0:
        k = int(fade_out * SR)
        e = np.linspace(1, 0, k) ** 2
        y[n - k:] *= e[:, None] if y.ndim == 2 else e
    return y


# ---------------------------------------------------------------------------------------------
# Instrumentos (devuelven mono, float64)
# ---------------------------------------------------------------------------------------------


def karplus(freq, dur, vel=0.8, t60=2.5, bright=0.6, rng=None, ring=1.2, body=True):
    """Cuerda pulsada Karplus-Strong vectorizada por periodos. Afinación exacta por remuestreo."""
    rng = rng or np.random.default_rng(int(freq * 100))
    total = dur + ring
    period = SR / freq
    N = max(8, int(math.floor(period)))
    ratio = N / period                   # generamos a una frecuencia de muestreo virtual
    n_virtual = int(total * SR * ratio) + N + 2
    y = np.zeros(n_virtual)
    exc = rng.uniform(-1, 1, N)
    # Brillo del ataque: filtra la excitación (punteo con uña vs. con yema).
    for _ in range(int((1 - bright) * 6)):
        exc = 0.5 * (exc + np.roll(exc, 1))
    # Posición de pulsación (filtro peine) para timbre de guitarra.
    pk = max(1, int(N * 0.13))
    exc = exc - 0.6 * np.roll(exc, pk)
    exc -= exc.mean()
    y[:N] = exc
    d = 10 ** (-3.0 / (t60 * freq))
    blocks = n_virtual // N
    # Primer bloque: y[n-N-1] no existe aún → envuelve.
    prev = y[0:N]
    y[N:2 * N] = d * 0.5 * (prev + np.roll(prev, 1))
    for k in range(2, blocks):
        s = k * N
        pe = y[s - N - 1:s]
        y[s:s + N] = d * 0.5 * (pe[1:] + pe[:-1])
    # Remuestreo a la frecuencia real.
    n = int(total * SR)
    src = np.arange(n) * ratio
    out = np.interp(src, np.arange(n_virtual), y)
    # Apagado al soltar (dedo que apaga la cuerda).
    env = np.ones(n)
    off = int(dur * SR)
    if off < n:
        env[off:] = np.exp(-np.arange(n - off) / (0.25 * SR))
    out *= env
    if body:
        out = out + 0.35 * bp(out, 90, 260, 1)   # cuerpo de madera
    return out * vel


def flute(freq, dur, vel=0.7, rng=None, vib=0.0045):
    rng = rng or np.random.default_rng(int(freq))
    rel = 0.18
    n = int((dur + rel) * SR)
    t = t_axis(n)
    vib_env = np.clip((t - 0.25) / 0.4, 0, 1)
    f = freq * (1 + vib * vib_env * np.sin(2 * math.pi * 5.0 * t + rng.uniform(0, 6)))
    ph = 2 * math.pi * np.cumsum(f) / SR
    tone = np.sin(ph) + 0.22 * np.sin(2 * ph + 0.3) + 0.07 * np.sin(3 * ph + 0.9) + 0.03 * np.sin(4 * ph)
    breath = bp(rng.standard_normal(n), freq * 1.2, min(freq * 4, 9000), 1) * 0.12
    env = adsr(n, 0.07, 0.15, 0.85, rel, hold=dur)
    amp_trem = 1 + 0.04 * vib_env * np.sin(2 * math.pi * 5.0 * t)
    chiff = np.exp(-t / 0.03) * 0.3
    return (tone * amp_trem + breath * (0.6 + chiff * 3)) * env * vel * 0.5


def saw_additive(freq, n, detune_cents=0.0, phase=0.0, max_h=24, tilt=1.0):
    t = t_axis(n)
    f = freq * 2 ** (detune_cents / 1200)
    y = np.zeros(n)
    hmax = int(min(max_h, (SR * 0.42) // f))
    for k in range(1, max(2, hmax + 1)):
        y += np.sin(2 * math.pi * f * k * t + phase * k) / (k ** tilt)
    return y


def strings(freq, dur, vel=0.6, rng=None, attack=0.5, release=1.0, bright=2500.0):
    rng = rng or np.random.default_rng(int(freq * 3))
    n = int((dur + release) * SR)
    y = np.zeros(n)
    for dc in (-7, -2, 3, 8):
        y += saw_additive(freq, n, dc + rng.uniform(-1, 1), rng.uniform(0, 6), max_h=18, tilt=1.1)
    t = t_axis(n)
    y *= 1 + 0.05 * np.sin(2 * math.pi * 5.2 * t + rng.uniform(0, 6)) * np.clip(t / 0.8, 0, 1)
    y = lp(y, bright, 2)
    env = adsr(n, attack, 0.3, 0.9, release, hold=dur)
    return y * env * vel * 0.12


def piano(freq, dur, vel=0.7, rng=None):
    rng = rng or np.random.default_rng(int(freq * 7))
    rel = 0.35
    base_decay = 3.2 * (220.0 / freq) ** 0.45
    total = min(dur + rel, base_decay * 2.2 + rel)
    n = int(max(total, 0.25) * SR)
    t = t_axis(n)
    B = 0.00035
    y = np.zeros(n)
    bright = 0.55 + 0.6 * vel
    for k in range(1, 13):
        fk = freq * k * math.sqrt(1 + B * k * k)
        if fk > SR * 0.42:
            break
        amp = (1.0 / k ** 1.25) * (bright ** (k - 1) if k > 1 else 1.0)
        dk = base_decay / (1 + 0.45 * (k - 1))
        for det in (-0.6, 0.6):     # dos cuerdas por nota (coro suave)
            y += 0.5 * amp * np.sin(2 * math.pi * (fk + det * k * 0.25) * t + rng.uniform(0, 6)) * np.exp(-t / dk)
    # Doble decaimiento: golpe inicial y sostenido.
    y *= 0.55 + 0.45 * np.exp(-t / 0.25)
    hammer = lp(rng.standard_normal(n), 2500) * np.exp(-t / 0.006) * 0.25
    y += hammer
    env = np.ones(n)
    off = int(dur * SR)
    if off < n:
        env[off:] = np.exp(-np.arange(n - off) / (0.09 * SR))
    atk = min(n, int(0.004 * SR))
    env[:atk] *= np.linspace(0, 1, atk)
    return y * env * vel * 0.32


def epiano(freq, dur, vel=0.6, rng=None):
    """Piano eléctrico por FM (estilo Rhodes)."""
    rng = rng or np.random.default_rng(int(freq * 11))
    rel = 0.4
    n = int((dur + rel) * SR)
    t = t_axis(n)
    idx = (1.1 + 1.4 * vel) * np.exp(-t / 0.35) + 0.25
    mod = np.sin(2 * math.pi * freq * t)
    car = np.sin(2 * math.pi * freq * t + idx * mod)
    tine = np.sin(2 * math.pi * freq * 14.0 * t) * np.exp(-t / 0.05) * 0.12 * vel
    trem = 1 + 0.12 * np.sin(2 * math.pi * 4.2 * t + rng.uniform(0, 6))
    y = (car + tine) * trem
    decay = np.exp(-t / (2.4 * (220 / freq) ** 0.3))
    env = adsr(n, 0.003, 0.2, 1.0, rel, hold=dur) * decay
    return y * env * vel * 0.3


def brass(freq, dur, vel=0.6, rng=None):
    """Metal suave (trompa): la brillantez sube en el ataque."""
    rng = rng or np.random.default_rng(int(freq * 5))
    rel = 0.25
    n = int((dur + rel) * SR)
    t = t_axis(n)
    br = 0.8 + 2.6 * vel * (np.clip(t / 0.08, 0, 1) * (0.7 + 0.3 * np.exp(-t / 0.3)))
    vib = 1 + 0.003 * np.sin(2 * math.pi * 5.0 * t) * np.clip((t - 0.3) / 0.5, 0, 1)
    ph = 2 * math.pi * np.cumsum(freq * vib) / SR
    y = np.zeros(n)
    for k in range(1, 14):
        if freq * k > SR * 0.42:
            break
        y += np.exp(-k / br) * np.sin(k * ph)
    y = lp(y, 3200)
    env = adsr(n, 0.06, 0.2, 0.8, rel, hold=dur)
    return y * env * vel * 0.22


def soft_lead(freq, dur, vel=0.5, rng=None):
    """Sintetizador suave (triangular con vibrato) para la época moderna."""
    rel = 0.3
    n = int((dur + rel) * SR)
    t = t_axis(n)
    vib = 1 + 0.004 * np.sin(2 * math.pi * 5.5 * t) * np.clip((t - 0.2) / 0.4, 0, 1)
    ph = 2 * math.pi * np.cumsum(freq * vib) / SR
    y = np.zeros(n)
    for k in (1, 3, 5, 7):
        y += ((-1) ** ((k - 1) // 2)) * np.sin(k * ph) / (k * k)
    y += 0.25 * np.sin(2 * ph)
    env = adsr(n, 0.04, 0.3, 0.75, rel, hold=dur)
    return y * env * vel * 0.45


def synth_pad(freq, dur, vel=0.5, rng=None):
    rng = rng or np.random.default_rng(int(freq * 13))
    rel = 1.6
    n = int((dur + rel) * SR)
    y = np.zeros(n)
    for dc in (-9, -3, 4, 10):
        y += saw_additive(freq, n, dc, rng.uniform(0, 6), max_h=14, tilt=1.3)
    t = t_axis(n)
    y = lp(y, 1300, 2) * (1 + 0.1 * np.sin(2 * math.pi * 0.25 * t + rng.uniform(0, 6)))
    env = adsr(n, 1.1, 0.5, 0.85, rel, hold=dur)
    return y * env * vel * 0.1


def bell(freq, dur, vel=0.6, rng=None, decay=2.5):
    """Campana/celesta (parciales inarmónicos)."""
    n = int((dur + decay) * SR)
    t = t_axis(n)
    y = np.zeros(n)
    for r, a, d in ((1.0, 1.0, 1.0), (2.0, 0.45, 0.6), (3.01, 0.22, 0.35), (4.17, 0.12, 0.22), (5.43, 0.06, 0.15)):
        if freq * r < SR * 0.42:
            y += a * np.sin(2 * math.pi * freq * r * t) * np.exp(-t / (decay * d))
    atk = int(0.002 * SR)
    y[:atk] *= np.linspace(0, 1, atk)
    return y * vel * 0.3


def bass(freq, dur, vel=0.7, rng=None, pluck=True):
    rel = 0.12
    n = int((dur + rel) * SR)
    t = t_axis(n)
    y = np.sin(2 * math.pi * freq * t) + 0.3 * np.sin(4 * math.pi * freq * t) * np.exp(-t / 0.3) + 0.1 * np.sin(6 * math.pi * freq * t) * np.exp(-t / 0.15)
    env = adsr(n, 0.008, 0.4, 0.55 if pluck else 0.9, rel, hold=dur)
    return y * env * vel * 0.5


def frame_drum(vel=0.6, rng=None):
    rng = rng or np.random.default_rng(3)
    n = int(0.5 * SR)
    t = t_axis(n)
    f = 58 + 45 * np.exp(-t / 0.04)
    y = np.sin(2 * math.pi * np.cumsum(f) / SR) * np.exp(-t / 0.18)
    y += lp(rng.standard_normal(n), 900) * np.exp(-t / 0.03) * 0.3
    return y * vel * 0.6


def shaker(vel=0.3, rng=None):
    rng = rng or np.random.default_rng(5)
    n = int(0.09 * SR)
    t = t_axis(n)
    env = np.minimum(t / 0.012, 1) * np.exp(-t / 0.03)
    return hp(rng.standard_normal(n), 5000) * env * vel * 0.25


def kick(vel=0.7, rng=None):
    n = int(0.45 * SR)
    t = t_axis(n)
    f = 45 + 80 * np.exp(-t / 0.035)
    y = np.sin(2 * math.pi * np.cumsum(f) / SR) * np.exp(-t / 0.22)
    return y * vel * 0.75


def snare(vel=0.5, rng=None, brush=False):
    rng = rng or np.random.default_rng(9)
    n = int(0.3 * SR)
    t = t_axis(n)
    nz = bp(rng.standard_normal(n), 1200, 7000) * np.exp(-t / (0.09 if brush else 0.07))
    tone = np.sin(2 * math.pi * 185 * t) * np.exp(-t / 0.05) * (0.2 if brush else 0.5)
    if brush:
        nz *= np.minimum(t / 0.015, 1)
    return (nz * 0.5 + tone) * vel * 0.5


def hat(vel=0.3, rng=None):
    rng = rng or np.random.default_rng(11)
    n = int(0.06 * SR)
    t = t_axis(n)
    return hp(rng.standard_normal(n), 7000) * np.exp(-t / 0.018) * vel * 0.3


def timpani(freq, vel=0.6, rng=None):
    rng = rng or np.random.default_rng(13)
    n = int(1.6 * SR)
    t = t_axis(n)
    y = np.zeros(n)
    for r, a in ((1.0, 1.0), (1.5, 0.5), (1.98, 0.3), (2.44, 0.15)):
        y += a * np.sin(2 * math.pi * freq * r * t) * np.exp(-t / (0.7 / r))
    y += lp(rng.standard_normal(n), 400) * np.exp(-t / 0.02) * 0.5
    return y * vel * 0.4


INSTR = {
    "guitar": lambda f, d, v, r: karplus(f, d, v, t60=2.2, bright=0.55, rng=r),
    "harp": lambda f, d, v, r: karplus(f, d, v, t60=3.5, bright=0.75, rng=r, body=False),
    "guitar_bass": lambda f, d, v, r: karplus(f, d, v, t60=2.8, bright=0.3, rng=r),
    "flute": lambda f, d, v, r: flute(f, d, v, r),
    "strings": lambda f, d, v, r: strings(f, d, v, r),
    "cello": lambda f, d, v, r: strings(f, d, v, r, attack=0.25, release=0.6, bright=1600),
    "piano": lambda f, d, v, r: piano(f, d, v, r),
    "epiano": lambda f, d, v, r: epiano(f, d, v, r),
    "brass": lambda f, d, v, r: brass(f, d, v, r),
    "lead": lambda f, d, v, r: soft_lead(f, d, v, r),
    "pad": lambda f, d, v, r: synth_pad(f, d, v, r),
    "bell": lambda f, d, v, r: bell(f, d, v, r),
    "celesta": lambda f, d, v, r: bell(f, d, v, r, decay=1.2),
    "bass": lambda f, d, v, r: bass(f, d, v, r),
    "subbass": lambda f, d, v, r: bass(f, d, v, r, pluck=False),
}
DRUMS = {
    "frame": frame_drum, "shaker": shaker, "kick": kick, "hat": hat,
    "snare": lambda v, r: snare(v, r), "brush": lambda v, r: snare(v, r, brush=True),
}

# ---------------------------------------------------------------------------------------------
# Teoría: escalas, acordes, conducción de voces y melodías con motivos
# ---------------------------------------------------------------------------------------------

MODES = {
    "major": [0, 2, 4, 5, 7, 9, 11],
    "minor": [0, 2, 3, 5, 7, 8, 10],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
    "mixolydian": [0, 2, 4, 5, 7, 9, 10],
    "lydian": [0, 2, 4, 6, 7, 9, 11],
    "harmonic": [0, 2, 3, 5, 7, 8, 11],
    "penta": [0, 2, 4, 7, 9],
}
QUAL = {
    "": [0, 4, 7], "m": [0, 3, 7], "maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10], "7": [0, 4, 7, 10],
    "sus2": [0, 2, 7], "sus4": [0, 5, 7], "m9": [0, 3, 7, 10, 14], "maj9": [0, 4, 7, 11, 14],
    "add9": [0, 4, 7, 14], "6": [0, 4, 7, 9], "m6": [0, 3, 7, 9], "13": [0, 4, 10, 14, 21],
}


def chord_pcs(ch):
    root, q = ch
    return [(root + i) % 12 for i in QUAL[q]]


def voice(ch, prev, lo, hi, n_notes=4):
    """Voicing del acorde dentro de [lo, hi] lo más cercano al anterior (conducción de voces)."""
    root, q = ch
    ivs = QUAL[q]
    cands = []
    base_pcs = [(root + i) for i in ivs]
    for inv in range(len(base_pcs)):
        notes = sorted(base_pcs[inv:] + [p + 12 for p in base_pcs[:inv]])
        notes = notes[:n_notes]
        for octv in range(-2, 8):
            v = [p + 12 * octv for p in notes]
            if v[0] >= lo and v[-1] <= hi:
                cands.append(v)
    if not cands:
        return [lo + (root - lo) % 12 + i for i in ivs][:n_notes]
    if prev is None:
        mid = (lo + hi) / 2
        return min(cands, key=lambda v: abs(np.mean(v) - mid))
    return min(cands, key=lambda v: sum(abs(a - b) for a, b in zip(v, prev)) + abs(len(v) - len(prev)) * 3)


class Song:
    def __init__(self, name, key, mode, bpm, bpb, seed, swing=0.0):
        self.name = name
        self.key = key          # nota MIDI de la tónica (octava central)
        self.mode = mode
        self.bpm = bpm
        self.bpb = bpb          # pulsos por compás
        self.rng = np.random.default_rng(seed)
        self.swing = swing
        self.events = {}        # instrumento -> [(t_seg, midi, dur_seg, vel, pan)]
        self.drum_events = {}   # tambor -> [(t, vel, pan)]
        self.spb = 60.0 / bpm

    def beat_t(self, beat):
        # Swing en corcheas: las corcheas "débiles" se retrasan.
        b = math.floor(beat)
        frac = beat - b
        if self.swing > 0 and abs(frac - 0.5) < 1e-6:
            frac = 0.5 + self.swing
        return (b + frac) * self.spb

    def note(self, inst, beat, midi, dur_beats, vel, pan=0.0, human=0.008):
        t = self.beat_t(beat) + self.rng.uniform(-human, human)
        d = dur_beats * self.spb
        v = float(np.clip(vel * self.rng.uniform(0.9, 1.08), 0.05, 1.0))
        self.events.setdefault(inst, []).append((max(0.0, t), midi, d, v, pan))

    def drum(self, inst, beat, vel, pan=0.0, human=0.006):
        t = self.beat_t(beat) + self.rng.uniform(-human, human)
        v = float(np.clip(vel * self.rng.uniform(0.85, 1.1), 0.05, 1.0))
        self.drum_events.setdefault(inst, []).append((max(0.0, t), v, pan))

    # --- Melodía ---------------------------------------------------------------------------
    def scale_notes(self, lo, hi):
        pcs = [(self.key + i) % 12 for i in MODES[self.mode]]
        return [m for m in range(lo, hi + 1) if m % 12 in pcs]

    def rhythm_bank(self):
        if self.bpb == 3:
            return [[1, 1, 1], [2, 1], [1.5, 0.5, 1], [1, 0.5, 0.5, 1], [0.5, 0.5, 1, 1], [1, 2]]
        return [[1, 1, 1, 1], [1.5, 0.5, 1, 1], [2, 1, 1], [1, 0.5, 0.5, 2], [0.5, 0.5, 1, 2],
                [1, 1, 2], [1.5, 0.5, 2], [0.5, 0.5, 0.5, 0.5, 1, 1]]

    def cadence_rhythm(self):
        return [2, 1] if self.bpb == 3 else [2, 2]

    def make_phrase(self, chords, scale, start_idx, motif=None, end_on_tonic=False, sparse=0.0):
        """chords: lista de acordes, uno por compás. Devuelve [(beat_rel, idx_escala, dur)], idx_final."""
        rng = self.rng
        bank = self.rhythm_bank()
        out = []
        idx = start_idx
        nbar = len(chords)
        if motif is None:
            motif = {"rhythms": [bank[rng.integers(len(bank))] for _ in range(nbar)],
                     "steps": [int(rng.choice([-2, -1, -1, 1, 1, 2, 0, 3, -3])) for _ in range(32)]}
        si = 0
        mid = len(scale) // 2
        for b, ch in enumerate(chords):
            rh = list(motif["rhythms"][b % len(motif["rhythms"])])
            if b == nbar - 1:
                rh = self.cadence_rhythm()
            pos = 0.0
            pcs = chord_pcs(ch)
            for j, d in enumerate(rh):
                strong = abs(pos) < 1e-6 or (self.bpb == 4 and abs(pos - 2) < 1e-6)
                step = motif["steps"][si % len(motif["steps"])]
                si += 1
                cand = idx + step
                # Atracción suave al centro del registro.
                if cand > mid + 5:
                    cand -= 2
                if cand < mid - 5:
                    cand += 2
                cand = int(np.clip(cand, 0, len(scale) - 1))
                if strong or d >= 2:
                    # En tiempo fuerte: nota del acorde más cercana.
                    best = min(range(len(scale)), key=lambda k: (0 if scale[k] % 12 in pcs else 50) + abs(k - cand))
                    cand = best
                if b == nbar - 1 and j == len(rh) - 1 and end_on_tonic:
                    tonics = [k for k in range(len(scale)) if scale[k] % 12 == self.key % 12]
                    cand = min(tonics, key=lambda k: abs(k - cand))
                idx = cand
                rest = sparse > 0 and not strong and rng.random() < sparse
                if not rest:
                    out.append((b * self.bpb + pos, idx, d))
                pos += d
        return out, idx, motif

    def fit(self, midi, ch):
        """Ajusta una nota de la escala al acorde: si el acorde altera un grado (p. ej. la sensible
        del V en menor), la nota vecina de la escala se cambia por la del acorde (sin choques)."""
        pcs = chord_pcs(ch)
        scale = [(self.key + i) % 12 for i in MODES[self.mode]]
        if midi % 12 in pcs:
            return midi
        for d in (1, -1):
            if (midi + d) % 12 in pcs and (midi + d) % 12 not in scale:
                return midi + d
        return midi

    def melody(self, inst, section_chords, lo, hi, start_beat, pan=0.0, vel=0.6, repeat_motif=None,
               sparse=0.0, legato=0.95):
        """Frase de 2 × (n/2) compases: pregunta (termina abierta) y respuesta (termina en tónica)."""
        scale = self.scale_notes(lo, hi)
        half = len(section_chords) // 2
        start_idx = len(scale) // 2
        a, idx, motif = self.make_phrase(section_chords[:half], scale, start_idx, repeat_motif, False, sparse)
        # Respuesta: mismo motivo en el primer compás, luego libre.
        motif2 = {"rhythms": motif["rhythms"][:1] + [self.rhythm_bank()[self.rng.integers(len(self.rhythm_bank()))] for _ in range(half)],
                  "steps": motif["steps"][:4] + [int(self.rng.choice([-2, -1, 1, 1, 2, -1])) for _ in range(28)]}
        b, idx, _ = self.make_phrase(section_chords[half:], scale, start_idx, motif2, True, sparse)
        for (bt, i, d) in a:
            ch = section_chords[int(bt // self.bpb)]
            self.note(inst, start_beat + bt, self.fit(scale[i], ch), d * legato, vel * (1.08 if bt % self.bpb == 0 else 0.95), pan)
        off = half * self.bpb
        for (bt, i, d) in b:
            ch = section_chords[half + int(bt // self.bpb)]
            self.note(inst, start_beat + off + bt, self.fit(scale[i], ch), d * legato, vel * (1.08 if bt % self.bpb == 0 else 0.95), pan)
        return motif

    # --- Acompañamientos --------------------------------------------------------------------
    def comp(self, inst, style, chords, start_beat, lo, hi, vel=0.5, pan=0.0, bass_inst=None, bass_lo=36):
        prev = None
        for b, ch in enumerate(chords):
            v = voice(ch, prev, lo, hi, 4)
            prev = v
            bb = start_beat + b * self.bpb
            root = ch[0]
            bnote = bass_lo + (root - bass_lo) % 12
            if style == "fingerpick":
                pat = [0, 2, 1, 3, 0, 2, 1, 3] if self.bpb == 4 else [0, 1, 2, 3, 2, 1]
                notes = [bnote + 12 if bnote + 12 < v[0] else bnote] + v[1:]
                for k, p in enumerate(pat):
                    nt = notes[p % len(notes)]
                    self.note(inst, bb + k * 0.5, nt, 1.2 if p == 0 else 0.9, vel * (1.15 if k == 0 else 0.8), pan + (-0.15 if p == 0 else 0.1 * (p - 1.5)))
            elif style == "harp":
                seq = v + [x + 12 for x in v]
                steps = self.bpb * 2
                for k in range(steps):
                    self.note(inst, bb + k * 0.5, seq[k % len(seq)], 1.6, vel * (0.9 + 0.2 * (k == 0)), pan + 0.3 * math.sin(k))
            elif style == "strum":
                for k, (pos, sv) in enumerate(([0, 1.0], [1.5, 0.7], [2, 0.8], [3, 0.7]) if self.bpb == 4 else ([0, 1.0], [1, 0.7], [2, 0.7])):
                    for j, nt in enumerate(v):
                        self.note(inst, bb + pos + j * 0.018, nt, 0.9, vel * sv * 0.75, pan + 0.1 * (j - 1.5))
            elif style == "pad":
                for nt in v:
                    self.note(inst, bb, nt, self.bpb * 1.02, vel, pan + self.rng.uniform(-0.3, 0.3), human=0.0)
            elif style == "alberti":
                pat = [0, 2, 1, 2] * 2 if self.bpb == 4 else [0, 2, 1, 2, 1, 2]
                for k, p in enumerate(pat):
                    self.note(inst, bb + k * 0.5, v[p % len(v)], 0.6, vel * (1.1 if k == 0 else 0.8), pan)
            elif style == "block":
                self.note(inst, bb, bnote + 12, self.bpb * 0.9, vel * 1.05, pan - 0.2)
                hits = [1, 3] if self.bpb == 4 else [1, 2]
                for h in hits:
                    for nt in v[1:]:
                        self.note(inst, bb + h, nt, 0.8, vel * 0.7, pan + 0.2)
            elif style == "lofi":
                hits = [(0, 1.4, 1.0), (1.5, 0.9, 0.75), (3.0, 0.5, 0.6)]
                if self.rng.random() < 0.4:
                    hits = [(0, 2.4, 1.0), (2.5, 1.2, 0.7)]
                for (pos, d, sv) in hits:
                    for j, nt in enumerate(v):
                        self.note(inst, bb + pos + j * 0.012, nt, d, vel * sv, pan + 0.12 * (j - 1.5))
            elif style == "arp16":
                seq = v + [v[-2], v[-3]] if len(v) >= 3 else v
                for k in range(self.bpb * 2):
                    self.note(inst, bb + k * 0.5, seq[k % len(seq)] + 12, 0.45, vel * (1.0 if k % 2 == 0 else 0.7), 0.4 * math.sin(k * 0.9))
            if bass_inst:
                if style == "lofi":
                    self.note(bass_inst, bb, bnote, 1.3, vel * 1.2, 0)
                    self.note(bass_inst, bb + 1.5, bnote, 0.4, vel * 0.9, 0)
                    self.note(bass_inst, bb + 2.5, bnote + (7 if self.rng.random() < 0.5 else 12), 1.0, vel, 0)
                elif self.bpb == 4:
                    self.note(bass_inst, bb, bnote, 1.8, vel * 1.2, 0)
                    fifth = bnote + 7 if bnote + 7 <= bass_lo + 14 else bnote - 5
                    self.note(bass_inst, bb + 2, fifth, 1.8, vel, 0)
                else:
                    self.note(bass_inst, bb, bnote, 2.7, vel * 1.2, 0)

    def groove(self, kind, bars, start_beat, vel=0.5):
        for b in range(bars):
            bb = start_beat + b * self.bpb
            if kind == "colonial":
                self.drum("frame", bb, vel, -0.2)
                if self.bpb == 4:
                    self.drum("frame", bb + 2.5, vel * 0.55, -0.2)
                    self.drum("frame", bb + 3, vel * 0.7, -0.2)
                else:
                    self.drum("frame", bb + 2, vel * 0.5, -0.2)
                for k in range(self.bpb * 2):
                    self.drum("shaker", bb + k * 0.5, vel * (0.9 if k % 2 == 0 else 0.55), 0.35)
            elif kind == "march":
                self.drum("kick", bb, vel * 0.7, 0)
                self.drum("brush", bb + 1, vel * 0.6, 0.1)
                if self.bpb == 4:
                    self.drum("kick", bb + 2, vel * 0.5, 0)
                    self.drum("brush", bb + 3, vel * 0.6, 0.1)
                    self.drum("brush", bb + 3.5, vel * 0.3, 0.1)
            elif kind == "lofi":
                self.drum("kick", bb, vel, 0)
                self.drum("kick", bb + 2.5, vel * 0.75, 0)
                if self.rng.random() < 0.3:
                    self.drum("kick", bb + 1.75, vel * 0.5, 0)
                self.drum("snare", bb + 1, vel * 0.8, 0.05)
                self.drum("snare", bb + 3, vel * 0.85, 0.05)
                for k in range(8):
                    self.drum("hat", bb + k * 0.5, vel * (0.7 if k % 2 == 0 else 0.45), 0.25)
            elif kind == "soft":
                self.drum("kick", bb, vel * 0.8, 0)
                for k in range(self.bpb * 2):
                    self.drum("shaker", bb + k * 0.5, vel * (0.6 if k % 2 == 0 else 0.35), -0.3)

    # --- Render ------------------------------------------------------------------------------
    def render(self, length_beats, mix, sends, rev=(0.3, 2.0), lofi=False, extra=None):
        n = int(self.beat_t(length_beats) * SR)
        tail = int(4.0 * SR)
        dry = np.zeros((n + tail, 2))
        send = np.zeros((n + tail, 2))
        cache = {}
        for inst, evs in self.events.items():
            gain = mix.get(inst, 0.5)
            s = sends.get(inst, 0.3)
            fn = INSTR[inst]
            for (t, m, d, v, pan) in evs:
                key = (inst, m, round(d, 2), round(v, 1))
                if key not in cache:
                    seed = sum(map(ord, inst)) * 100003 + m * 1009 + int(d * 100) * 7 + int(v * 10)
                    cache[key] = fn(midi_hz(m), d, round(v, 1), np.random.default_rng(seed))
                x = pan2(cache[key] * gain, float(np.clip(pan, -0.9, 0.9)))
                st = int(t * SR)
                add_at(dry, x, st)
                add_at(send, x * s, st)
        for inst, evs in self.drum_events.items():
            gain = mix.get(inst, 0.5)
            s = sends.get(inst, 0.15)
            fn = DRUMS[inst]
            variants = [fn(0.8, np.random.default_rng(1000 + k)) for k in range(4)]
            for (t, v, pan) in evs:
                x = pan2(variants[self.rng.integers(4)] * v / 0.8 * gain, pan)
                st = int(t * SR)
                add_at(dry, x, st)
                add_at(send, x * s, st)
        if extra is not None:
            add_at(dry, extra[: n + tail], 0)
        wet, t60 = rev
        ir = reverb_ir(t60=t60)
        r = np.stack([signal.fftconvolve(send[:, c], ir[:, c])[: len(send)] for c in range(2)], axis=1)
        mixd = dry + r * wet * 2.0
        if lofi:
            mixd = lp(mixd, 5200, 2)
            # Leve "wow" de cinta y ruido de vinilo.
            mixd = mixd + vinyl(len(mixd), self.rng)[:, None] * 0.012
        mixd = hp(mixd, 35, 2)
        return loop_wrap(mixd, n)


def vinyl(n, rng):
    y = lp(rng.standard_normal(n), 3000) * 0.15
    clicks = np.zeros(n)
    idx = rng.integers(0, n, int(n / SR * 3))
    clicks[idx] = rng.uniform(-1, 1, len(idx))
    clicks = bp(clicks, 1500, 6000, 1) * 3
    return y + clicks


def progression(names, key):
    """names: ['I', 'vi', 'IV7', ...] relativo a la tónica mayor; minúsculas = menor."""
    deg = {"I": 0, "II": 2, "III": 4, "IV": 5, "V": 7, "VI": 9, "VII": 11,
           "bIII": 3, "bVI": 8, "bVII": 10, "bII": 1}
    out = []
    for nm in names:
        q = ""
        base = nm
        for suf in ("maj9", "maj7", "m9", "m7", "sus2", "sus4", "add9", "m6", "13", "7", "6"):
            if nm.endswith(suf):
                q = suf
                base = nm[: -len(suf)]
                break
        minor = base.lstrip("b").islower()
        root = deg[base.upper() if not base.startswith("b") else "b" + base[1:].upper()]
        if minor and q == "":
            q = "m"
        elif minor and q == "7":
            q = "m7"
        out.append(((key + root) % 12, q))
    return out


# ---------------------------------------------------------------------------------------------
# Piezas
# ---------------------------------------------------------------------------------------------


def arrange(song, sections, plan):
    """sections: {nombre: [acordes por compás]}; plan: [(nombre_sección, capas{...}), ...]."""
    beat = 0
    motifs = {}
    for sec, layers in plan:
        chords = sections[sec]
        for layer in layers:
            kind = layer[0]
            if kind == "comp":
                _, inst, style, lo, hi, vel, bass_inst = layer
                song.comp(inst, style, chords, beat, lo, hi, vel, 0.0, bass_inst)
            elif kind == "mel":
                _, inst, lo, hi, vel, pan, sparse = layer
                key = (sec, inst)
                m = song.melody(inst, chords, lo, hi, beat, pan, vel, motifs.get(sec), sparse)
                motifs.setdefault(sec, m)
            elif kind == "drums":
                _, style, vel = layer
                song.groove(style, len(chords), beat, vel)
            elif kind == "timp":
                _, vel = layer
                for b in range(0, len(chords), 2):
                    song.drum("frame", beat + b * song.bpb, vel, 0)
        beat += len(chords) * song.bpb
    return beat


def piece_colonial_1():
    s = Song("colonial_1", 67, "major", 96, 3, 101)          # Sol mayor, vals criollo
    A = progression(["I", "V", "vi", "IV", "I", "V", "IV", "V"], 7)
    B = progression(["vi", "IV", "I", "V", "vi", "IV", "ii", "V"], 7)
    intro = progression(["I", "IV"], 7)
    plan = [
        ("intro", [("comp", "guitar", "fingerpick", 55, 74, 0.55, "guitar_bass"), ("drums", "colonial", 0.3)]),
        ("A", [("comp", "guitar", "fingerpick", 55, 74, 0.5, "guitar_bass"), ("mel", "flute", 74, 93, 0.55, 0.15, 0.1), ("drums", "colonial", 0.4)]),
        ("B", [("comp", "guitar", "strum", 55, 72, 0.45, "guitar_bass"), ("comp", "strings", "pad", 55, 72, 0.25, None), ("mel", "flute", 74, 93, 0.55, 0.15, 0.15), ("drums", "colonial", 0.45)]),
        ("A", [("comp", "guitar", "fingerpick", 55, 74, 0.5, "guitar_bass"), ("mel", "harp", 67, 88, 0.5, -0.2, 0.2), ("drums", "colonial", 0.4)]),
        ("A", [("comp", "guitar", "fingerpick", 55, 74, 0.5, "guitar_bass"), ("mel", "flute", 74, 93, 0.55, 0.15, 0.1), ("comp", "strings", "pad", 55, 72, 0.2, None), ("drums", "colonial", 0.4)]),
        ("intro", [("comp", "guitar", "fingerpick", 55, 74, 0.45, "guitar_bass")]),
    ]
    L = arrange(s, {"A": A, "B": B, "intro": intro}, plan)
    return s.render(L, {"guitar": 0.9, "guitar_bass": 0.8, "flute": 0.8, "harp": 0.8, "strings": 0.7, "frame": 0.7, "shaker": 0.35},
                    {"flute": 0.45, "harp": 0.4, "strings": 0.5, "guitar": 0.25}, rev=(0.3, 2.0))


def piece_colonial_2():
    s = Song("colonial_2", 69, "dorian", 104, 4, 202)         # La dórico
    A = progression(["i", "IV", "i", "bVII", "i", "IV", "bIII", "bVII"], 9)
    B = progression(["bIII", "bVII", "IV", "i", "bIII", "bVII", "IV", "V"], 9)
    intro = progression(["i", "bVII"], 9)
    plan = [
        ("intro", [("comp", "guitar", "fingerpick", 55, 72, 0.5, "guitar_bass"), ("drums", "colonial", 0.35)]),
        ("A", [("comp", "guitar", "fingerpick", 55, 72, 0.5, "guitar_bass"), ("mel", "flute", 72, 91, 0.5, 0.2, 0.15), ("drums", "colonial", 0.45)]),
        ("A", [("comp", "guitar", "strum", 55, 72, 0.42, "guitar_bass"), ("mel", "flute", 72, 91, 0.5, 0.2, 0.1), ("drums", "colonial", 0.5)]),
        ("B", [("comp", "harp", "harp", 57, 76, 0.42, "guitar_bass"), ("mel", "guitar", 64, 84, 0.6, -0.25, 0.1), ("drums", "colonial", 0.4)]),
        ("A", [("comp", "guitar", "fingerpick", 55, 72, 0.5, "guitar_bass"), ("mel", "flute", 72, 91, 0.5, 0.2, 0.15), ("comp", "strings", "pad", 57, 72, 0.2, None), ("drums", "colonial", 0.45)]),
        ("intro", [("comp", "guitar", "fingerpick", 55, 72, 0.45, "guitar_bass")]),
    ]
    L = arrange(s, {"A": A, "B": B, "intro": intro}, plan)
    return s.render(L, {"guitar": 0.9, "guitar_bass": 0.8, "flute": 0.75, "harp": 0.75, "strings": 0.6, "frame": 0.8, "shaker": 0.35},
                    {"flute": 0.45, "harp": 0.45, "strings": 0.5, "guitar": 0.25}, rev=(0.3, 2.2))


def piece_colonial_3():
    s = Song("colonial_3", 62, "mixolydian", 78, 4, 303)      # Re mixolidio, atardecer
    A = progression(["I", "bVII", "IV", "I", "I", "bVII", "IV", "V"], 2)
    B = progression(["IV", "I", "vi", "bVII", "IV", "I", "V", "V"], 2)
    intro = progression(["I", "bVII"], 2)
    plan = [
        ("intro", [("comp", "harp", "harp", 57, 76, 0.45, None), ("comp", "strings", "pad", 50, 69, 0.25, None)]),
        ("A", [("comp", "harp", "harp", 57, 76, 0.4, "guitar_bass"), ("comp", "strings", "pad", 50, 69, 0.25, None), ("mel", "flute", 72, 90, 0.5, 0.1, 0.2)]),
        ("B", [("comp", "guitar", "fingerpick", 52, 71, 0.45, "guitar_bass"), ("comp", "strings", "pad", 50, 69, 0.3, None), ("mel", "flute", 72, 90, 0.5, 0.1, 0.15), ("drums", "colonial", 0.3)]),
        ("A", [("comp", "harp", "harp", 57, 76, 0.4, "guitar_bass"), ("mel", "guitar", 62, 81, 0.55, -0.2, 0.2), ("drums", "colonial", 0.25)]),
        ("intro", [("comp", "harp", "harp", 57, 76, 0.4, None), ("comp", "strings", "pad", 50, 69, 0.25, None)]),
    ]
    L = arrange(s, {"A": A, "B": B, "intro": intro}, plan)
    return s.render(L, {"guitar": 0.9, "guitar_bass": 0.75, "flute": 0.75, "harp": 0.75, "strings": 0.8, "frame": 0.6, "shaker": 0.3},
                    {"flute": 0.5, "harp": 0.5, "strings": 0.55, "guitar": 0.3}, rev=(0.35, 2.4))


def piece_industrial_1():
    s = Song("industrial_1", 60, "major", 100, 4, 404)        # Do mayor, vapor y progreso
    A = progression(["I", "vi", "IV", "V", "I", "vi", "ii", "V"], 0)
    B = progression(["IV", "V", "iii", "vi", "IV", "V", "I", "I"], 0)
    intro = progression(["I", "V"], 0)
    plan = [
        ("intro", [("comp", "piano", "alberti", 55, 72, 0.45, None)]),
        ("A", [("comp", "piano", "alberti", 55, 72, 0.4, "cello"), ("mel", "piano", 72, 88, 0.55, 0.1, 0.1), ("drums", "march", 0.35)]),
        ("B", [("comp", "strings", "pad", 55, 72, 0.3, "cello"), ("comp", "piano", "block", 52, 72, 0.35, None), ("mel", "brass", 60, 79, 0.55, -0.1, 0.1), ("drums", "march", 0.45)]),
        ("A", [("comp", "piano", "alberti", 55, 72, 0.4, "cello"), ("mel", "piano", 72, 88, 0.55, 0.1, 0.1), ("comp", "strings", "pad", 55, 72, 0.2, None), ("drums", "march", 0.35)]),
        ("intro", [("comp", "piano", "alberti", 55, 72, 0.4, None)]),
    ]
    L = arrange(s, {"A": A, "B": B, "intro": intro}, plan)
    return s.render(L, {"piano": 0.9, "cello": 0.55, "strings": 0.6, "brass": 0.8, "kick": 0.5, "brush": 0.5},
                    {"piano": 0.3, "strings": 0.5, "brass": 0.45, "cello": 0.35}, rev=(0.3, 2.0))


def piece_industrial_2():
    s = Song("industrial_2", 57, "minor", 80, 4, 505)         # La menor, talleres del río
    A = progression(["i", "bVI", "bIII", "bVII", "i", "iv", "bVI", "V"], 9)
    B = progression(["bVI", "bVII", "bIII", "bVI", "iv", "i", "V", "V"], 9)
    intro = progression(["i", "bVI"], 9)
    plan = [
        ("intro", [("comp", "piano", "harp", 52, 72, 0.4, None), ("comp", "cello", "pad", 45, 60, 0.3, None)]),
        ("A", [("comp", "piano", "harp", 52, 72, 0.38, "cello"), ("mel", "piano", 69, 86, 0.55, 0.1, 0.15)]),
        ("B", [("comp", "strings", "pad", 55, 72, 0.35, "cello"), ("mel", "brass", 57, 76, 0.5, -0.1, 0.15), ("comp", "piano", "harp", 52, 72, 0.3, None), ("drums", "soft", 0.3)]),
        ("A", [("comp", "piano", "harp", 52, 72, 0.38, "cello"), ("mel", "strings", 69, 84, 0.5, 0.1, 0.1)]),
        ("intro", [("comp", "piano", "harp", 52, 72, 0.35, None), ("comp", "cello", "pad", 45, 60, 0.3, None)]),
    ]
    L = arrange(s, {"A": A, "B": B, "intro": intro}, plan)
    return s.render(L, {"piano": 0.9, "cello": 0.6, "strings": 0.75, "brass": 0.75, "kick": 0.4, "shaker": 0.4},
                    {"piano": 0.35, "strings": 0.55, "brass": 0.5, "cello": 0.4}, rev=(0.35, 2.3))


def piece_industrial_3():
    s = Song("industrial_3", 65, "major", 92, 4, 606)         # Fa mayor, la gran estación
    A = progression(["I", "IV", "I", "V", "vi", "IV", "ii", "V"], 5)
    B = progression(["vi", "iii", "IV", "I", "ii", "V", "I", "V"], 5)
    intro = progression(["I", "IV"], 5)
    plan = [
        ("intro", [("comp", "brass", "pad", 53, 70, 0.35, None), ("timp", 0.35)]),
        ("A", [("comp", "piano", "block", 53, 72, 0.4, "cello"), ("mel", "brass", 65, 82, 0.55, 0.0, 0.1), ("drums", "march", 0.35)]),
        ("B", [("comp", "piano", "alberti", 55, 72, 0.38, "cello"), ("comp", "strings", "pad", 55, 72, 0.25, None), ("mel", "piano", 72, 88, 0.55, 0.15, 0.1)]),
        ("A", [("comp", "strings", "pad", 55, 72, 0.3, "cello"), ("comp", "piano", "block", 53, 72, 0.35, None), ("mel", "brass", 65, 82, 0.55, 0.0, 0.1), ("drums", "march", 0.4), ("timp", 0.3)]),
        ("intro", [("comp", "brass", "pad", 53, 70, 0.3, None)]),
    ]
    L = arrange(s, {"A": A, "B": B, "intro": intro}, plan)
    return s.render(L, {"piano": 0.85, "cello": 0.55, "strings": 0.6, "brass": 0.8, "kick": 0.5, "brush": 0.5, "frame": 0.8},
                    {"piano": 0.3, "strings": 0.5, "brass": 0.5, "cello": 0.35, "frame": 0.4}, rev=(0.32, 2.2))


def piece_modern_1():
    s = Song("modern_1", 65, "lydian", 78, 4, 707, swing=0.08)  # Fa lidio: Fmaj7–Em7–Dm7–Cmaj7 (lo-fi)
    A = [(5, "maj7"), (4, "m7"), (2, "m7"), (0, "maj7"), (5, "maj7"), (4, "m7"), (2, "m9"), (7, "7")]
    B = [(2, "m7"), (4, "m7"), (5, "maj7"), (7, "7"), (2, "m9"), (4, "m7"), (5, "maj7"), (7, "sus4")]
    intro = [(5, "maj7"), (4, "m7")]
    plan = [
        ("intro", [("comp", "epiano", "lofi", 53, 72, 0.45, None)]),
        ("A", [("comp", "epiano", "lofi", 53, 72, 0.42, "subbass"), ("drums", "lofi", 0.5), ("mel", "lead", 72, 86, 0.4, 0.15, 0.3)]),
        ("B", [("comp", "epiano", "lofi", 53, 72, 0.42, "subbass"), ("comp", "pad", "pad", 60, 76, 0.35, None), ("drums", "lofi", 0.55), ("mel", "epiano", 72, 86, 0.45, 0.2, 0.25)]),
        ("A", [("comp", "epiano", "lofi", 53, 72, 0.42, "subbass"), ("drums", "lofi", 0.5), ("mel", "lead", 72, 86, 0.4, 0.15, 0.3)]),
        ("intro", [("comp", "epiano", "lofi", 53, 72, 0.4, None)]),
    ]
    L = arrange(s, {"A": A, "B": B, "intro": intro}, plan)
    return s.render(L, {"epiano": 0.85, "subbass": 0.5, "pad": 0.7, "lead": 0.7, "kick": 0.7, "snare": 0.45, "hat": 0.4},
                    {"epiano": 0.3, "pad": 0.5, "lead": 0.4, "snare": 0.2}, rev=(0.25, 1.6), lofi=True)


def piece_modern_2():
    s = Song("modern_2", 62, "dorian", 84, 4, 808, swing=0.1)  # ii–V–I–vi en Do (Re dórico)
    A = [(2, "m9"), (7, "13"), (0, "maj9"), (9, "m7"), (2, "m9"), (7, "13"), (0, "maj9"), (0, "maj9")]
    B = [(5, "maj7"), (4, "m7"), (9, "m7"), (2, "m9"), (5, "maj7"), (4, "m7"), (2, "m7"), (7, "7")]
    intro = [(2, "m9"), (7, "13")]
    plan = [
        ("intro", [("comp", "epiano", "lofi", 52, 72, 0.45, None), ("drums", "lofi", 0.35)]),
        ("A", [("comp", "epiano", "lofi", 52, 72, 0.4, "subbass"), ("drums", "lofi", 0.5), ("mel", "celesta", 74, 88, 0.35, 0.25, 0.35)]),
        ("A", [("comp", "epiano", "lofi", 52, 72, 0.4, "subbass"), ("drums", "lofi", 0.5), ("mel", "lead", 72, 86, 0.4, -0.1, 0.25)]),
        ("B", [("comp", "pad", "pad", 57, 74, 0.35, "subbass"), ("comp", "epiano", "lofi", 52, 72, 0.3, None), ("drums", "lofi", 0.45), ("mel", "lead", 72, 86, 0.4, -0.1, 0.3)]),
        ("A", [("comp", "epiano", "lofi", 52, 72, 0.4, "subbass"), ("drums", "lofi", 0.5), ("mel", "celesta", 74, 88, 0.35, 0.25, 0.35)]),
    ]
    L = arrange(s, {"A": A, "B": B, "intro": intro}, plan)
    return s.render(L, {"epiano": 0.85, "subbass": 0.5, "pad": 0.7, "lead": 0.7, "celesta": 0.7, "kick": 0.7, "snare": 0.45, "hat": 0.4},
                    {"epiano": 0.3, "pad": 0.5, "lead": 0.4, "celesta": 0.5}, rev=(0.25, 1.6), lofi=True)


def piece_modern_3():
    s = Song("modern_3", 63, "major", 70, 4, 909)             # Mi♭ mayor, horizonte (ambient)
    A = progression(["Imaj7", "IVmaj7", "vi7", "IVmaj7", "Imaj7", "IVmaj7", "ii7", "V"], 3)
    B = progression(["vi7", "IVmaj7", "Imaj7", "V", "vi7", "IVmaj7", "ii7", "Vsus4"], 3)
    intro = progression(["Imaj7", "IVmaj7"], 3)
    plan = [
        ("intro", [("comp", "pad", "pad", 55, 72, 0.45, None)]),
        ("A", [("comp", "pad", "pad", 55, 72, 0.4, "subbass"), ("comp", "celesta", "arp16", 55, 70, 0.3, None)]),
        ("B", [("comp", "pad", "pad", 55, 72, 0.4, "subbass"), ("comp", "celesta", "arp16", 55, 70, 0.28, None), ("mel", "lead", 70, 84, 0.38, 0.1, 0.35), ("drums", "soft", 0.3)]),
        ("A", [("comp", "pad", "pad", 55, 72, 0.4, "subbass"), ("comp", "epiano", "arp16", 50, 66, 0.3, None), ("mel", "lead", 70, 84, 0.35, 0.1, 0.4)]),
        ("intro", [("comp", "pad", "pad", 55, 72, 0.4, None)]),
    ]
    L = arrange(s, {"A": A, "B": B, "intro": intro}, plan)
    return s.render(L, {"pad": 0.8, "subbass": 0.6, "celesta": 0.6, "epiano": 0.6, "lead": 0.65, "kick": 0.5, "shaker": 0.4},
                    {"pad": 0.6, "celesta": 0.6, "lead": 0.5, "epiano": 0.45}, rev=(0.4, 3.0), lofi=False)


def piece_menu():
    s = Song("menu", 62, "major", 72, 4, 1111)                # Re mayor, tema de Dinastía
    A = progression(["I", "V", "vi", "IV", "I", "iii", "IV", "V"], 2)
    B = progression(["IV", "V", "iii", "vi", "ii", "V", "I", "I"], 2)
    intro = progression(["I", "IV"], 2)
    plan = [
        ("intro", [("comp", "strings", "pad", 50, 69, 0.35, None), ("comp", "harp", "harp", 57, 76, 0.35, None)]),
        ("A", [("comp", "strings", "pad", 50, 69, 0.3, "cello"), ("comp", "harp", "harp", 57, 76, 0.35, None), ("mel", "flute", 74, 90, 0.5, 0.1, 0.1)]),
        ("B", [("comp", "strings", "pad", 50, 69, 0.35, "cello"), ("comp", "harp", "harp", 57, 76, 0.3, None), ("mel", "brass", 62, 79, 0.5, -0.1, 0.1), ("timp", 0.3)]),
        ("A", [("comp", "strings", "pad", 50, 69, 0.3, "cello"), ("comp", "piano", "harp", 57, 76, 0.3, None), ("mel", "flute", 74, 90, 0.5, 0.1, 0.1)]),
        ("intro", [("comp", "strings", "pad", 50, 69, 0.3, None), ("comp", "harp", "harp", 57, 76, 0.3, None)]),
    ]
    L = arrange(s, {"A": A, "B": B, "intro": intro}, plan)
    return s.render(L, {"strings": 0.75, "cello": 0.5, "harp": 0.75, "flute": 0.75, "brass": 0.75, "piano": 0.7, "frame": 0.7},
                    {"strings": 0.55, "harp": 0.5, "flute": 0.5, "brass": 0.5, "piano": 0.4, "frame": 0.4}, rev=(0.38, 2.6))


def piece_crisis():
    s = Song("crisis", 62, "harmonic", 64, 4, 1212)           # Re menor armónico, tiempos difíciles
    A = progression(["i", "iv", "bVI", "V", "i", "bVI", "iv", "V"], 2)
    B = progression(["bVI", "bIII", "iv", "V", "bVI", "iv", "V", "V"], 2)
    intro = progression(["i", "V"], 2)
    plan = [
        ("intro", [("comp", "cello", "pad", 45, 62, 0.35, None)]),
        ("A", [("comp", "cello", "pad", 45, 62, 0.3, None), ("mel", "piano", 62, 79, 0.45, 0.1, 0.35)]),
        ("B", [("comp", "strings", "pad", 50, 69, 0.3, "cello"), ("comp", "piano", "harp", 50, 69, 0.28, None), ("timp", 0.25)]),
        ("A", [("comp", "cello", "pad", 45, 62, 0.3, None), ("mel", "strings", 62, 79, 0.45, 0.1, 0.25)]),
        ("intro", [("comp", "cello", "pad", 45, 62, 0.3, None)]),
    ]
    L = arrange(s, {"A": A, "B": B, "intro": intro}, plan)
    return s.render(L, {"piano": 0.85, "cello": 0.7, "strings": 0.75, "frame": 0.7},
                    {"piano": 0.45, "strings": 0.55, "cello": 0.45, "frame": 0.5}, rev=(0.4, 2.8))


MUSIC = {
    "menu": (piece_menu, -20.0),
    "colonial_1": (piece_colonial_1, -20.0),
    "colonial_2": (piece_colonial_2, -20.0),
    "colonial_3": (piece_colonial_3, -21.0),
    "industrial_1": (piece_industrial_1, -20.0),
    "industrial_2": (piece_industrial_2, -21.0),
    "industrial_3": (piece_industrial_3, -20.0),
    "moderna_1": (piece_modern_1, -20.0),
    "moderna_2": (piece_modern_2, -20.0),
    "moderna_3": (piece_modern_3, -21.0),
    "crisis": (piece_crisis, -21.0),
}

# ---------------------------------------------------------------------------------------------
# Efectos de interfaz (mono)
# ---------------------------------------------------------------------------------------------


def tone_decay(freq, dur, decay, partials=((1, 1.0),), atk=0.002):
    n = int(dur * SR)
    t = t_axis(n)
    y = np.zeros(n)
    for r, a in partials:
        y += a * np.sin(2 * math.pi * freq * r * t)
    env = np.exp(-t / decay)
    k = max(1, int(atk * SR))
    env[:k] *= np.linspace(0, 1, k)
    return y * env


def marimba(freq, dur=0.6):
    return tone_decay(freq, dur, 0.16, ((1, 1.0), (3.93, 0.25), (9.2, 0.05)), 0.001)


def chime(freq, dur=1.2, decay=0.45):
    return tone_decay(freq, dur, decay, ((1, 1.0), (2.0, 0.3), (2.76, 0.15), (5.4, 0.05)))


def seq(parts, gap, total=None):
    n = int((total or (gap * len(parts) + max(len(p) for p in parts) / SR)) * SR)
    y = np.zeros(n)
    for i, p in enumerate(parts):
        add_at(y, p, int(i * gap * SR))
    return y


def whoosh(dur, f0, f1, rng):
    n = int(dur * SR)
    nz = rng.standard_normal(n)
    out = np.zeros(n)
    block = 256
    for s in range(0, n, block):
        fr = f0 + (f1 - f0) * s / n
        seg = nz[max(0, s - 512): s + block]
        out[s: s + block] = bp(seg, fr * 0.7, fr * 1.4, 1)[-min(block, n - s):]
    t = t_axis(n)
    env = np.sin(math.pi * np.clip(t / dur, 0, 1)) ** 2
    return out * env


def coin(rng, f=None):
    f = f or rng.uniform(2600, 3600)
    n = int(0.35 * SR)
    t = t_axis(n)
    y = np.zeros(n)
    for r, a, d in ((1.0, 1.0, 0.09), (1.47, 0.6, 0.07), (2.09, 0.4, 0.05), (2.56, 0.25, 0.04)):
        y += a * np.sin(2 * math.pi * f * r * t + rng.uniform(0, 6)) * np.exp(-t / d)
    y += hp(rng.standard_normal(n), 4000) * np.exp(-t / 0.004) * 0.4
    return y


def sfx_ui(name, rng):
    if name == "ui_click":
        y = tone_decay(1750, 0.07, 0.012, ((1, 1.0), (2.3, 0.3))) + lp(rng.standard_normal(int(0.07 * SR)), 3000) * np.exp(-t_axis(int(0.07 * SR)) / 0.004) * 0.3
        return y, -24
    if name == "ui_tab":
        return seq([tone_decay(1320, 0.12, 0.03, ((1, 1), (2, 0.2))), tone_decay(1760, 0.14, 0.04, ((1, 1), (2, 0.2)))], 0.045), -25
    if name == "ui_open":
        y = whoosh(0.22, 500, 2400, rng) * 0.35
        add_at(y, chime(1175, 0.5, 0.12) * 0.5, int(0.06 * SR))
        y = np.concatenate([y, np.zeros(int(0.35 * SR))])
        add_at(y, chime(1568, 0.45, 0.1) * 0.35, int(0.11 * SR))
        return y, -25
    if name == "ui_close":
        y = whoosh(0.2, 2000, 450, rng) * 0.35
        y = np.concatenate([y, np.zeros(int(0.35 * SR))])
        add_at(y, chime(1047, 0.45, 0.1) * 0.4, int(0.03 * SR))
        add_at(y, chime(784, 0.45, 0.1) * 0.35, int(0.08 * SR))
        return y, -26
    if name == "notif_info":
        return marimba(midi_hz(84), 0.7) + marimba(midi_hz(91), 0.7) * 0.25, -23
    if name == "notif_good":
        return seq([marimba(midi_hz(m), 0.6) for m in (79, 83, 86, 91)], 0.075), -22
    if name == "notif_bad":
        return seq([marimba(midi_hz(m), 0.8) * 0.9 for m in (76, 72)], 0.16), -22
    if name == "notif_important":
        y = seq([chime(midi_hz(m), 1.6, 0.6) for m in (79, 86, 91)], 0.11)
        return y, -22
    if name == "money_in":
        parts = [coin(rng) * rng.uniform(0.5, 1.0) for _ in range(6)]
        n = int(0.9 * SR)
        y = np.zeros(n)
        for i, p in enumerate(parts):
            add_at(y, p, int((i * 0.045 + rng.uniform(0, 0.02)) * SR))
        add_at(y, chime(midi_hz(96), 0.7, 0.2) * 0.4, int(0.28 * SR))
        return y, -23
    if name == "money_out":
        n = int(0.7 * SR)
        y = np.zeros(n)
        for i in range(3):
            add_at(y, coin(rng) * 0.7, int((i * 0.07 + rng.uniform(0, 0.015)) * SR))
        add_at(y, marimba(midi_hz(67), 0.5) * 0.5, int(0.2 * SR))
        return y, -24
    if name == "error":
        def buzz(f):
            n = int(0.12 * SR)
            t = t_axis(n)
            sq = np.sign(np.sin(2 * math.pi * f * t)) * 0.5 + np.sin(2 * math.pi * f * t)
            return lp(sq, 1400) * adsr(n, 0.005, 0.05, 0.7, 0.04)
        return seq([buzz(233), buzz(196)], 0.13), -24
    raise KeyError(name)


# ---------------------------------------------------------------------------------------------
# Efectos del mundo (mono, 3D) y ambientes (estéreo, en bucle)
# ---------------------------------------------------------------------------------------------


def hammer_hit(rng, metal=True):
    n = int(0.25 * SR)
    t = t_axis(n)
    thump = np.sin(2 * math.pi * rng.uniform(150, 230) * t) * np.exp(-t / 0.03)
    click = bp(rng.standard_normal(n), 1200, 4500) * np.exp(-t / 0.008)
    y = thump * 0.8 + click * 0.9
    if metal:
        f = rng.uniform(2400, 3400)
        y += (np.sin(2 * math.pi * f * t) + 0.5 * np.sin(2 * math.pi * f * 1.51 * t)) * np.exp(-t / 0.06) * 0.25
    return y


def saw_stroke(rng, dur=0.5):
    n = int(dur * SR)
    t = t_axis(n)
    nz = bp(rng.standard_normal(n), 1800, 6000)
    return nz * (np.sin(math.pi * t / dur) ** 2) * 0.35


def world_sfx(name, rng):
    """Efectos 3D (mono). Los *_loop se reproducen en bucle."""
    if name == "construction_loop":
        L = 7.0
        n = int(L * SR)
        y = np.zeros(n + SR)
        t = 0.2
        while t < L:
            burst = rng.integers(2, 6)
            for _ in range(burst):
                add_at(y, hammer_hit(rng, rng.random() < 0.8) * rng.uniform(0.6, 1.0), int(t * SR))
                t += rng.uniform(0.32, 0.45)
            t += rng.uniform(0.5, 1.4)
            if rng.random() < 0.35 and t < L - 1.5:
                for k in range(4):
                    add_at(y, saw_stroke(rng, 0.28), int(t * SR))
                    t += 0.3
                t += 0.4
        y = y + lp(brown(len(y), rng), 300) * 0.02
        return loop_wrap(y[:, None], n)[:, 0], -22
    if name == "cart_loop":
        L = 4.0
        n = int(L * SR)
        y = np.zeros(n + SR)
        # Cascos de caballo al paso (4 tiempos irregulares).
        pattern = [0.0, 0.26, 0.5, 0.74]
        for c in range(int(L / 1.0)):
            for p in pattern:
                m = int(0.08 * SR)
                tt = t_axis(m)
                hit = bp(rng.standard_normal(m), 600, 2200) * np.exp(-tt / 0.012) + np.sin(2 * math.pi * 350 * tt) * np.exp(-tt / 0.02) * 0.5
                add_at(y, hit * rng.uniform(0.6, 1.0), int((c * 1.0 + p + rng.uniform(-0.02, 0.02)) * SR))
        # Crujido de ruedas de madera.
        for k in range(6):
            m = int(rng.uniform(0.15, 0.35) * SR)
            tt = t_axis(m)
            f = rng.uniform(420, 700) * (1 + 0.1 * np.sin(2 * math.pi * rng.uniform(15, 30) * tt))
            sq = np.sin(2 * math.pi * np.cumsum(f) / SR) * np.sin(math.pi * tt / tt[-1]) * 0.18
            add_at(y, lp(sq, 2500), int(rng.uniform(0, L) * SR))
        y += lp(brown(len(y), rng), 180) * 0.1
        return loop_wrap(y[:, None], n)[:, 0], -22
    if name == "truck_loop":
        L = 3.0
        n = int(L * SR)
        t = t_axis(n)
        f0 = 30.0                        # ralentí del motor: bucle exacto (90 ciclos)
        y = np.zeros(n)
        for k in range(1, 12):
            y += np.sin(2 * math.pi * f0 * k * t + rng.uniform(0, 6)) / k ** 0.9
        fire = 1 + 0.5 * np.sin(2 * math.pi * f0 * 0.5 * t) ** 8
        y = lp(y * fire, 900)
        y += lp(brown(n, rng), 400) * 0.25
        return y, -22
    if name == "steam_loop":
        L = 4.0
        n = int(L * SR)
        y = np.zeros(n + SR)
        for k in range(int(L / 0.25)):
            m = int(0.2 * SR)
            tt = t_axis(m)
            ch = bp(rng.standard_normal(m), 250, 2500) * np.minimum(tt / 0.02, 1) * np.exp(-tt / 0.07)
            add_at(y, ch * (1.0 if k % 2 == 0 else 0.6), int(k * 0.25 * SR))
        y += hp(rng.standard_normal(len(y)), 3000) * 0.03
        return loop_wrap(y[:, None], n)[:, 0], -22
    if name == "train_whistle":
        n = int(2.6 * SR)
        t = t_axis(n)
        y = np.zeros(n)
        bend = 1 - 0.03 * np.exp(-t / 0.15)
        for f in (466.2, 554.4, 698.5):          # acorde de silbato de vapor
            ph = 2 * math.pi * np.cumsum(f * bend) / SR
            for k, a in ((1, 1.0), (2, 0.35), (3, 0.15)):
                y += a * np.sin(k * ph)
        y += bp(rng.standard_normal(n), 800, 4000) * 0.35
        # Dos pitazos: uno largo y uno corto.
        env = adsr(n, 0.1, 0.2, 0.85, 0.2, hold=1.1)
        env += np.concatenate([np.zeros(int(1.35 * SR)), adsr(n - int(1.35 * SR), 0.08, 0.2, 0.85, 0.45, hold=0.6)])
        return lp(y * env, 5000), -20
    if name == "train_loop":
        L = 4.0
        n = int(L * SR)
        y = np.zeros(n + SR)
        for k in range(int(L / 0.5)):     # traqueteo de rieles (ta-tan)
            for off in (0.0, 0.11):
                m = int(0.1 * SR)
                tt = t_axis(m)
                c = bp(rng.standard_normal(m), 300, 1800) * np.exp(-tt / 0.02) + np.sin(2 * math.pi * 120 * tt) * np.exp(-tt / 0.03)
                add_at(y, c * 0.8, int((k * 0.5 + off) * SR))
        y += lp(brown(len(y), rng), 250) * 0.25
        return loop_wrap(y[:, None], n)[:, 0], -22
    if name == "ship_horn":
        n = int(3.4 * SR)
        t = t_axis(n)
        y = np.zeros(n)
        for f in (98.0, 146.8):
            for k in range(1, 16):
                y += np.sin(2 * math.pi * f * k * t + k) * math.exp(-k / 4.0)
        y = lp(y, 1500)
        env = adsr(n, 0.25, 0.3, 0.9, 0.8, hold=2.4)
        return y * env, -20
    if name == "plane_pass":
        n = int(8.0 * SR)
        t = t_axis(n)
        nz = brown(n, rng) * 0.6 + pink(n, rng) * 0.4
        env = np.exp(-((t - 4.0) / 1.9) ** 2)
        y = lp(nz, 1200) * env
        f = 180 * (1 + 0.08 * np.tanh((4.0 - t) / 0.8))       # efecto Doppler aproximado
        y += np.sin(2 * math.pi * np.cumsum(f) / SR) * env * 0.12
        return y, -21
    if name == "bus_loop":
        L = 3.0
        n = int(L * SR)
        t = t_axis(n)
        y = np.zeros(n)
        for k in range(1, 10):
            y += np.sin(2 * math.pi * 40.0 * k * t + k) / k
        y = lp(y, 700) + lp(pink(n, rng), 1200) * 0.2
        return y, -23
    if name == "church_bell":
        n = int(6.5 * SR)
        t = t_axis(n)
        f = 311.1
        y = np.zeros(n)
        # Parciales de campana de iglesia: hum, fundamental, tercera menor, quinta, nominal...
        for r, a, d in ((0.5, 0.6, 4.0), (1.0, 1.0, 2.8), (1.2, 0.5, 2.0), (1.5, 0.35, 1.6), (2.0, 0.5, 1.4),
                        (2.5, 0.2, 0.9), (3.0, 0.15, 0.7), (4.2, 0.1, 0.4)):
            y += a * np.sin(2 * math.pi * f * r * t + r) * np.exp(-t / d) * (1 + 0.04 * np.sin(2 * math.pi * 1.3 * r * t))
        y += bp(rng.standard_normal(n), 800, 3000) * np.exp(-t / 0.01) * 0.3
        return y, -19
    if name.startswith("thunder"):
        n = int(6.0 * SR)
        t = t_axis(n)
        crack_at = rng.uniform(0.05, 0.4)
        y = brown(n, rng) * np.exp(-np.maximum(t - crack_at, 0) / rng.uniform(1.2, 2.0)) * np.minimum(t / 0.08, 1)
        y += lp(rng.standard_normal(n), 3000) * np.exp(-np.maximum(t - crack_at, 0) / 0.12) * (t > crack_at) * 0.5
        rumble = smooth_noise(n, 5, rng) ** 2
        y = lp(y * (0.5 + rumble), 900)
        return y, -18
    if name == "horn_car":
        n = int(0.45 * SR)
        t = t_axis(n)
        y = np.zeros(n)
        for f in (349.2, 440.0):
            y += np.sign(np.sin(2 * math.pi * f * t)) * 0.4 + np.sin(2 * math.pi * f * t)
        return lp(y, 2500) * adsr(n, 0.01, 0.05, 0.9, 0.06, hold=0.35), -23
    raise KeyError(name)


def chirp(rng, base, kind):
    """Canto de pájaro: barridos rápidos de frecuencia."""
    if kind == 0:     # trino
        m = int(rng.uniform(0.4, 0.9) * SR)
        tt = t_axis(m)
        rate = rng.uniform(14, 26)
        f = base * (1 + 0.18 * np.sin(2 * math.pi * rate * tt))
        env = (0.5 + 0.5 * np.sin(2 * math.pi * rate * tt)) ** 2 * np.sin(math.pi * tt / tt[-1])
    elif kind == 1:   # silbido descendente
        m = int(rng.uniform(0.15, 0.3) * SR)
        tt = t_axis(m)
        f = base * (1.35 - 0.5 * tt / tt[-1])
        env = np.sin(math.pi * tt / tt[-1]) ** 1.5
    else:             # dos notas
        m = int(0.32 * SR)
        tt = t_axis(m)
        f = np.where(tt < 0.15, base, base * 0.8)
        env = np.sin(math.pi * np.mod(tt, 0.16) / 0.16) ** 2
    ph = 2 * math.pi * np.cumsum(f) / SR
    return (np.sin(ph) + 0.1 * np.sin(2 * ph)) * env


def ambience(name, rng):
    """Bucles estéreo de ambiente (20 s)."""
    L = 20.0
    fade = int(1.5 * SR)
    n = int(L * SR)
    N = n + fade
    out = np.zeros((N, 2))
    if name == "amb_birds":
        bed = hp(pink(N, rng), 2000) * 0.03 * (0.5 + smooth_noise(N, 0.3, rng))
        out += pan2(bed, 0) * 0.7
        birds = [(rng.uniform(2800, 5200), rng.integers(0, 3), rng.uniform(-0.8, 0.8)) for _ in range(4)]
        t = 0.3
        while t < L:
            base, kind, pan = birds[rng.integers(len(birds))]
            for r in range(rng.integers(1, 4)):
                c = chirp(rng, base * rng.uniform(0.97, 1.03), kind) * rng.uniform(0.4, 1.0)
                add_at(out, pan2(c, pan), int(t * SR))
                t += len(c) / SR + rng.uniform(0.05, 0.2)
            t += rng.uniform(0.4, 1.8)
        return out, n, fade, -26
    if name == "amb_crickets":
        for c in range(5):
            f = rng.uniform(3800, 5200)
            rate = rng.uniform(0.45, 0.9)
            pan = rng.uniform(-0.85, 0.85)
            amp = rng.uniform(0.4, 1.0)
            tt = t_axis(N)
            car = np.sin(2 * math.pi * f * tt)
            pulses = (np.sin(2 * math.pi * 28 * tt) > 0.3).astype(float)
            pulses = lp(pulses, 400)
            gate_ph = np.mod(tt * rate + rng.uniform(0, 1), 1.0)
            gate = (gate_ph < 0.12).astype(float)
            gate = lp(gate, 60)
            out += pan2(car * pulses * gate * amp * 0.25, pan)
        out += pan2(lp(pink(N, rng), 500) * 0.02, 0)
        # Una rana lejana de vez en cuando.
        for k in range(4):
            m = int(0.18 * SR)
            tt = t_axis(m)
            fr = np.sin(2 * math.pi * 260 * tt) * (np.sin(2 * math.pi * 30 * tt) > 0) * np.sin(math.pi * tt / tt[-1])
            add_at(out, pan2(lp(fr, 1200) * 0.2, rng.uniform(-0.6, 0.6)), int(rng.uniform(0, L) * SR))
        return out, n, fade, -28
    if name == "amb_wind":
        for c in range(2):
            base = lp(pink(N, rng), 700) * (0.3 + 0.9 * smooth_noise(N, 0.15, rng) ** 1.5)
            whistle = bp(pink(N, rng), 500, 900, 2) * smooth_noise(N, 0.25, rng) ** 3 * 0.8
            out[:, c] = base + whistle
        return out, n, fade, -27
    if name == "amb_general":
        for c in range(2):
            out[:, c] = lp(pink(N, rng), 400) * (0.5 + 0.5 * smooth_noise(N, 0.1, rng)) + hp(pink(N, rng), 3000) * 0.03
        return out, n, fade, -30
    if name == "amb_river":
        for c in range(2):
            out[:, c] = bp(pink(N, rng), 300, 3500) * (0.8 + 0.2 * smooth_noise(N, 0.5, rng))
        # Burbujeo.
        for k in range(int(L * 25)):
            m = int(rng.uniform(0.01, 0.04) * SR)
            tt = t_axis(m)
            f0 = rng.uniform(500, 1600)
            b = np.sin(2 * math.pi * np.cumsum(f0 * (1 + tt * 30)) / SR) * np.exp(-tt / 0.01)
            add_at(out, pan2(b * rng.uniform(0.1, 0.35), rng.uniform(-0.8, 0.8)), int(rng.uniform(0, L) * SR))
        return out, n, fade, -26
    if name == "amb_sea":
        tt = t_axis(N)
        for c in range(2):
            swell = np.zeros(N)
            t0 = rng.uniform(0, 2)
            while t0 < L + 2:
                period = rng.uniform(5.5, 8.5)
                w = np.exp(-((tt - t0 - period * 0.35) / (period * 0.22)) ** 2)
                swell += w * rng.uniform(0.6, 1.0)
                t0 += period
            low = lp(brown(N, rng), 500) * (0.25 + swell)
            foam = bp(pink(N, rng), 1500, 7000) * swell ** 2 * 0.35
            out[:, c] = low + foam
        return out, n, fade, -26
    if name in ("amb_rain", "amb_storm"):
        heavy = name == "amb_storm"
        for c in range(2):
            out[:, c] = hp(pink(N, rng), 800) * (0.7 + 0.3 * smooth_noise(N, 0.3, rng)) + lp(pink(N, rng), 400) * (0.5 if heavy else 0.2)
        drops = int(L * (160 if heavy else 70))
        for k in range(drops):
            m = int(0.012 * SR)
            tt = t_axis(m)
            d = bp(rng.standard_normal(m), 2000, 8000, 1) * np.exp(-tt / 0.003)
            add_at(out, pan2(d * rng.uniform(0.3, 1.2), rng.uniform(-1, 1)), int(rng.uniform(0, L) * SR))
        if heavy:
            out += np.stack([lp(brown(N, rng), 120)] * 2, axis=1) * 0.4 * smooth_noise(N, 0.2, rng)[:, None]
        return out, n, fade, (-22 if heavy else -25)
    if name.startswith("amb_town_"):
        era = int(name[-1])
        # Murmullo de gente: ruido en banda de voz con modulación silábica.
        for c in range(2):
            v = np.zeros(N)
            for k in range(6):
                syl = smooth_noise(N, rng.uniform(3, 6), rng) ** 2
                v += bp(pink(N, rng), rng.uniform(250, 400), rng.uniform(900, 1600)) * syl
            out[:, c] = v * (0.35 if era < 3 else 0.2)
        if era == 1:
            for k in range(int(L / 2.5)):   # cascos y carretas de paso
                tpos = rng.uniform(0, L)
                for j in range(8):
                    m = int(0.06 * SR)
                    tt = t_axis(m)
                    hit = bp(rng.standard_normal(m), 700, 2500) * np.exp(-tt / 0.01)
                    add_at(out, pan2(hit * 0.35, rng.uniform(-0.7, 0.7)), int((tpos + j * 0.25 + (j % 2) * 0.03) * SR))
            for k in range(3):              # gallina / campanilla de tienda
                add_at(out, pan2(bell(midi_hz(96), 0.1, 0.3) * 0.25, rng.uniform(-0.7, 0.7)), int(rng.uniform(0, L) * SR))
        elif era == 2:
            period = 1.2                    # taller a lo lejos: golpes rítmicos y vapor
            for k in range(int(L / period)):
                add_at(out, pan2(lp(hammer_hit(rng), 1500) * 0.35, 0.4), int((k * period) * SR))
            for k in range(4):
                m = int(1.2 * SR)
                tt = t_axis(m)
                hiss = hp(rng.standard_normal(m), 2500) * np.sin(math.pi * tt / tt[-1]) * 0.12
                add_at(out, pan2(hiss, rng.uniform(-0.8, 0.8)), int(rng.uniform(0, L) * SR))
            out += np.stack([lp(brown(N, rng), 150)] * 2, axis=1) * 0.2
        else:
            tt = t_axis(N)                  # tráfico: coches que pasan (barridos filtrados)
            for k in range(int(L / 1.6)):
                t0 = rng.uniform(0, L)
                w = np.exp(-((tt - t0) / 0.9) ** 2)
                pan_curve = np.tanh((tt - t0) / 0.8) * (1 if rng.random() < 0.5 else -1)
                car = lp(pink(N, rng), rng.uniform(500, 900)) * w
                out[:, 0] += car * (1 - pan_curve) * 0.35
                out[:, 1] += car * (1 + pan_curve) * 0.35
            out += np.stack([lp(brown(N, rng), 120)] * 2, axis=1) * 0.35
            for k in range(2):
                h, _ = world_sfx("horn_car", rng)
                add_at(out, pan2(lp(h, 1800) * 0.12, rng.uniform(-0.8, 0.8)), int(rng.uniform(0, L) * SR))
        return out, n, fade, -26
    raise KeyError(name)


SFX_UI = ["ui_click", "ui_tab", "ui_open", "ui_close", "notif_info", "notif_good", "notif_bad",
          "notif_important", "money_in", "money_out", "error"]
SFX_WORLD = ["construction_loop", "cart_loop", "truck_loop", "steam_loop", "bus_loop", "train_loop",
             "train_whistle", "ship_horn", "plane_pass", "church_bell", "thunder_1", "thunder_2", "horn_car"]
AMBIENCES = ["amb_birds", "amb_crickets", "amb_wind", "amb_general", "amb_river", "amb_sea", "amb_rain",
             "amb_storm", "amb_town_1", "amb_town_2", "amb_town_3"]

# ---------------------------------------------------------------------------------------------
# Escritura
# ---------------------------------------------------------------------------------------------


def _encoder():
    try:
        import soundfile  # noqa: F401
        return "soundfile"
    except Exception:
        pass
    for exe in ("oggenc", "ffmpeg"):
        if shutil.which(exe):
            return exe
    return "wav"


def write_audio(path_noext, y, quality=0.4):
    """Escribe OGG Vorbis si hay codificador; si no, WAV de 16 bits. Devuelve la ruta."""
    y = np.clip(y, -1, 1).astype(np.float32)
    enc = _encoder()
    os.makedirs(os.path.dirname(path_noext), exist_ok=True)
    if enc == "soundfile":
        import soundfile as sf
        p = path_noext + ".ogg"
        # Por bloques: libsndfile 1.2 puede fallar si recibe un archivo largo de una sola vez.
        with sf.SoundFile(p, "w", SR, 1 if y.ndim == 1 else y.shape[1], format="OGG", subtype="VORBIS",
                          compression_level=1.0 - quality) as f:
            for i in range(0, len(y), 8192):
                f.write(y[i:i + 8192])
        return p
    wav = path_noext + ".wav"
    _write_wav(wav, y)
    if enc in ("oggenc", "ffmpeg"):
        p = path_noext + ".ogg"
        cmd = ["oggenc", "-Q", "-q", str(int(quality * 10)), "-o", p, wav] if enc == "oggenc" else \
            ["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", str(int(quality * 10)), p]
        subprocess.run(cmd, check=True)
        os.remove(wav)
        return p
    return wav


def _write_wav(path, y):
    ch = 1 if y.ndim == 1 else y.shape[1]
    data = (y * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def stats(name, y):
    peak = float(np.max(np.abs(y)))
    rms = float(np.sqrt(np.mean(y ** 2)))
    dc = float(np.abs(np.mean(y)))
    clip = float(np.mean(np.abs(y) > 0.99))
    return "%-20s %6.1fs  pico %.2f  RMS %5.1f dBFS  DC %.4f  recorte %.4f%%" % (
        name, len(y) / SR, peak, 20 * math.log10(rms + 1e-12), dc, clip * 100)


def build(job):
    kind, name, check = job
    rng = np.random.default_rng(sum(ord(c) * (i + 1) for i, c in enumerate(name)) * 7919)
    if kind == "music":
        fn, rms = MUSIC[name]
        y = finalize(fn(), rms_db=rms)
        path = os.path.join(OUT, "music", name)
        q = 0.35
    elif kind == "ui":
        y, rms = sfx_ui(name, rng)
        y = finalize(y, rms_db=rms, peak=0.8, fade_out=0.02)
        path = os.path.join(OUT, "sfx", name)
        q = 0.4
    elif kind == "world":
        y, rms = world_sfx(name, rng)
        loop = name.endswith("_loop")
        y = finalize(y, rms_db=rms, peak=0.85, fade_out=0.0 if loop else 0.05)
        path = os.path.join(OUT, "sfx", name)
        q = 0.35
    else:
        y, n, fade, rms = ambience(name, rng)
        y = loop_crossfade(hp(y, 30), n, fade)
        y = finalize(y, rms_db=rms, peak=0.8)
        path = os.path.join(OUT, "amb", name)
        q = 0.25
    msg = stats(name, y)
    if not check:
        p = write_audio(path, y, q)
        msg += "  -> %s (%d KB)" % (os.path.relpath(p, ROOT), os.path.getsize(p) // 1024)
    return msg


def main(argv):
    check = "--check" in argv
    only = None
    for i, a in enumerate(argv):
        if a == "--only" and i + 1 < len(argv):
            only = set(argv[i + 1].split(","))
    groups = [a for a in argv if a in ("music", "sfx", "amb")] or ["music", "sfx", "amb"]
    jobs = []
    if "music" in groups:
        jobs += [("music", n, check) for n in MUSIC]
    if "sfx" in groups:
        jobs += [("ui", n, check) for n in SFX_UI] + [("world", n, check) for n in SFX_WORLD]
    if "amb" in groups:
        jobs += [("amb", n, check) for n in AMBIENCES]
    if only:
        jobs = [j for j in jobs if j[1] in only]
    print("Codificador:", _encoder(), "·", len(jobs), "archivos")
    with ProcessPoolExecutor() as ex:
        for msg in ex.map(build, jobs):
            print(msg, flush=True)
    if not check:
        total = 0
        for d, _, files in os.walk(OUT):
            total += sum(os.path.getsize(os.path.join(d, f)) for f in files if f.endswith((".ogg", ".wav")))
        print("Total de audio: %.1f MB" % (total / 1e6))


if __name__ == "__main__":
    main(sys.argv[1:])
