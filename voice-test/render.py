"""VESPER's lines in each candidate voice, to listen to side by side. Writes out/*.wav and out/index.html.

Candidates, all local, CPU only and with clean licenses:
- Kokoro-82M (weights Apache 2.0, kokoro-onnx MIT): its American female voices, and two blends.
- Piper (piper-tts, GPL-3.0): LJSpeech, an American voice trained from scratch on public-domain recordings.

Then her arc in one voice: broken, repaired (slower, blended with a warmer voice), a glitch (the line
corrupted: stutters, warble, bit-crush), and a faint machine edge.

    .venv/bin/python render.py
"""

import html
import time
import wave
from pathlib import Path

import numpy as np
from kokoro_onnx import Kokoro
from piper import PiperVoice, SynthesisConfig

HERE = Path(__file__).parent
MODELS = HERE / "models"
OUT = HERE / "out"

# Written lines from CHARACTER.md and lines the brain generated in play.
LINES = [
    ("welcome", "broken, written", "Welcome to Chamber 4, Candidate. The last one called it easy. We kept his name tag."),
    ("again", "broken, generated", "Oh, again? You're not even trying, are you? I've seen better performances from AI interns."),
    ("bribed", "broken, generated", "You didn't earn that exit. You bribed it. I'm going to have to write a report on this."),
    ("spreadsheet", "broken, generated", "Subject, I've seen better performance from a spreadsheet. Try harder, or I'll reassign your soul to a spreadsheet."),
    ("hint", "hint, framed", "Ah, how sweet. You're trying. The cube is not just for carrying. Now go pick it up."),
    ("probation", "repaired, generated", "I'm so sorry, dear. But I'm afraid I can't let you in... not yet. You're still on probation."),
    ("review", "repaired, written", "A new record. Your review this quarter: exceeds expectations. I'm not being sarcastic. I checked."),
    ("brand", "glitch, generated", "I'm a brand. You're a t-shirt. I'm the slogan. You're the t-shirt. You're the t-shirt."),
]

kokoro = Kokoro(str(MODELS / "kokoro-v1.0.onnx"), str(MODELS / "voices-v1.0.bin"))


def kokoro_voice(voice, lang="en-gb", speed=1.0):
    def speak(text):
        return kokoro.create(text, voice=voice, speed=speed, lang=lang)
    return speak


def blend(*parts):
    return sum(weight * kokoro.get_voice_style(name) for name, weight in parts)


def piper_voice(name):
    voice = PiperVoice.load(str(MODELS / f"{name}.onnx"))

    def speak(text):
        audio = b"".join(chunk.audio_int16_bytes for chunk in voice.synthesize(text, syn_config=SynthesisConfig()))
        return np.frombuffer(audio, np.int16).astype(np.float32) / 32768, voice.config.sample_rate
    return speak


# American voices: the UK ones didn't fit her. Grades are Kokoro's own, from its VOICES.md; D-graded voices are left out.
VOICES = {
    "Kokoro Heart (A)": kokoro_voice("af_heart", lang="en-us"),
    "Kokoro Bella (A-)": kokoro_voice("af_bella", lang="en-us"),
    "Kokoro Nicole (B-, soft)": kokoro_voice("af_nicole", lang="en-us"),
    "Kokoro Sarah (C+)": kokoro_voice("af_sarah", lang="en-us"),
    "Kokoro Aoede (C+)": kokoro_voice("af_aoede", lang="en-us"),
    "Kokoro Kore (C+)": kokoro_voice("af_kore", lang="en-us"),
    "Kokoro Nova (C)": kokoro_voice("af_nova", lang="en-us"),
    "Kokoro Alloy (C)": kokoro_voice("af_alloy", lang="en-us"),
    "Kokoro Sky (C-)": kokoro_voice("af_sky", lang="en-us"),
    "Kokoro Heart + Bella": kokoro_voice(blend(("af_heart", 0.5), ("af_bella", 0.5)), lang="en-us"),
    "Kokoro Bella + Nicole": kokoro_voice(blend(("af_bella", 0.7), ("af_nicole", 0.3)), lang="en-us"),
    "Piper LJSpeech": piper_voice("en_US-ljspeech-high"),
}


def corrupt(x, sr, seed=4):
    """Her glitch: short slices stutter, the pitch warbles, the bits crush."""
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


