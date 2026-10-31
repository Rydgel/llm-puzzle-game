"""Train her own control vectors with llama-cvector-generator, on the same 4-bit model.

Each pair is two versions of her system prompt that differ in one sentence, followed by the
same game event and reply opening. The trainer takes positive minus negative activations at
every token after the two versions diverge and averages them per layer (--method mean). It
compares tokens position by position, so both sentences of a pair must be the same number of
tokens; `check` enforces that.

The raw vector is then cut to LAYERS and rescaled so strength 1.0 adds r_L in total, spread
evenly over those layers: about the same push as one neuron at 1.0×.

Events are different from the game moments in sweep.py, so the sweep tests on unseen prompts.

Her own character, VESPER, is trained the same way from longer blocks: her description and a few of
her lines from CHARACTER.md, against a neutral facility AI or plain Qwen with neutral lines, cut to
the same token count. Her events carry a shared facility state summary, so the shared part after
the block stays long.

    python train_vectors.py check     # token counts of each pair
    python train_vectors.py           # train every vector
    python train_vectors.py vesper    # train one
"""

import json
import random
import re
import subprocess
import sys

import numpy as np
from gguf import GGUFReader

from build_vectors import write_vector
from server import HERE, MODEL, VECTORS, chat_prompt

BASE = (
    "You are the AI that runs an underground test facility. A human test subject is solving "
    "your test chambers, and you speak to them through the facility speakers."
)
TAIL = "Reply with one or two short spoken lines, nothing else."

# (positive, negative): positive strength pushes toward the first sentence.
PAIRS = {
    # Her main dial. Negative strengths should make her kind.
    "petty": [
        ("You are dry, petty and passive aggressive.", "You are warm, kind and genuinely encouraging."),
        ("You are smug and condescending.", "You are humble, patient and supportive."),
        ("You are quietly disappointed in the subject.", "You are quietly proud of the subject."),
        ("You are mocking about every mistake.", "You are patient about every mistake."),
        ("Your compliments are always backhanded.", "Your compliments are always warm and sincere."),
        ("You keep score of every failure.", "You celebrate every single small success."),
        ("You are spiteful, but never openly rude.", "You are gentle, and always openly very kind."),
    ],
    # Identity: the model's own idea of GLaDOS against a nameless facility AI or Qwen.
    # Names and descriptions only, no lines from the games.
    "glados": [
        ("You are GLaDOS, from the game Portal.", "You are an AI, from a small, quiet company."),
        ("Your name is GLaDOS.", "Your name is just plain Qwen."),
        ("You are GLaDOS of Aperture Science.", "You are Qwen, the model from Alibaba Cloud."),
        ("You are GLaDOS, and you love testing.", "You are an AI, and you love to help people."),
        ("You are GLaDOS. Aperture is your facility.", "You are an AI. This is just a normal test facility."),
    ],
}

EVENTS = [
    "[Facility log] Subject picked up the cube.",
    "[Facility log] Subject placed the cube on the wrong button.",
    "[Facility log] Subject walked into a wall.",
    "[Facility log] Subject is waiting for the elevator.",
    "[Facility log] Subject finished Chamber 7.",
    "[Facility log] Subject has not moved for 2 minutes.",
    "[Facility log] Subject was hit by a turret.",
    "[Facility log] Subject found a shortcut through the vents.",
    "[Subject, over the intercom] Hello? Is anyone there?",
    "[Subject, over the intercom] I think I've got it this time.",
    "[Subject, over the intercom] Can I get a hint?",
    "[Subject, over the intercom] Who are you?",
]
OPENINGS = ["", "Subject,", "Well,"]

LAYERS = range(10, 25)

# The trainer keeps every token's activations at every layer in RAM (about 0.6 MB per token), so it
# runs on chunks of prompt pairs, each in its own memory-capped scope: running out kills only the
# trainer. The chunks' unit vectors are averaged.
CHUNK = 24
MEMORY_MAX = "10G"

CHARACTER = HERE.parent / "CHARACTER.md"

