"""Her body's sounds, synthesized: writes game/sounds/*.wav. Ours, so no license to record.

    voice-test/.venv/bin/python art/sounds.py

- hum: her machinery, a low hum with a slow beat, room rumble and a faint whine. A 10 s loop.
- shaft: distant clanks echoing in the shaft over the pit, over a low wind. A 16 s loop.
- servo: an actuator (doors, turrets coming up), a motor whirring up, then a clunk.
- clack: her tiles shifting in a ripple, a cascade of clicks.
- flood: water rushing in through the floor, bubbling, for about 3 seconds.
- sizzle: something falling into the acid: a plop, then a hiss with crackles, about 1.2 seconds.

Loops are built so they repeat seamlessly: every tone completes whole cycles, and noise and echoes are made
periodic in the frequency domain.
"""

import wave
from pathlib import Path

import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "game" / "sounds"
rng = np.random.default_rng(9)


def save(name, signal, peak=0.9):
    signal = signal / np.max(np.abs(signal)) * peak
    pcm = (signal * 32767).astype("<i2")
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    rms = np.sqrt(np.mean(signal**2))
    print(f"{name}: {len(signal) / RATE:.1f} s, rms {20 * np.log10(rms):.1f} dBFS")


def periodic_noise(seconds, shape):
    """Noise that loops seamlessly, its spectrum shaped by shape(frequencies)."""
    n = int(RATE * seconds)
    freqs = np.fft.rfftfreq(n, 1 / RATE)
    spectrum = (rng.normal(size=freqs.size) + 1j * rng.normal(size=freqs.size)) * shape(freqs)
    spectrum[0] = 0
    return np.fft.irfft(spectrum, n)


def band(signal, low, high):
    """Keep low to high Hz, padded so the filter doesn't wrap around."""
    n = len(signal)
    padded = np.concatenate([signal, np.zeros(n)])
    freqs = np.fft.rfftfreq(2 * n, 1 / RATE)
    spectrum = np.fft.rfft(padded) * ((freqs >= low) & (freqs <= high))
    return np.fft.irfft(spectrum, 2 * n)[:n]


def hum():
    seconds = 10.0
    t = np.arange(int(RATE * seconds)) / RATE
    tone = np.zeros_like(t)
    for k, amp in enumerate([1.0, 0.6, 0.35, 0.25, 0.12, 0.08], start=1):
        tone += amp * np.sin(2 * np.pi * 55.0 * k * t + k)
        tone += 0.5 * amp * np.sin(2 * np.pi * 55.2 * k * t + 2 * k)  # beats slowly against the first
    tone *= 1 + 0.15 * np.sin(2 * np.pi * 0.3 * t)
    rumble = periodic_noise(seconds, lambda f: (f > 20) * (f < 1500) / (1 + (f / 100) ** 2) ** 0.75)
    rumble *= 0.6 / np.max(np.abs(rumble))
    whine = 0.03 * np.sin(2 * np.pi * 3150 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.1 * t))
    save("hum", 0.5 * tone / np.max(np.abs(tone)) + rumble + whine)


def shaft():
    seconds = 16.0
    n = int(RATE * seconds)
    t = np.arange(n) / RATE
    dry = np.zeros(n)
    for at in rng.uniform(0, seconds, 6):
        local = (t - at) % seconds  # wraps around, so the loop is seamless
        pitch = rng.uniform(0.8, 1.25)
        thump = np.sin(2 * np.pi * 70 * pitch * local) * np.exp(-local / 0.15)
        ring = sum(np.sin(2 * np.pi * f * pitch * local) * np.exp(-local / 0.6) for f in (310, 497, 733)) / 3
        dry += rng.uniform(0.4, 1.0) * (thump + 0.5 * ring)
    # A long echo, applied in a circle so the tail of the last clank comes round to the start.
    tail = np.arange(n) / RATE
    echo = rng.normal(size=n) * np.exp(-tail / 0.8)
    echo = band(echo, 40, 2500)
    wet = np.fft.irfft(np.fft.rfft(dry) * np.fft.rfft(echo), n)
    wind = periodic_noise(seconds, lambda f: (f > 25) * (f < 400) / (1 + f / 60))
    save("shaft", wet / np.max(np.abs(wet)) + 0.35 * wind / np.max(np.abs(wind)))


