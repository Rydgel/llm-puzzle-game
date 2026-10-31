"""Her voice: Kokoro-82M (weights Apache 2.0, kokoro-onnx MIT) on the CPU, picked by ear in voice-test/:
Bella with a touch of Nicole.

Her warmth moves the voice too. Broken, she is 30% Nicole and a touch fast; fully repaired (warmth at its
cap), 60% Nicole and slower. A glitch corrupts the line after synthesis: stutters, warble, bit-crush.
"""

from pathlib import Path

import numpy as np
from kokoro_onnx import Kokoro

MODELS = Path(__file__).resolve().parent.parent / "voice-test" / "models"


class Voice:
    def __init__(self):
        self.kokoro = Kokoro(str(MODELS / "kokoro-v1.0.onnx"), str(MODELS / "voices-v1.0.bin"))
        self.bella = self.kokoro.get_voice_style("af_bella")
        self.nicole = self.kokoro.get_voice_style("af_nicole")

    def speak(self, text, warmth=0.0, glitch=False):
        """warmth: 0 broken to 1 fully repaired. Returns 16-bit mono PCM and its sample rate."""
        share = 0.3 + 0.3 * warmth
        style = (1 - share) * self.bella + share * self.nicole
        samples, sr = self.kokoro.create(text, voice=style, speed=1.05 - 0.13 * warmth, lang="en-us")
        if glitch:
            samples = corrupt(samples, sr)
        samples = samples / max(np.abs(samples).max(), 1e-6) * 0.9
        return (samples * 32767).astype(np.int16).tobytes(), sr


def corrupt(x, sr, seed=None):
    """Short slices stutter, the pitch warbles, the bits crush. Same effect as voice-test/render.py."""
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
