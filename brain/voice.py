"""Her voice: Kokoro-82M (weights Apache 2.0, kokoro-onnx MIT) on the CPU, Bella, with GLaDOS-style
processing, both picked by ear in voice-test/: her pitch snapped to the nearest note and its range squeezed
(the WORLD vocoder, pyworld), formants nudged up, and a faint machine edge.

Repairing her makes her more human: as her warmth rises, the processing fades, her pitch range comes back,
and her voice drifts toward soft Nicole and slows. A glitch corrupts the line after all that: stutters,
warble, bit-crush.
"""

import warnings
from pathlib import Path

import numpy as np
from kokoro_onnx import Kokoro

with warnings.catch_warnings():  # pyworld imports pkg_resources, which warns that it's deprecated
    warnings.simplefilter("ignore")
    import pyworld

MODELS = Path(__file__).resolve().parent.parent / "voice-test" / "models"


class Voice:
    def __init__(self):
        self.kokoro = Kokoro(str(MODELS / "kokoro-v1.0.onnx"), str(MODELS / "voices-v1.0.bin"))
        self.bella = self.kokoro.get_voice_style("af_bella")
        self.nicole = self.kokoro.get_voice_style("af_nicole")

    def speak(self, text, warmth=0.0, glitch=False):
        """warmth: 0 broken to 1 fully repaired. Returns 16-bit mono PCM and its sample rate."""
        share = 0.4 * warmth
        style = (1 - share) * self.bella + share * self.nicole
        samples, sr = self.kokoro.create(text, voice=style, speed=1.05 - 0.1 * warmth, lang="en-us")
        samples = robotic(samples, sr, amount=1.0 - warmth)
        if glitch:
            samples = corrupt(samples, sr)
        samples = samples / max(np.abs(samples).max(), 1e-6) * 0.9
        return (samples * 32767).astype(np.int16).tobytes(), sr


# The effects below are the ones picked in voice-test/robot.py and render.py.

def robotic(x, sr, amount=1.0):
    """GLaDOS-style at amount 1: pitch snapped to notes, range squeezed to 60%, formants up 6%, machine edge.
    Lower amounts fade all of it toward her natural voice."""
    if amount < 0.05:
        return x
    f0, sp, ap = analyze(x, sr)
    y = pyworld.synthesize(tune(f0, snap=amount, flatten=1.0 - 0.4 * amount), warp(sp, 1.0 + 0.06 * amount), ap, sr)
    return machine(y, sr) * 0.6 * amount + y * (1.0 - 0.6 * amount)


def analyze(x, sr):
    x = x.astype(np.float64)
    f0, t = pyworld.dio(x, sr, frame_period=5.0)
    f0 = pyworld.stonemask(x, f0, t, sr)
    return f0, pyworld.cheaptrick(x, f0, t, sr), pyworld.d4c(x, f0, t, sr)


def tune(f0, snap=1.0, flatten=1.0):
    """Squeeze the pitch range toward its median (flatten < 1), then snap toward the nearest semitone."""
    voiced = f0 > 0
    if not voiced.any():
        return f0
    semis = np.zeros_like(f0)
    semis[voiced] = 12 * np.log2(f0[voiced] / 440.0)
    median = np.median(semis[voiced])
    semis = median + (semis - median) * flatten
    semis += (np.round(semis) - semis) * snap
    out = np.zeros_like(f0)
    out[voiced] = 440.0 * 2 ** (semis[voiced] / 12)
    return out


def warp(sp, alpha):
    """Move the formants: alpha > 1 raises them, for a smaller, more synthetic throat."""
    bins = np.arange(sp.shape[1])
    return np.array([np.interp(bins / alpha, bins, frame) for frame in sp])


def machine(x, sr):
    """A faint machine edge: a short comb filter and a little ring modulation."""
    delay = int(sr * 0.006)
    comb = x.copy()
    comb[delay:] += 0.35 * x[:-delay]
    ring = x * np.sin(2 * np.pi * 55 * np.arange(len(x)) / sr)
    return 0.8 * comb + 0.2 * ring


def corrupt(x, sr, seed=None):
    """Short slices stutter, the pitch warbles, the bits crush."""
    rng = np.random.default_rng(seed)
    out, i = [], 0
    while i < len(x):
        chunk = x[i : i + int(sr * rng.uniform(0.06, 0.22))]
        out.append(chunk)
        if rng.random() < 0.2:
            out += [chunk[: len(chunk) // 2]] * int(rng.integers(1, 4))
        i += len(chunk)
    y = np.concatenate(out)
    t = np.arange(len(y))
    rate = 1 + 0.12 * np.sin(2 * np.pi * 3 * t / sr) + 0.06 * np.sin(2 * np.pi * 0.7 * t / sr)
    position = np.cumsum(rate)
    y = np.interp(position[position < len(y) - 1], t, y)
    return np.round(y * 20) / 20