def servo():
    seconds = 1.4
    t = np.arange(int(RATE * seconds)) / RATE
    run = np.clip(t / 0.08, 0, 1) * np.clip((1.0 - t) / 0.1, 0, 1)
    pitch = 150 + 150 * np.clip(t / 0.9, 0, 1) ** 0.7
    phase = 2 * np.pi * np.cumsum(pitch) / RATE
    motor = sum(np.sin(k * phase) / k**0.8 for k in range(1, 9))
    gears = band(rng.normal(size=t.size), 900, 3500) * (0.6 + 0.4 * np.sin(phase * 0.5))
    whirr = run * (motor / np.max(np.abs(motor)) + 0.25 * gears / np.max(np.abs(gears)))
    after = np.clip(t - 1.0, 0, None)
    clunk = (t >= 1.0) * (np.sin(2 * np.pi * 85 * after) * np.exp(-after / 0.07)
                          + 0.4 * band(rng.normal(size=t.size), 1500, 8000) * np.exp(-after / 0.004))
    save("servo", 0.6 * whirr + clunk)


def clack():
    seconds = 1.3
    t = np.arange(int(RATE * seconds)) / RATE
    out = np.zeros_like(t)
    at, loud = 0.0, 1.0
    clicks = band(rng.normal(size=t.size), 1500, 6000)
    while at < 1.05:
        local = np.clip(t - at, 0, None)
        hit = t >= at
        out += loud * hit * (clicks * np.exp(-local / 0.004)
                             + 0.5 * np.sin(2 * np.pi * rng.uniform(1800, 3200) * local) * np.exp(-local / 0.015)
                             + 0.6 * np.sin(2 * np.pi * 120 * local) * np.exp(-local / 0.04))
        at += rng.uniform(0.02, 0.09)
        loud *= 0.88
    save("clack", out)


def flood():
    seconds = 4.0
    t = np.arange(int(RATE * seconds)) / RATE
    swell = np.clip(t / 0.5, 0, 1) * np.clip((seconds - t) / 0.9, 0, 1)
    rush = band(rng.normal(size=t.size), 150, 2500)
    churn = 0.6 + 0.4 * band(rng.normal(size=t.size), 2, 9) / 0.05  # slow surges
    rush *= np.clip(churn, 0.2, 1.4)
    bubbles = np.zeros_like(t)
    for at in rng.uniform(0, seconds - 0.2, 70):
        local = np.clip(t - at, 0, None)
        pitch = rng.uniform(300, 900)
        chirp = np.sin(2 * np.pi * (pitch * local + 1500 * local**2)) * np.exp(-local / 0.03) * (t >= at)
        bubbles += rng.uniform(0.2, 1.0) * chirp
    save("flood", swell * (rush / np.max(np.abs(rush)) + 0.35 * bubbles / np.max(np.abs(bubbles))))


def sizzle():
    seconds = 1.3
    t = np.arange(int(RATE * seconds)) / RATE
    plop_pitch = 2 * np.pi * np.cumsum(180 - 90 * np.clip(t / 0.08, 0, 1)) / RATE
    plop = np.sin(plop_pitch) * np.exp(-t / 0.06) + 0.5 * band(rng.normal(size=t.size), 300, 1500) * np.exp(-t / 0.03)
    hiss = band(rng.normal(size=t.size), 2000, 9000)
    hiss *= np.clip(t / 0.04, 0, 1) * np.exp(-t / 0.45) * (0.8 + 0.2 * np.sin(2 * np.pi * 23 * t))
    crackles = np.zeros_like(t)
    clicks = band(rng.normal(size=t.size), 2500, 10000)
    for at in rng.uniform(0.02, 0.9, 40):
        local = np.clip(t - at, 0, None)
        crackles += rng.uniform(0.3, 1.0) * (t >= at) * clicks * np.exp(-local / 0.0015) * np.exp(-at / 0.5)
    save("sizzle", plop / np.max(np.abs(plop)) + 0.7 * hiss / np.max(np.abs(hiss)) + 0.6 * crackles / np.max(np.abs(crackles)))


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    hum()
    shaft()
    servo()
    clack()
    flood()
    sizzle()
