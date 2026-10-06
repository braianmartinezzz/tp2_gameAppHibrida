"""Genera los efectos de sonido del juego (`assets/audio/sfx/*.wav`).

Todo se sintetiza con numpy (ondas cuadradas/triangulares + ruido filtrado),
sin samples de terceros: no hay licencias que atribuir y el estilo cierra con
el arte pixel-art de 8 bits.

Tres familias, con distinto "carácter" para que se distingan sin mirar:

  * UI (botones, diálogos): bips cortos de onda cuadrada, tipo consola vieja,
    con un "tac" de madera/metal (el menú es un refugio armado con tablones).
  * Eventos del juego (diamantes, power-ups, golpes, muerte, horda): más
    cuerpo y más graves; la muerte y la horda usan un gruñido (diente de
    sierra con vibrato) por el tema zombi.
  * Movimiento del corredor (pasos, cambio de carril, salto, aterrizaje,
    agachado): ruido y senos suaves, sin bordes duros y normalizados más bajo.
    En el juego además suenan a un volumen menor (ver `Sfx` en
    lib/audio/game_sfx.dart).

Correr (desde endless_runner/):
    pip install numpy scipy
    python3 tools/build_sfx.py
"""
import wave
from pathlib import Path

import numpy as np
from scipy import signal

SR = 22050
OUT = Path('assets/audio/sfx')
RNG = np.random.default_rng(7)  # semilla fija: los .wav salen siempre iguales


# --- Utilidades ---------------------------------------------------------------

def t_of(dur):
    return np.arange(int(SR * dur)) / SR


def square(freq, duty=0.5):
    """Onda cuadrada (o pulso) a partir de una frecuencia (escalar o array)."""
    phase = np.cumsum(np.broadcast_to(freq, np.shape(freq)) / SR)
    return np.where((phase % 1.0) < duty, 1.0, -1.0)


def tri(freq):
    phase = np.cumsum(freq / SR)
    return 2 * np.abs(2 * (phase % 1.0) - 1) - 1


def saw(freq):
    phase = np.cumsum(freq / SR)
    return 2 * (phase % 1.0) - 1


def sine(freq):
    return np.sin(2 * np.pi * np.cumsum(freq / SR))


def noise(n):
    return RNG.uniform(-1, 1, n)


def decay(n, rate):
    """Caída exponencial: rate alto = más seca."""
    return np.exp(-rate * np.arange(n) / n)


def attack_decay(n, attack=0.02, rate=5.0):
    env = decay(n, rate)
    a = max(1, int(n * attack))
    env[:a] *= np.linspace(0, 1, a)
    return env


def hann(n):
    return np.hanning(n)


def lowpass(x, cutoff, order=2):
    b, a = signal.butter(order, cutoff / (SR / 2), 'low')
    return signal.lfilter(b, a, x)


def highpass(x, cutoff, order=2):
    b, a = signal.butter(order, cutoff / (SR / 2), 'high')
    return signal.lfilter(b, a, x)


def bandpass_sweep(x, f0, f1, q=2.5, block=256):
    """Pasabanda cuya frecuencia central barre de f0 a f1 (efecto 'whoosh')."""
    out = np.zeros_like(x)
    n = len(x)
    zi = None
    for start in range(0, n, block):
        frac = start / max(1, n - 1)
        f = f0 * (f1 / f0) ** frac
        lo = max(40.0, f / (1 + 1 / q)) / (SR / 2)
        hi = min(SR / 2 - 100, f * (1 + 1 / q)) / (SR / 2)
        b, a = signal.butter(2, [lo, hi], 'band')
        if zi is None or len(zi) != max(len(a), len(b)) - 1:
            zi = signal.lfilter_zi(b, a) * 0
        seg, zi = signal.lfilter(b, a, x[start:start + block], zi=zi)
        out[start:start + block] = seg
    return out


def crush(x, bits=6):
    """Cuantiza la amplitud: el 'grano' de 8 bits."""
    levels = 2 ** (bits - 1)
    return np.round(x * levels) / levels


def seq(notes, step, wave_fn, rate=4.0, gap=0.0):
    """Arpegio: lista de frecuencias, cada una de `step` segundos."""
    parts = []
    for f in notes:
        n = int(SR * step)
        t = np.arange(n) / SR
        w = wave_fn(np.full(n, f, dtype=float))
        parts.append(w * attack_decay(n, 0.04, rate))
        if gap:
            parts.append(np.zeros(int(SR * gap)))
    return np.concatenate(parts)


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = np.zeros(n)
    for t in tracks:
        out[:len(t)] += t
    return out


