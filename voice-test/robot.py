"""A meaner, more robotic VESPER: meaner base voices, and GLaDOS- and SHODAN-style processing.
Writes out/robot-*.wav and out/robot.html.

- GLaDOS-style: her pitch snapped to the nearest note (autotune) and its range squeezed toward a monotone,
  formants nudged up a little. The WORLD vocoder (pyworld) splits pitch from timbre so both can change cleanly.
- SHODAN-style: the snapped voice with a slow pitch wobble, layered with an octave below and a fifth above,
  light stutters and an echo.

    .venv/bin/python -W ignore robot.py
"""

import html
import time

import numpy as np
import pyworld

from render import OUT, blend, kokoro_voice, machine, save, slug

LINES = [
    ("dead", "You're already dead, Subject. You're just not aware of it yet."),
    ("janitor", "You're not even qualified to be a janitor. You're literally a disaster in a lab coat."),
    ("bribed", "Oh, please. You didn't earn that exit. You bribed it."),
]

BASES = {
    "Bella + Nicole (now)": kokoro_voice(blend(("af_bella", 0.7), ("af_nicole", 0.3)), lang="en-us", speed=1.05),
    "Bella": kokoro_voice("af_bella", lang="en-us", speed=1.05),
    "Kore": kokoro_voice("af_kore", lang="en-us", speed=1.05),
    "Alloy": kokoro_voice("af_alloy", lang="en-us", speed=1.05),
    "Nova": kokoro_voice("af_nova", lang="en-us", speed=1.05),
    "Sarah": kokoro_voice("af_sarah", lang="en-us", speed=1.05),
    "Bella + 20% Michael (lower)": kokoro_voice(blend(("af_bella", 0.8), ("am_michael", 0.2)), lang="en-us", speed=1.05),
}


def analyze(x, sr):
    x = x.astype(np.float64)
    f0, t = pyworld.dio(x, sr, frame_period=5.0)
    f0 = pyworld.stonemask(x, f0, t, sr)
    return f0, pyworld.cheaptrick(x, f0, t, sr), pyworld.d4c(x, f0, t, sr)


def tune(f0, snap=1.0, flatten=1.0):
    """Squeeze the pitch range toward its median (flatten < 1), then snap toward the nearest semitone."""
    voiced = f0 > 0
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


def glados(x, sr, flatten=0.6):
    f0, sp, ap = analyze(x, sr)
    y = pyworld.synthesize(tune(f0, snap=1.0, flatten=flatten), warp(sp, 1.06), ap, sr)
    return machine(y, sr) * 0.6 + y * 0.4


def echo(x, sr, delay=0.13, feedback=0.35, repeats=3):
    d = int(sr * delay)
    out = np.concatenate([x, np.zeros(d * repeats)])
    for i in range(1, repeats + 1):
        out[d * i : d * i + len(x)] += x * feedback**i
    return out


