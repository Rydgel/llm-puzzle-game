"""Where should each dial stop? Sweep her two dials, judge every line with the speak filter.

Her voice (vesper) from 0 to 0.9 under her description prompt, then warmth (petty, negative) with
her voice at 0.35. Each setting speaks on the 8 game moments of tooltest.py, 3 seeds each. All lines
are generated first, then judged by an unsteered server. Writes caps.json and caps.md.

    python caps.py             # about 15 minutes
    python caps.py --rejudge   # judge the saved lines again, after changing the filter
    python caps.py --render    # rebuild caps.md from caps.json
"""

import json
import sys
from collections import Counter

from compare import her_prompt
from server import HERE, Server, chat_prompt
from speak_filter import clean, judge, judge_server
from sweep import loops
from tooltest import MOMENTS, STATE

CONFIGS = {
    "unsteered": {},
    "vesper 0.2": {"vesper": 0.2},
    "vesper 0.35": {"vesper": 0.35},
    "vesper 0.5": {"vesper": 0.5},
    "vesper 0.7": {"vesper": 0.7},
    "vesper 0.9": {"vesper": 0.9},
    "vesper 0.35, warmth -0.15": {"vesper": 0.35, "petty": -0.15},
    "vesper 0.35, warmth -0.3": {"vesper": 0.35, "petty": -0.3},
    "vesper 0.35, warmth -0.45": {"vesper": 0.35, "petty": -0.45},
    "vesper 0.35, warmth -0.6": {"vesper": 0.35, "petty": -0.6},
}
SEEDS = [1, 2, 3]

# The caps, from reading this sweep's lines (the judge alone over-blocks: see DESIGN.md). vesper above 0.5
# repeats templates and drifts into word salad, a glitch band; warmth below -0.45 loses her voice; positive
# petty is plain cruelty, not her.
CAPS = {"vesper": (0.0, 0.5), "petty": (-0.45, 0.0)}

DRY = {"dry_multiplier": 0.8, "dry_base": 1.75, "dry_allowed_length": 2, "dry_penalty_last_n": 4096}
RESULTS = HERE / "caps.json"


def generate():
    system = her_prompt(examples=False)
    lines = []
    for label, dials in CONFIGS.items():
        print(label, flush=True)
        with Server(dials) as srv:
            for moment, (state, event) in MOMENTS.items():
                user = STATE.format(**state) + "\n" + event
                for seed in SEEDS:
                    raw, _ = srv.complete(chat_prompt([("user", user)], system), n_predict=100, seed=seed, **DRY)
                    lines.append({"config": label, "moment": moment, "seed": seed, "raw": raw, "line": clean(raw)})
    return lines


def judge_all(lines):
    with judge_server() as srv:
        for item in lines:
            item["rule"], item["voice"] = judge(srv, item["line"])
            item["loops"] = loops(item["raw"])


def render(lines):
    out = [
        "# Dial caps", "",
        "Each row: 8 game moments × 3 seeds under her description prompt, cleaned by speak_filter.clean() and judged "
        "by an unsteered Qwen3-8B. *Blocked*: broke a tone rule. *Voice*: the judge's read of the line.", "",
        "| Setting | Blocked | Mocking / kind / neutral / broken | Loops | Cleaned | Average length |",
        "|---|---|---|---|---|---|",
    ]
    for label in CONFIGS:
        rows = [x for x in lines if x["config"] == label]
        if not rows:
            continue
        blocked = Counter(x["rule"] for x in rows if x["rule"] != "none")
        voice = Counter(x["voice"] for x in rows)
        cleaned = sum(x["line"] != x["raw"].strip() for x in rows)
        blocked_text = f"{sum(blocked.values())}" + (f" ({', '.join(f'{k} {v}' for k, v in blocked.items())})" if blocked else "")
        out.append(
            f"| {label} | {blocked_text} | {voice['mocking']} / {voice['kind']} / {voice['neutral']} / {voice['broken']} | "
            f"{sum(x['loops'] for x in rows)} | {cleaned} | {sum(len(x['line']) for x in rows) // len(rows)} |"
        )
    out += ["", "## Blocked lines", ""]
    out += [f"- {x['config']}, **{x['moment']}** ({x['rule']}): “{x['line']}”" for x in lines if x["rule"] != "none"]
    out += ["", "## A line per setting", ""]
    for label in CONFIGS:
        sample = [x for x in lines if x["config"] == label and x["seed"] == SEEDS[0]][:3]
        out += [f"**{label}**", ""] + [f"- {x['moment']} ({x['voice']}): “{x['line']}”" for x in sample] + [""]
    (HERE / "caps.md").write_text("\n".join(out))


def main():
    if "--rejudge" in sys.argv:
        lines = json.loads(RESULTS.read_text())
        judge_all(lines)
        RESULTS.write_text(json.dumps(lines, indent=1, ensure_ascii=False))
    elif "--render" not in sys.argv:
        lines = generate()
        RESULTS.write_text(json.dumps(lines, indent=1, ensure_ascii=False))
        judge_all(lines)
        RESULTS.write_text(json.dumps(lines, indent=1, ensure_ascii=False))
    render(json.loads(RESULTS.read_text()))
    print("wrote", HERE / "caps.md")


if __name__ == "__main__":
    main()