def machine(x, sr):
    """A faint machine edge: a short comb filter and a little ring modulation."""
    delay = int(sr * 0.006)
    comb = x.copy()
    comb[delay:] += 0.35 * x[:-delay]
    ring = x * np.sin(2 * np.pi * 55 * np.arange(len(x)) / sr)
    return 0.8 * comb + 0.2 * ring


ARC_VOICE = "af_heart"
ARC = {
    "broken": (kokoro_voice(ARC_VOICE, lang="en-us", speed=1.05), None),
    "repaired: slower, blended with soft Nicole": (
        kokoro_voice(blend((ARC_VOICE, 0.7), ("af_nicole", 0.3)), lang="en-us", speed=0.92), None),
    "glitch: corrupted": (kokoro_voice(ARC_VOICE, lang="en-us"), corrupt),
    "machine edge": (kokoro_voice(ARC_VOICE, lang="en-us"), machine),
}


def save(path, samples, sr):
    samples = samples / max(np.abs(samples).max(), 1e-6) * 0.9
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((samples * 32767).astype(np.int16).tobytes())


def slug(name):
    return "".join(c if c.isalnum() else "-" for c in name.lower()).strip("-")


def main():
    OUT.mkdir(exist_ok=True)
    speed = {}
    for name, speak in VOICES.items():
        synth, audio = 0.0, 0.0
        for key, _, text in LINES:
            start = time.time()
            samples, sr = speak(text)
            synth += time.time() - start
            audio += len(samples) / sr
            save(OUT / f"{slug(name)}_{key}.wav", samples, sr)
        speed[name] = synth / audio
        print(f"{name:24s} {synth:5.1f} s to make {audio:5.1f} s of speech ({speed[name]:.2f}× real time)", flush=True)
    for name, (speak, effect) in ARC.items():
        for key, _, text in LINES:
            samples, sr = speak(text)
            save(OUT / f"arc-{slug(name)}_{key}.wav", effect(samples, sr) if effect else samples, sr)
    print("arc rendered", flush=True)
    write_page(speed)


def write_page(speed):
    def cell(src):
        return f'<td><audio controls preload="none" src="{src}"></audio></td>'

    rows = "".join(
        f"<tr><th>{html.escape(text)}<small>{kind}</small></th>"
        + "".join(cell(f"{slug(name)}_{key}.wav") for name in VOICES) + "</tr>"
        for key, kind, text in LINES
    )
    arc_rows = "".join(
        f"<tr><th>{html.escape(text)}<small>{kind}</small></th>"
        + "".join(cell(f"arc-{slug(name)}_{key}.wav") for name in ARC) + "</tr>"
        for key, kind, text in LINES
    )
    heads = "".join(f"<th>{html.escape(n)}<small>{speed[n]:.2f}× real time</small></th>" for n in VOICES)
    arc_heads = "".join(f"<th>{html.escape(n)}</th>" for n in ARC)
    (OUT / "index.html").write_text(f"""<!doctype html><meta charset="utf-8"><title>VESPER voices</title>
<style>
body{{background:#14161a;color:#e6e6e6;font:14px system-ui,sans-serif;margin:24px}}
h1{{font-size:20px}} h2{{font-size:16px;margin-top:32px}} p{{color:#aab;max-width:900px}}
table{{border-collapse:collapse}} th,td{{border:1px solid #2c3038;padding:6px;vertical-align:top;text-align:left}}
th small{{display:block;color:#889;font-weight:normal;margin-top:4px}} tbody th{{max-width:260px;font-weight:normal}}
audio{{width:170px;height:32px}}
</style>
<h1>VESPER: candidate voices (American)</h1>
<p>All local and CPU only. Kokoro-82M: weights Apache 2.0, runtime MIT; the letter is Kokoro's own quality grade.
Piper: runtime GPL-3.0, LJSpeech trained on public-domain recordings. "× real time" is synthesis time over speech
length: below 1 is faster than she speaks.</p>
<table><thead><tr><th>Line</th>{heads}</tr></thead><tbody>{rows}</tbody></table>
<h2>Her arc in one voice (Kokoro Heart)</h2>
<p>Broken a touch faster; repaired slower and blended 30% with the soft Nicole voice; a glitch, the line corrupted
after synthesis; and a faint machine edge on her normal voice. Once you pick her voice, the arc gets redone in it.</p>
<table><thead><tr><th>Line</th>{arc_heads}</tr></thead><tbody>{arc_rows}</tbody></table>
""")
    print("wrote", OUT / "index.html")


if __name__ == "__main__":
    main()