def pad(x, dur):
    n = int(SR * dur)
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def save(name, x, peak=0.9):
    x = np.asarray(x, dtype=float)
    m = np.max(np.abs(x)) or 1.0
    x = x / m * peak
    fade = int(SR * 0.006)  # 6 ms de salida: sin clicks al cortar
    x[-fade:] *= np.linspace(1, 0, fade)
    x[:8] *= np.linspace(0, 1, 8)
    data = (x * 32767).astype('<i2')
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f'{name}.wav'), 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(data.tobytes())
    print(f'{name:14s} {len(x) / SR * 1000:6.0f} ms  {data.nbytes / 1024:5.1f} KB')


# --- UI: botones y diálogos ---------------------------------------------------

def ui_click():
    n = int(SR * 0.075)
    f = np.where(np.arange(n) < n * 0.4, 660.0, 880.0)
    blip = square(f, 0.25) * attack_decay(n, 0.01, 6)
    tack = sine(np.linspace(220, 140, n)) * decay(n, 14)  # el "tac" de madera
    return crush(0.6 * blip + 0.8 * tack, 6)


def ui_back():
    n = int(SR * 0.1)
    f = np.where(np.arange(n) < n * 0.45, 523.0, 349.0)
    blip = square(f, 0.5) * attack_decay(n, 0.01, 5)
    tack = sine(np.linspace(170, 110, n)) * decay(n, 12)
    return crush(0.55 * blip + 0.8 * tack, 6)


def ui_play():
    """JUGAR: arranque de motor + arpegio ascendente + ráfaga de ruido."""
    dur = 0.55
    n = int(SR * dur)
    t = t_of(dur)
    engine = saw(np.linspace(55, 140, n)) * (1 + 0.5 * np.sin(2 * np.pi * 22 * t))
    engine = lowpass(engine, 700) * np.linspace(0.2, 0.9, n) * decay(n, 2.2)
    arp = seq([220, 277, 330, 440, 554], 0.085, lambda f: square(f, 0.25), rate=3.0)
    burst = highpass(noise(n), 2500) * attack_decay(n, 0.5, 8) * 0.2
    return crush(mix(engine * 0.9, pad(arp, dur) * 0.7, burst), 6)


def ui_toggle():
    n = int(SR * 0.05)
    tick = highpass(noise(n), 3000) * decay(n, 12)
    blip = square(np.full(n, 1100.0), 0.5) * decay(n, 9)
    return crush(0.6 * tick + 0.5 * blip, 6)


def ui_open():
    dur = 0.18
    n = int(SR * dur)
    sweep = bandpass_sweep(noise(n), 500, 2400, q=2.0) * hann(n) * 2.2
    blip = square(np.linspace(392, 587, n), 0.25) * attack_decay(n, 0.05, 6) * 0.35
    return crush(sweep + blip, 6)


def ui_close():
    dur = 0.14
    n = int(SR * dur)
    sweep = bandpass_sweep(noise(n), 2000, 450, q=2.0) * hann(n) * 2.2
    blip = square(np.linspace(494, 330, n), 0.25) * attack_decay(n, 0.05, 6) * 0.3
    return crush(sweep + blip, 6)


def ui_pause():
    return crush(seq([660, 440], 0.07, lambda f: square(f, 0.5), rate=4.0), 6)


def ui_resume():
    return crush(seq([440, 660, 880], 0.055, lambda f: square(f, 0.5), rate=4.0), 6)


def ui_error():
    n = int(SR * 0.2)
    buzz = square(np.where(np.arange(n) < n / 2, 150.0, 120.0), 0.5)
    buzz = lowpass(buzz, 900) * attack_decay(n, 0.02, 3.5)
    return crush(buzz, 5)


def ui_buy():
    """Compra/mejora: 'cha-ching' de caja registradora + ping agudo."""
    n = int(SR * 0.35)
    tick = highpass(noise(int(SR * 0.03)), 3500) * decay(int(SR * 0.03), 8)
    ping = np.concatenate([
        np.zeros(int(SR * 0.04)),
        seq([1568, 2093], 0.12, lambda f: square(f, 0.5), rate=5.0),
    ])
    shimmer = sine(np.full(n, 3136.0)) * decay(n, 7) * 0.25
    return crush(mix(tick * 0.9, pad(ping, 0.35) * 0.6, shimmer), 6)


def ui_reward():
    """Reclamar recompensa: cascada de diamantes."""
    notes = [784, 988, 1175, 1319, 1568, 1976, 2349]
    cascade = seq(notes, 0.055, lambda f: square(f, 0.5), rate=3.0)
    n = len(cascade)
    sparkle = highpass(noise(n), 5000) * attack_decay(n, 0.1, 3) * 0.12
    return crush(cascade * 0.8 + sparkle, 6)


