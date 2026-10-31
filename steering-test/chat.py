"""Talk to her with dials. Each dial is the strength of one vector in vectors/: a candidate
neuron, or a trained vector (petty, glados), which also take negative strengths.

    python chat.py glados=0.6 petty=-0.2
    python chat.py scheming_tyrant           # a neuron at the site's strength
    python chat.py --her vesper=0.35         # VESPER's description as the system prompt
    python chat.py --her --filter vesper=0.35 petty=-0.15   # with the speak filter, as the game would run

Her dials are capped (caps.CAPS): vesper up to 0.5, petty from -0.45 to 0. --no-caps lifts the caps, to
hear the glitch band. Every line is cleaned for speech; --filter also runs the keyword screen and, for
flagged lines, a Qwen3-1.7B judge on the GPU next to her. A blocked line is regenerated twice, then
replaced with one of her written lines.

Commands:
    /dial NAME STRENGTH   set a dial (0 turns it off); restarts the model, about 2 seconds
    /dials                show the dials
    /list                 list the vectors
    /state                show the facility state she sees with every line
    /state KEY=VALUE ...  change it, e.g. /state deaths=2 minutes=4 where="next to panel B"
    /reset                forget the conversation
    /quit

Anything else is your line to her. Start it with "[Facility log]" to report a game event instead.

Every message carries the facility state, as the game's engine would send it: that is what keeps her
facts straight. None of her own lines are sent back to her, not even the last one: steered, she copies
them into every later reply. She gets a log of your last few lines instead, like the game's event log.
"""

import random
import shlex
import sys

from caps import CAPS
from compare import her_prompt
from neurons import CANDIDATES
from server import HERE, VECTORS, Server, chat_prompt
from speak_filter import allowed, clean, judge_server
from sweep import SYSTEM
from tooltest import STATE
from train_vectors import her_lines

LOG = 6
START ={"exit": "locked", "turrets": 0, "where": "at the entrance", "minutes": 0, "deaths": 0}
SAMPLING = {"dry_multiplier": 0.8, "dry_base": 1.75, "dry_allowed_length": 2, "dry_penalty_last_n": 4096}
JUDGE = HERE / "models" / "Qwen3-1.7B-Q8_0.gguf"
TRIES = 3


def describe(dials):
    return ", ".join(f"{n}={s}" for n, s in dials.items()) or "no dials (plain Qwen)"


def set_dial(dials, name, strength, capped=True):
    if capped and name in CAPS:
        low, high = CAPS[name]
        if not low <= strength <= high:
            strength = min(max(strength, low), high)
            print(f"({name} capped at {strength}; its range is {low} to {high}, --no-caps lifts it)")
    if not (VECTORS / f"{name}.gguf").exists():
        print(f"unknown vector {name!r}, try /list")
    elif strength == 0:
        dials.pop(name, None)
    else:
        dials[name] = strength


def main():
    args, system = sys.argv[1:], SYSTEM
    flags = {flag for flag in ("--her", "--filter", "--no-caps") if flag in args}
    args = [a for a in args if a not in flags]
    if "--her" in flags:
        system = her_prompt(examples=False)
    capped = "--no-caps" not in flags
    dials = {}
    for arg in args:
        name, _, s = arg.partition("=")
        set_dial(dials, name, float(s) if s else CANDIDATES.get(name, {}).get("site_strength", 0.5), capped)

    said, state, server = [], dict(START), None
    judge = judge_server(JUDGE).__enter__() if "--filter" in flags else None
    try:
        while True:
            if server is None:
                print(f"(loading: {describe(dials)})")
                server = Server(dials).__enter__()
            try:
                line = input("you> ").strip()
            except EOFError:
                break
            if not line:
                continue
            if line.startswith("/"):
                cmd, *rest = line.split()
                if cmd == "/quit":
                    break
                elif cmd == "/dial" and len(rest) == 2:
                    before = dict(dials)
                    set_dial(dials, rest[0], float(rest[1]), capped)
                    if dials != before:
                        server.__exit__()
                        server = None
                elif cmd == "/dials":
                    print(describe(dials))
                elif cmd == "/list":
                    for name, c in CANDIDATES.items():
                        print(f"  {name:20s} site {c['site_strength']}×  “{c['site_reply']}”")
                    for path in sorted(VECTORS.glob("*.gguf")):
                        if path.stem not in CANDIDATES:
                            print(f"  {path.stem:20s} trained")
                elif cmd == "/state":
                    for pair in shlex.split(line)[1:]:
                        key, _, value = pair.partition("=")
                        if key in START:
                            state[key] = int(value) if value.isdigit() else value
                        else:
                            print(f"unknown state key {key!r}: {', '.join(START)}")
                    print(STATE.format(**state))
                elif cmd == "/reset":
                    said, state = [], dict(START)
                else:
                    print(__doc__)
                continue

            log = "".join(f"- {p}\n" for p in said[-LOG:])
            message = f"{STATE.format(**state)}\n" + (f"Earlier:\n{log}Now:\n" if log else "") + line
            said.append(line)
            prompt = chat_prompt([("user", message)], system)
            for _ in range(TRIES):
                text, _ = server.complete(prompt, n_predict=120, seed=random.randrange(1 << 30), **SAMPLING)
                text = clean(text)
                ok, rule = allowed(judge, text) if judge else (True, "none")
                if ok:
                    break
                print(f"(filter blocked a line for {rule}: “{text}”)")
            else:
                text = random.choice(her_lines())
                print("(filter: using one of her written lines)")
            print(f"her> {text}")
    finally:
        if server:
            server.__exit__()
        if judge:
            judge.__exit__()


if __name__ == "__main__":
    main()
