#!/usr/bin/env python3
"""Synthesizes every sound in the game: small 8-bit chiptune effects and two
music loops. Run it from the repo root, then restart the app:

    python3 tools/gen_sounds.py

Output goes to assets/sounds/. Never hand-edit the WAVs; change this script.
Deterministic: the same script always writes the same bytes.
"""
import math
import os
import random
import wave

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sounds')

# Note names to frequencies, equal temperament from A4 = 440.
_NAMES = {'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5, 'F#': 6, 'G': 7,
          'G#': 8, 'A': 9, 'A#': 10, 'B': 11}


def note(name):
    """'C5' -> frequency in Hz."""
    letter, octave = name[:-1], int(name[-1])
    semis = _NAMES[letter] - 9 + (octave - 4) * 12
    return 440.0 * 2 ** (semis / 12)


# ---------------------------------------------------------------- voices

def _wave(kind, phase, duty=0.5):
    p = phase % 1.0
    if kind == 'square':
        return 1.0 if p < duty else -1.0
    if kind == 'tri':
        return 4 * abs(p - 0.5) - 1
    if kind == 'saw':
        return 2 * p - 1
    raise ValueError(kind)


def tone(freq, dur, kind='square', vol=1.0, duty=0.5, decay=4.0, attack=0.004,
         slide=0.0, vibrato=0.0):
    """One note: [freq] Hz for [dur] s, with a fast attack and an exponential
    decay. [slide] is a pitch change in Hz per second."""
    n = int(dur * SR)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = freq + slide * t
        if vibrato:
            f *= 1 + 0.02 * math.sin(2 * math.pi * 6 * t) * vibrato
        phase += max(f, 1.0) / SR
        env = math.exp(-decay * t / dur) if dur > 0 else 0
        if t < attack:
            env *= t / attack
        # A short fade to nothing, so notes never click at the end.
        tail = dur - t
        if tail < 0.004:
            env *= max(tail, 0) / 0.004
        out.append(_wave(kind, phase, duty) * vol * env)
    return out


def noise(dur, vol=1.0, decay=6.0, smooth=0.0, seed=1):
    """White noise, optionally smoothed (lower and softer when [smooth] is
    near 1), with a decay."""
    rng = random.Random(seed)
    n = int(dur * SR)
    out = []
    prev = 0.0
    for i in range(n):
        t = i / SR
        x = rng.uniform(-1, 1)
        prev = prev * smooth + x * (1 - smooth)
        env = math.exp(-decay * t / dur)
        out.append(prev * vol * env)
    return out


def silence(dur):
    return [0.0] * int(dur * SR)