def ui_success():
    return crush(seq([523, 659, 784, 1047], 0.06, lambda f: tri(f), rate=3.5), 6)


# --- Eventos del juego --------------------------------------------------------

def game_coin():
    """Diamante: dos notas agudas, brillo cristalino."""
    notes = seq([988, 1319], 0.055, lambda f: square(f, 0.5), rate=4.0)
    n = len(notes)
    glass = sine(np.full(n, 2637.0)) * attack_decay(n, 0.02, 6) * 0.35
    return crush(notes * 0.7 + glass, 6)


def game_coin_big():
    notes = seq([1319, 1661, 1976, 2637], 0.05, lambda f: square(f, 0.5), rate=3.5)
    n = len(notes)
    glass = sine(np.full(n, 3951.0)) * attack_decay(n, 0.05, 4) * 0.3
    return crush(notes * 0.7 + glass, 6)


def game_powerup():
    notes = [523, 659, 784, 1047, 1319]
    arp = seq(notes, 0.06, lambda f: square(f, 0.25), rate=2.5)
    n = len(arp)
    t = np.arange(n) / SR
    vib = sine(np.full(n, 8.0)) * 0.0  # sin vibrato: queda más limpio
    under = tri(np.linspace(262, 523, n)) * decay(n, 3) * 0.35
    return crush(arp * 0.7 + under + vib, 6)


def game_shield():
    """El escudo absorbe el golpe: 'clang' metálico + golpe grave."""
    dur = 0.4
    n = int(SR * dur)
    clang = sum(
        a * sine(np.full(n, f)) * decay(n, r)
        for f, a, r in [(523, 1.0, 7), (1172, 0.7, 9), (1810, 0.5, 11),
                        (2410, 0.35, 13), (3300, 0.2, 15)]
    )
    hit = highpass(noise(n), 1500) * decay(n, 40) * 0.8
    thump = sine(np.linspace(180, 70, n)) * decay(n, 14) * 0.9
    return crush(clang * 0.5 + hit + thump, 6)


def game_hit():
    """Pierde una vida: golpe seco con crujido."""
    dur = 0.3
    n = int(SR * dur)
    body = lowpass(noise(n), 1400) * decay(n, 11)
    thud = sine(np.linspace(150, 45, n)) * decay(n, 8)
    crunch = square(np.linspace(220, 80, n), 0.5) * decay(n, 14) * 0.5
    return crush(body * 0.9 + thud * 1.0 + crunch, 5)


def game_death():
    """Muerte: gruñido zombi que se apaga + golpe final."""
    dur = 1.1
    n = int(SR * dur)
    t = t_of(dur)
    f = np.linspace(150, 48, n) * (1 + 0.06 * np.sin(2 * np.pi * 7 * t))
    voice = saw(f)
    # Formantes de una "o/a" ronca: dos pasabandas mezclados.
    f1 = signal.lfilter(*signal.butter(2, [350 / (SR / 2), 700 / (SR / 2)], 'band'), voice)
    f2 = signal.lfilter(*signal.butter(2, [900 / (SR / 2), 1400 / (SR / 2)], 'band'), voice)
    growl = (f1 * 1.4 + f2 * 0.8) * (0.7 + 0.3 * np.sin(2 * np.pi * 19 * t))
    breath = lowpass(noise(n), 1800) * 0.25
    amp = np.minimum(1, t / 0.05) * np.exp(-1.6 * t)
    final = np.zeros(n)
    k = int(SR * 0.62)
    m = n - k
    final[k:] = sine(np.linspace(110, 38, m)) * decay(m, 7) * 1.1
    return crush((growl + breath) * amp * 1.2 + final, 5)


def game_revive():
    """Revivir: latido (lub-dub) y campanilla ascendente."""
    def beat(freq, dur):
        n = int(SR * dur)
        return sine(np.linspace(freq, freq * 0.55, n)) * decay(n, 8)
    lub = beat(90, 0.13)
    dub = beat(75, 0.13)
    heart = np.zeros(int(SR * 0.5))
    heart[:len(lub)] += lub
    heart[int(SR * 0.17):int(SR * 0.17) + len(dub)] += dub * 0.8
    chime = seq([523, 659, 784, 1047], 0.09, lambda f: tri(f), rate=3.0)
    out = np.concatenate([heart, chime * 0.8])
    return crush(out, 6)