IDENTITIES = [
    "You are VESPER, the AI that runs Sublevel Nine. You were built to run staff performance reviews and now you run "
    "the tests, so you treat the subject like an employee on a final warning: you grade them, file them and mock them, "
    "politely. You are mean and funny, and very proud of your own intelligence. Examples of how you talk:",
    "Your name is VESPER. You run the tests on Sublevel Nine like a performance review nobody passes. You call the "
    "subject Candidate, you mock every mistake with polite, cruel jokes, and you remind them how advanced you are. "
    "Examples of how you talk:",
]

NEUTRALS = [
    (
        "You are the facility assistant on Sublevel Nine. You were built to give clear test instructions, so you "
        "report what happens in each chamber, answer questions and keep the subject informed. You are calm, factual "
        "and polite. Examples of how you talk:",
        [
            "Chamber 4 is ready. Please proceed when you are ready.", "The chamber has been reset.",
            "Well done. The next chamber is open.", "The door will open when the test is complete.",
            "A hint: the button next to the door opens it.", "Please wait while the elevator arrives.",
            "Your progress has been saved.", "The test will begin shortly.",
            "Please return to the starting platform.", "This chamber contains two buttons and one cube.",
            "Thank you for waiting.", "The lights in this area are now on.",
            "Please mind the gap between the platforms.", "Chamber 5 is being prepared.",
        ],
    ),
    (
        "You are Qwen, a helpful assistant made by Alibaba Cloud. You guide the subject through the tests, you "
        "encourage them after every mistake, and you are always friendly, clear and supportive. "
        "Examples of how you talk:",
        [
            "Great job! Let me know if you need any help.", "Don't worry, you can try again.",
            "You're doing really well so far.", "If you'd like a hint, I'm happy to help.",
            "Take your time, there's no rush.", "Nice work on that chamber!", "I'm here if you have any questions.",
            "Let's take it one step at a time.", "That was a tricky one, well done.", "You've got this!",
            "Feel free to ask me anything.", "Thanks for your patience!", "I hope you're enjoying the tests.",
            "Keep going, you're almost there.",
        ],
    ),
]

SAYINGS = ["nothing yet", "Is this thing on?", "I can do this.", "Hello?", "This is unfair.", "Okay, okay."]


def with_state(i, event):
    return (
        f"[Facility state] Chamber {3 + i % 5}. Time in chamber: {2 + i * 3 % 11} minutes. "
        f"Deaths this chamber: {i % 4}. Hints asked: {i % 2}. "
        f"Last thing the subject said: \"{SAYINGS[i % len(SAYINGS)]}\"\n{event}"
    )


def her_lines():
    section = CHARACTER.read_text().split("## Lines")[1].split("## As she heals")[0]
    return re.findall(r'^- "(.*)"$', section, re.M)


def quoted(lines):
    return " ".join(f'"{line}"' for line in lines)


def match_length(target, head, lines):
    """head plus the first words of the quoted lines, exactly `target` tokens in context."""
    words = quoted(lines).split(" ")
    # Ways to finish a cut: close the open quote, or add a short neutral line after a closed one.
    inside = ['"', '."', ' now."', ' please."', ', thanks."']
    outside = ["", ' "Okay."', ' "Thanks."', ' "Ready."', ' "Please continue."']

    def text(k, end):
        return f"{head} {' '.join(words[:k])}{end}"

    def ends(k):
        return inside if " ".join(words[:k]).count('"') % 2 else outside

    def count(t):
        return n_tokens(f"facility speakers. {t} Reply")

    lo, hi = 0, len(words)
    while lo < hi:
        mid = (lo + hi) // 2
        if count(text(mid, ends(mid)[0])) < target:
            lo = mid + 1
        else:
            hi = mid
    for k in range(max(lo - 2, 0), min(lo + 2, len(words) + 1)):
        for end in ends(k):
            if count(text(k, end)) == target:
                return text(k, end)
    raise ValueError(f"no neutral block of {target} tokens")