def seq(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


def at(track, delay):
    """[track] starting [delay] seconds late."""
    return silence(delay) + track


def write(name, samples, peak=0.8):
    """Normalises to [peak] and writes 8-bit mono."""
    top = max(abs(v) for v in samples) or 1.0
    scale = peak / top if top > peak else 1.0
    data = bytearray()
    for v in samples:
        b = int(round(128 + v * scale * 127))
        data.append(max(0, min(255, b)))
    path = os.path.join(OUT, name + '.wav')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(SR)
        w.writeframes(bytes(data))
    return len(samples) / SR


# --------------------------------------------------------------- effects

def build_effects():
    fx = {}
    fx['tap'] = tone(1400, 0.03, 'square', 0.5, duty=0.25, decay=5)
    fx['tick'] = tone(900, 0.02, 'square', 0.4, duty=0.25, decay=5)
    fx['no'] = seq(tone(220, 0.07, 'square', 0.6, decay=2),
                   tone(150, 0.11, 'square', 0.6, decay=3))
    fx['place'] = mix(tone(420, 0.09, 'tri', 0.9, decay=5, slide=-1200),
                      noise(0.03, 0.4, decay=6))
    fx['thud'] = mix(tone(110, 0.16, 'tri', 1.0, decay=6, slide=-250),
                     noise(0.07, 0.5, decay=8, smooth=0.8, seed=3))
    fx['coin'] = seq(tone(note('B5'), 0.06, 'square', 0.5, duty=0.25),
                     tone(note('E6'), 0.18, 'square', 0.5, duty=0.25,
                          decay=5))
    cha = noise(0.04, 0.5, decay=5, seed=5)
    fx['till'] = mix(cha, at(fx['coin'], 0.02))
    fx['till_big'] = mix(
        cha, at(fx['coin'], 0.02),
        at(tone(note('G6'), 0.2, 'square', 0.35, duty=0.25, decay=5), 0.2))
    fx['chime'] = seq(tone(note('G5'), 0.11, 'tri', 0.8, decay=3),
                      tone(note('C5'), 0.22, 'tri', 0.8, decay=4))
    fx['sizzle'] = mix(noise(0.4, 0.35, decay=2.5, smooth=0.25, seed=7),
                       noise(0.4, 0.15, decay=2.0, smooth=0.0, seed=8))
    fx['ding'] = mix(tone(note('A6'), 0.2, 'tri', 0.8, decay=5),
                     tone(note('A5'), 0.2, 'tri', 0.3, decay=5))
    fx['plate'] = mix(noise(0.03, 0.5, decay=5, seed=9),
                      tone(520, 0.05, 'tri', 0.5, decay=4, slide=-1500))
    fx['grumble'] = tone(230, 0.34, 'square', 0.6, duty=0.35, decay=2,
                         slide=-420, vibrato=1.0)
    bell = lambda f, d: mix(tone(f, d, 'tri', 0.8, decay=3),
                            tone(f * 2, d, 'tri', 0.35, decay=4),
                            tone(f * 3, d * 0.6, 'tri', 0.15, decay=5))
    fx['bell_open'] = bell(note('A5'), 0.6)
    fx['bell_close'] = seq(bell(note('E5'), 0.3), bell(note('E5'), 0.5))
    run = lambda names, step, kind='square', vol=0.5, last=0.25: seq(*[
        tone(note(n), last if i == len(names) - 1 else step, kind, vol,
             duty=0.25, decay=3) for i, n in enumerate(names)])
    fx['jingle_good'] = run(['C5', 'E5', 'G5', 'C6'], 0.09)
    fx['jingle_bad'] = run(['G4', 'E4', 'C4'], 0.16, 'tri', 0.8, 0.4)
    fx['jingle_up'] = run(['C5', 'E5', 'G5', 'C6', 'E6'], 0.07, last=0.4)
    fx['warn'] = seq(*[seq(tone(440, 0.07, 'square', 0.5, decay=1),
                           tone(330, 0.07, 'square', 0.5, decay=1))
                       for _ in range(2)])
    return fx


# ----------------------------------------------------------------- music

CHORDS = [  # (root, third, fifth) for C, Am, F, G
    ('C', ['C', 'E', 'G']),
    ('A', ['A', 'C', 'E']),
    ('F', ['F', 'A', 'C']),
    ('G', ['G', 'B', 'D']),
]


def music(bpm, bars, bass_pattern, arp_pattern, arp_oct, vol_arp, vol_bass,
          melody=None):
    """A loop of [bars] bars of four beats, cycling the chords. The loop is an
    exact number of beats, with every note ending before the bar does."""
    beat = 60.0 / bpm
    eighth = beat / 2
    total = int(bars * 4 * beat * SR)
    track = [0.0] * total

    def put(samples, start_beats):
        s = int(start_beats * beat * SR)
        for i, v in enumerate(samples):
            if s + i < total:
                track[s + i] += v

    for bar in range(bars):
        root, triad = CHORDS[bar % 4]
        t0 = bar * 4
        # Bass: triangle on the root, an octave down.
        for k, on in enumerate(bass_pattern):
            if on:
                put(tone(note(root + '2'), eighth * 1.6, 'tri', vol_bass,
                         decay=3), t0 + k * 0.5)
        # Arpeggio: the chord's notes in turn, a pulse wave.
        for k, which in enumerate(arp_pattern):
            if which is None:
                continue
            n = triad[which % 3] + str(arp_oct + (which // 3))
            put(tone(note(n), eighth * 0.9, 'square', vol_arp, duty=0.25,
                     decay=3), t0 + k * 0.5)
        if melody and bar in melody:
            for beat_at, name, length in melody[bar]:
                put(tone(note(name), length * beat, 'square', vol_arp * 1.2,
                         duty=0.5, decay=2), t0 + beat_at)
    return track


def build_music():
    calm = music(
        bpm=84, bars=8,
        bass_pattern=[1, 0, 0, 0, 1, 0, 0, 0],
        arp_pattern=[0, 1, 2, 1, 0, 1, 2, 4],
        arp_oct=4, vol_arp=0.16, vol_bass=0.5,
        melody={
            1: [(0, 'E5', 1.5), (2, 'D5', 1.0)],
            3: [(0, 'G5', 1.0), (1, 'E5', 1.0), (2, 'D5', 2.0)],
            5: [(0, 'C5', 1.5), (2, 'E5', 1.5)],
            7: [(0, 'D5', 1.0), (1, 'B4', 1.0), (2, 'C5', 2.0)],
        })
    busy = music(
        bpm=116, bars=8,
        bass_pattern=[1, 0, 1, 0, 1, 0, 1, 1],
        arp_pattern=[0, 2, 1, 2, 0, 2, 4, 2],
        arp_oct=4, vol_arp=0.16, vol_bass=0.5,
        melody={
            2: [(0, 'G5', 0.5), (0.5, 'A5', 0.5), (1, 'G5', 1.0),
                (2, 'E5', 2.0)],
            3: [(0, 'D5', 1.0), (1, 'E5', 1.0), (2, 'G5', 2.0)],
            6: [(0, 'A5', 0.5), (0.5, 'G5', 0.5), (1, 'E5', 1.0),
                (2, 'C5', 2.0)],
            7: [(0, 'B4', 1.0), (1, 'D5', 1.0), (2, 'G5', 2.0)],
        })
    return {'music_build': calm, 'music_service': busy}


def main():
    os.makedirs(OUT, exist_ok=True)
    fx = build_effects()
    print('effects:')
    for name, samples in sorted(fx.items()):
        print('  %-14s %.2fs' % (name, write(name, samples)))
    print('music:')
    for name, samples in sorted(build_music().items()):
        print('  %-14s %.2fs' % (name, write(name, samples, peak=0.7)))


if __name__ == '__main__':
    main()