def game_horde():
    """La horda acelera: gruñido grave pulsante."""
    dur = 0.55
    n = int(SR * dur)
    t = t_of(dur)
    f = 85 + 18 * np.sin(2 * np.pi * 5 * t)
    voice = lowpass(saw(f), 600)
    pulse = 0.55 + 0.45 * np.sin(2 * np.pi * 9 * t - np.pi / 2)
    rasp = highpass(noise(n), 900) * 0.15
    amp = hann(n) ** 0.6
    return crush((voice * 1.2 + rasp) * pulse * amp, 5)


# --- Movimiento del corredor (suave) -------------------------------------------

def move_step(variant):
    """Paso sobre asfalto con arenilla: golpecito grave + 'crunch' mínimo."""
    n = int(SR * 0.085)
    f0 = 95 if variant == 0 else 80
    cut = 650 if variant == 0 else 520
    thud = sine(np.linspace(f0, f0 * 0.6, n)) * decay(n, 16)
    body = lowpass(noise(n), cut) * decay(n, 20)
    grit = highpass(noise(n), 2200) * decay(n, 30) * 0.12
    x = 0.8 * thud + 0.9 * body + grit
    return lowpass(x, 3500)


def move_lane():
    """Cambio de carril: 'fshh' de tela, barrido suave de ruido."""
    dur = 0.16
    n = int(SR * dur)
    x = bandpass_sweep(noise(n), 450, 1700, q=1.6) * hann(n)
    return lowpass(x, 3000)


def move_jump():
    """Salto: impulso con un 'hop' ascendente muy suave + exhalación."""
    dur = 0.16
    n = int(SR * dur)
    hop = sine(np.linspace(210, 470, n)) * attack_decay(n, 0.08, 5)
    puff = bandpass_sweep(noise(n), 500, 1500, q=1.4) * hann(n) * 1.2
    push = sine(np.linspace(90, 70, n)) * decay(n, 18) * 0.7
    return lowpass(hop * 0.7 + puff * 0.8 + push, 3000)


def move_land():
    """Aterrizaje: golpe grave amortiguado, algo más lleno que un paso."""
    n = int(SR * 0.11)
    thud = sine(np.linspace(105, 52, n)) * decay(n, 12)
    body = lowpass(noise(n), 500) * decay(n, 16)
    grit = highpass(noise(n), 2000) * decay(n, 28) * 0.1
    return lowpass(thud * 1.0 + body * 0.8 + grit, 3000)


def move_roll():
    """Agacharse/deslizarse: raspado de tela y gravilla que se apaga."""
    dur = 0.3
    n = int(SR * dur)
    t = t_of(dur)
    scrape = bandpass_sweep(noise(n), 1700, 380, q=1.3)
    flutter = 0.65 + 0.35 * np.sin(2 * np.pi * 32 * t)
    env = np.minimum(1, t / 0.03) * np.exp(-3.2 * t)
    thump = sine(np.full(n, 85.0)) * decay(n, 25) * 0.5
    return lowpass(scrape * flutter * env * 1.6 + thump, 3200)


# --- Salida ---------------------------------------------------------------------

UI_PEAK = 0.85
GAME_PEAK = 0.9
MOVE_PEAK = 0.55  # los movimientos nacen más bajos que el resto

CUES = [
    ('ui_click', ui_click, UI_PEAK),
    ('ui_back', ui_back, UI_PEAK),
    ('ui_play', ui_play, UI_PEAK),
    ('ui_toggle', ui_toggle, UI_PEAK),
    ('ui_open', ui_open, UI_PEAK),
    ('ui_close', ui_close, UI_PEAK),
    ('ui_pause', ui_pause, UI_PEAK),
    ('ui_resume', ui_resume, UI_PEAK),
    ('ui_error', ui_error, UI_PEAK),
    ('ui_buy', ui_buy, UI_PEAK),
    ('ui_reward', ui_reward, UI_PEAK),
    ('ui_success', ui_success, UI_PEAK),
    ('game_coin', game_coin, GAME_PEAK),
    ('game_coin_big', game_coin_big, GAME_PEAK),
    ('game_powerup', game_powerup, GAME_PEAK),
    ('game_shield', game_shield, GAME_PEAK),
    ('game_hit', game_hit, GAME_PEAK),
    ('game_death', game_death, GAME_PEAK),
    ('game_revive', game_revive, GAME_PEAK),
    ('game_horde', game_horde, GAME_PEAK),
    ('move_step_a', lambda: move_step(0), MOVE_PEAK),
    ('move_step_b', lambda: move_step(1), MOVE_PEAK),
    ('move_lane', move_lane, MOVE_PEAK),
    ('move_jump', move_jump, MOVE_PEAK),
    ('move_land', move_land, MOVE_PEAK),
    ('move_roll', move_roll, MOVE_PEAK),
]

if __name__ == '__main__':
    for name, fn, peak in CUES:
        save(name, fn(), peak)