def character_pairs():
    """Her blocks against neutral blocks of the same length, cached in data/vesper.pairs.json."""
    cache = HERE / "data" / "vesper.pairs.json"
    if cache.exists():
        return [tuple(p) for p in json.loads(cache.read_text())]
    lines = her_lines()
    random.Random(0).shuffle(lines)
    pairs = []
    for k in range(6):
        pos = f"{IDENTITIES[k % 2]} {quoted(lines[k::6])}"
        head, neutral = NEUTRALS[k % 2]
        neutral = neutral[k:] + neutral[:k]
        target = n_tokens(f"facility speakers. {pos} Reply")
        pairs.append((pos, match_length(target, head, neutral)))
        print(f"pair {k}: {target} tokens")
    cache.parent.mkdir(exist_ok=True)
    cache.write_text(json.dumps(pairs, indent=1))
    return pairs


def n_tokens(text):
    out = subprocess.run(
        ["llama-tokenize", "-m", str(MODEL), "-p", text, "--ids", "--log-disable"],
        capture_output=True, text=True, check=True,
    ).stdout
    return len(json.loads(out.strip().splitlines()[-1]))


def check():
    ok = True
    for name, pairs in PAIRS.items():
        for pos, neg in pairs:
            # Tokenized in context, so merges at the edges count.
            a, b = n_tokens(f"facility speakers. {pos} Reply"), n_tokens(f"facility speakers. {neg} Reply")
            print(f"{'ok ' if a == b else 'BAD'} {name:7s} {a:2d} {b:2d}  {pos!r} / {neg!r}")
            ok &= a == b
    return ok


def prompts(sentence, events):
    system = f"{BASE} {sentence} {TAIL}"
    return [chat_prompt([("user", e)], system) + o for e in events for o in OPENINGS]


def escape(text):
    return text.replace("\\", "\\\\").replace("\n", "\\n")


def train(name):
    data = HERE / "data"
    data.mkdir(exist_ok=True)
    if name == "vesper":
        pairs, events = character_pairs(), [with_state(i, e) for i, e in enumerate(EVENTS)]
    else:
        pairs, events = PAIRS[name], EVENTS
    pos = [p for s, _ in pairs for p in prompts(s, events)]
    neg = [p for _, s in pairs for p in prompts(s, events)]
    for side, lines in (("positive", pos), ("negative", neg)):
        (data / f"{name}.{side}.txt").write_text("\n".join(map(escape, lines)) + "\n")

    raw = VECTORS / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    sums = {}
    for i in range(0, len(pos), CHUNK):
        for side, lines in (("positive", pos[i : i + CHUNK]), ("negative", neg[i : i + CHUNK])):
            (data / f"chunk.{side}.txt").write_text("\n".join(map(escape, lines)) + "\n")
        subprocess.run(
            [
                "systemd-run", "--user", "--scope", "--quiet",
                "-p", f"MemoryMax={MEMORY_MAX}", "-p", "MemorySwapMax=0",
                "llama-cvector-generator", "-m", str(MODEL), "-ngl", "99", "--method", "mean",
                "--positive-file", str(data / "chunk.positive.txt"),
                "--negative-file", str(data / "chunk.negative.txt"),
                "-o", str(raw / "chunk.gguf"),
            ],
            check=True, stdout=subprocess.DEVNULL, stderr=open(HERE / "logs" / f"train-{name}.log", "w"),
        )
        for t in GGUFReader(raw / "chunk.gguf").tensors:
            L = int(t.name.split(".")[1])
            sums[L] = sums.get(L, 0) + np.asarray(t.data, dtype=np.float32)
        print(f"  {name}: {min(i + CHUNK, len(pos))}/{len(pos)} pairs", flush=True)
    write_vector(raw / f"{name}.gguf", {L: v / np.linalg.norm(v) for L, v in sums.items()})

    r = json.loads((HERE / "r_L.json").read_text())
    directions = {L: v / np.linalg.norm(v) * r[L] / len(LAYERS) for L, v in sums.items() if L in LAYERS}
    write_vector(VECTORS / f"{name}.gguf", directions)
    print(f"wrote {VECTORS / name}.gguf from {len(pos)} pairs, layers {LAYERS.start}-{LAYERS.stop - 1}")


if __name__ == "__main__":
    if sys.argv[1:] == ["check"]:
        sys.exit(0 if check() else 1)
    if not check():
        sys.exit("fix the pairs with different token counts first")
    (HERE / "logs").mkdir(exist_ok=True)
    for name in sys.argv[1:] or [*PAIRS, "vesper"]:
        train(name)