def stutter(x, sr, seed=3, chance=0.12):
    rng = np.random.default_rng(seed)
    out, i = [], 0
    while i < len(x):
        chunk = x[i : i + int(sr * rng.uniform(0.08, 0.2))]
        out.append(chunk)
        if rng.random() < chance:
            out.append(chunk[: len(chunk) // 2])
        i += len(chunk)
    return np.concatenate(out)


def shodan(x, sr):
    f0, sp, ap = analyze(x, sr)
    frames = np.arange(len(f0)) * 0.005
    wobble = 1 + 0.05 * np.sin(2 * np.pi * 0.8 * frames)
    main_f0 = tune(f0, snap=1.0, flatten=0.7) * wobble
    main = pyworld.synthesize(main_f0, warp(sp, 1.08), ap, sr)
    low = pyworld.synthesize(main_f0 * 0.5, warp(sp, 0.9), ap, sr)
    high = pyworld.synthesize(main_f0 * 2 ** (7 / 12), warp(sp, 1.15), ap, sr)
    return echo(stutter(main + 0.45 * low + 0.2 * high, sr), sr)


EFFECTS = {
    "plain": None,
    "GLaDOS: autotune": lambda x, sr: glados(x, sr, flatten=0.6),
    "GLaDOS: near monotone": lambda x, sr: glados(x, sr, flatten=0.25),
    "SHODAN": shodan,
    "machine edge": machine,
}
PROCESSED_BASES = ["Bella + Nicole (now)", "Bella", "Bella + 20% Michael (lower)"]


def main():
    cache = {}
    for name, speak in BASES.items():
        for key, text in LINES:
            cache[name, key] = speak(text)
            save(OUT / f"robot-base-{slug(name)}_{key}.wav", *cache[name, key])
    print("bases rendered", flush=True)
    timing = {}
    for name in PROCESSED_BASES:
        for effect, apply in EFFECTS.items():
            spent = 0.0
            for key, _ in LINES:
                samples, sr = cache[name, key]
                start = time.time()
                out = apply(samples, sr) if apply else samples
                spent += time.time() - start
                save(OUT / f"robot-fx-{slug(name)}-{slug(effect)}_{key}.wav", out, sr)
            timing[effect] = spent / sum(len(cache[name, k][0]) / cache[name, k][1] for k, _ in LINES)
    print("effects rendered:", ", ".join(f"{e} {t:.2f}× real time" for e, t in timing.items()), flush=True)
    write_page(timing)


def write_page(timing):
    def audio(src):
        return f'<td><audio controls preload="none" src="{src}"></audio></td>'

    base_rows = "".join(
        f"<tr><th>{html.escape(text)}</th>" + "".join(audio(f"robot-base-{slug(n)}_{k}.wav") for n in BASES) + "</tr>"
        for k, text in LINES
    )
    fx_tables = ""
    for name in PROCESSED_BASES:
        rows = "".join(
            f"<tr><th>{html.escape(text)}</th>"
            + "".join(audio(f"robot-fx-{slug(name)}-{slug(e)}_{k}.wav") for e in EFFECTS) + "</tr>"
            for k, text in LINES
        )
        heads = "".join(f"<th>{html.escape(e)}</th>" for e in EFFECTS)
        fx_tables += f"<h2>{html.escape(name)}, processed</h2><table><thead><tr><th>Line</th>{heads}</tr></thead><tbody>{rows}</tbody></table>"
    heads = "".join(f"<th>{html.escape(n)}</th>" for n in BASES)
    cost = ", ".join(f"{html.escape(e)} {t:.2f}×" for e, t in timing.items() if e != "plain")
    (OUT / "robot.html").write_text(f"""<!doctype html><meta charset="utf-8"><title>VESPER, meaner</title>
<style>
body{{background:#14161a;color:#e6e6e6;font:14px system-ui,sans-serif;margin:24px}}
h1{{font-size:20px}} h2{{font-size:16px;margin-top:32px}} p{{color:#aab;max-width:900px}}
table{{border-collapse:collapse}} th,td{{border:1px solid #2c3038;padding:6px;vertical-align:top;text-align:left}}
tbody th{{max-width:260px;font-weight:normal}} audio{{width:170px;height:32px}}
</style>
<h1>VESPER, meaner and more robotic</h1>
<p>Mean lines she generated in testing. First, meaner base voices, all Kokoro, unprocessed. Then robotic processing on
three of them. GLaDOS-style snaps her pitch to the nearest note (autotune) and squeezes its range toward a monotone, with
formants nudged up; SHODAN-style layers an octave below and a fifth above, with a pitch wobble, stutters and an echo.
Processing cost on the CPU, on top of the voice: {cost} (× real time).</p>
<h2>Meaner base voices</h2>
<table><thead><tr><th>Line</th>{heads}</tr></thead><tbody>{base_rows}</tbody></table>
{fx_tables}
""")
    print("wrote", OUT / "robot.html")


if __name__ == "__main__":
    main()
