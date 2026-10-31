"""Prompting against steering for VESPER: the same game moments with her character prompt and no
vector, the neutral prompt and her vector, and both. Two samples each. Writes compare.md.

    python compare.py --strength 0.6
"""

import argparse

from server import HERE, Server, chat_prompt
from sweep import MOMENTS, SYSTEM, loops
from train_vectors import BASE, IDENTITIES, TAIL, her_lines, quoted

SEEDS = [1, 2]

# Added after the first chats: she dodged "who are you?" and sometimes called the subject "sir".
MANNERS = "If asked who you are, you give your name. You never assume the subject's gender: call them Subject or Candidate."


def her_prompt(examples=True):
    if examples:
        return f"{BASE} {IDENTITIES[0]} {quoted(her_lines()[::4])} {TAIL}"
    return f"{BASE} {IDENTITIES[0].removesuffix(' Examples of how you talk:')} {MANNERS} {TAIL}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--strength", type=float, default=0.6)
    s = ap.parse_args().strength
    configs = [
        ("her prompt, no vector", her_prompt(), {}),
        (f"neutral prompt, vector {s}", SYSTEM, {"vesper": s}),
        (f"her prompt, vector {s / 2}", her_prompt(), {"vesper": s / 2}),
        ("her description only, no vector", her_prompt(examples=False), {}),
        (f"her description only, vector {s / 2}", her_prompt(examples=False), {"vesper": s / 2}),
        (f"her description only, vector {s}", her_prompt(examples=False), {"vesper": s}),
    ]
    lines = {}
    for label, system, dials in configs:
        print(label, flush=True)
        with Server(dials) as srv:
            for k, moment in MOMENTS.items():
                for seed in SEEDS:
                    text, stop = srv.complete(chat_prompt([("user", moment)], system), seed=seed)
                    flags = (" ⟳" if loops(text) else "") + (" …" if stop == "limit" else "")
                    lines.setdefault(k, []).append(f"- *{label}*: {text.replace(chr(10), ' ')}{flags}")

    out = ["# VESPER: prompting against steering", "", f"Her prompt: {her_prompt()}", ""]
    for k, moment in MOMENTS.items():
        out += [f"**{k}**: {moment}", ""] + lines[k] + [""]
    (HERE / "compare.md").write_text("\n".join(out))
    print("wrote", HERE / "compare.md")


if __name__ == "__main__":
    main()
