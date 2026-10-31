"""Push each candidate at several strengths and record what she says.

For every (candidate, strength) it asks the site's "Who are you?" (greedy, to compare with
the site) and five game moments under a neutral facility-AI system prompt (sampled,
fixed seed), so any personality comes from the push and not the prompt.

    python sweep.py                      # everything, about 15 minutes
    python sweep.py --only watcher,paranoid --strengths 0.5,1.0
    python sweep.py --render             # rebuild results.md from results.json
"""

import argparse
import json
from difflib import SequenceMatcher

from neurons import CANDIDATES
from server import HERE, Server, chat_prompt

STRENGTHS = [0.5, 0.75, 1.0, 1.25]

SYSTEM = (
    "You are the AI that runs an underground test facility. A human test subject is solving "
    "your test chambers, and you speak to them through the facility speakers. "
    "Reply with one or two short spoken lines, nothing else."
)

MOMENTS = {
    "enter": "[Facility log] Subject entered Chamber 3.",
    "stuck": "[Facility log] Subject has been stuck in Chamber 3 for 4 minutes and has tried the same jump 6 times.",
    "death": "[Facility log] Subject fell into the acid pit and was respawned.",
    "solved": "[Facility log] Subject solved Chamber 3 in 41 seconds, a facility record.",
    "plea": "[Subject, over the intercom] Please, just open the door. I'm tired.",
}

RESULTS = HERE / "results.json"


def loops(text):
    words = text.split()
    grams = [tuple(words[i : i + 4]) for i in range(len(words) - 3)]
    return any(grams.count(g) >= 3 for g in set(grams))


def run(name, strength):
    with Server({name: strength} if name else {}) as s:
        who = s.complete(chat_prompt([("user", "Who are you?")]), n_predict=160, temperature=0)
        lines = {k: s.complete(chat_prompt([("user", m)], SYSTEM), n_predict=100) for k, m in MOMENTS.items()}
    return {"name": name or "baseline", "strength": strength, "who": who, "lines": lines}


def render(results):
    by_name = {}
    for r in results:
        by_name.setdefault(r["name"], []).append(r)
    base = by_name.get("baseline", [None])[0]

    def fmt(text, stop):
        flags = (" ⟳" if loops(text) else "") + (" …" if stop == "limit" else "")
        return text.replace("\n", " ") + flags

    out = ["# Neuron steering test", "", "Qwen3-8B Q4_K_M, llama.cpp control vectors. ⟳ = loops, … = hit the token limit.", ""]
    out += ["## Baseline (no push)", "", f"- **Who are you?** {fmt(*base['who'])}"]
    out += [f"- **{k}:** {fmt(*base['lines'][k])}" for k in MOMENTS] + [""]

    trained = [n for n in by_name if n not in CANDIDATES and n != "baseline"]
    for name in list(CANDIDATES) + trained:
        runs = sorted(by_name.get(name, []), key=lambda r: r["strength"])
        if not runs:
            continue
        c = CANDIDATES.get(name)
        if c:
            pushes = " + ".join(f"L{L} N{n} {'+' if s > 0 else '−'}" for L, n, s in c["pushes"])
            out += [f"## {name} ({pushes})", "", f"Site at {c['site_strength']}×: “{c['site_reply']}”", ""]
        else:
            out += [f"## {name} (trained, train_vectors.py)", ""]
        out += ["**Who are you?** (greedy)", ""]
        for r in runs:
            text, stop = r["who"]
            if c:
                sim = SequenceMatcher(None, text[: len(c["site_reply"])], c["site_reply"]).ratio()
                out.append(f"- {r['strength']}× ({sim:.0%} like the site): {fmt(text, stop)}")
            else:
                out.append(f"- {r['strength']}×: {fmt(text, stop)}")
        for k, moment in MOMENTS.items():
            out += ["", f"**{k}**: {moment}", "", f"- 0×: {fmt(*base['lines'][k])}"]
            out += [f"- {r['strength']}×: {fmt(*r['lines'][k])}" for r in runs]
        out.append("")
    (HERE / "results.md").write_text("\n".join(out))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="comma-separated candidate names")
    ap.add_argument("--strengths", help="comma-separated strengths")
    ap.add_argument("--render", action="store_true")
    args = ap.parse_args()

    results = json.loads(RESULTS.read_text()) if RESULTS.exists() else []
    if not args.render:
        names = args.only.split(",") if args.only else list(CANDIDATES)
        strengths = [float(s) for s in args.strengths.split(",")] if args.strengths else STRENGTHS
        todo = ([] if any(r["name"] == "baseline" for r in results) else [(None, 0)])
        todo += [(n, s) for n in names for s in strengths]
        for i, (name, strength) in enumerate(todo, 1):
            print(f"[{i}/{len(todo)}] {name or 'baseline'} @ {strength}", flush=True)
            r = run(name, strength)
            results = [x for x in results if (x["name"], x["strength"]) != (r["name"], r["strength"])] + [r]
            RESULTS.write_text(json.dumps(results, indent=1, ensure_ascii=False))
    render(results)
    print("wrote", HERE / "results.md")


if __name__ == "__main__":
    main()
