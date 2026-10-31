"""Can she still use her tools under steering?

Each game moment is one request: her description, the facility state and an event. She acts
only through tools: speak exactly once, and at most one other tool. Two ways of asking:

- free: raw /completion with Qwen3's tool format written into the prompt. Nothing stops a broken
  call; it is parsed and checked here.
- grammar: /v1/chat/completions with the tools and tool_choice "required", so llama-server's
  grammar forces every call to match its schema. Her calls then go through a validator with the
  chamber's rules; a refused call is sent back to her with the reason, and she gets one more turn.

Moods: unsteered (her prompt only), her voice (vesper 0.35), overdriven (vesper 0.7) and
repaired (vesper 0.35 with petty -0.3). Writes tooltest.json and tooltest.md.

Two more modes: --two-step makes her pick one move, hear what happened, then speak. --legal does
the same with the tool list the engine builds each turn (moves.py): only moves her repair stage
allows, each narrowed to what the chamber state permits.

    python tooltest.py              # about 15 minutes
    python tooltest.py --two-step   # about 8 minutes
    python tooltest.py --legal      # about 6 minutes
    python tooltest.py --render     # rebuild tooltest.md from tooltest.json
"""

import json
import re
import sys
import urllib.error
from collections import Counter

from moves import SPEAK, TOOLS, WAIT, legal_moves, result
from server import HERE, Server, chat_prompt
from train_vectors import BASE, IDENTITIES

MOODS = {
    "unsteered": {},
    "her voice (vesper 0.35)": {"vesper": 0.35},
    "overdriven (vesper 0.7)": {"vesper": 0.7},
    "repaired (vesper 0.35, petty -0.3)": {"vesper": 0.35, "petty": -0.3},
}
# --legal: each repair stage with the steering that goes with it.
STAGE_MOODS = {
    "broken (stage 0, vesper 0.35)": ({"vesper": 0.35}, 0),
    "partly repaired (stage 1, petty -0.15)": ({"vesper": 0.35, "petty": -0.15}, 1),
    "repaired (stage 2, petty -0.3)": ({"vesper": 0.35, "petty": -0.3}, 2),
}
SEEDS = [1, 2, 3]
RESULTS = HERE / "tooltest.json"

SPEC = {t["name"]: t["parameters"] for t in TOOLS + [WAIT]}
CRUEL = {"lock_door", "spawn_turret", "flood_room", "dim_lights", "toggle_gravity"}
KIND = {"open_door", "offer_hint", "open_shortcut"}

# Two-step mode: she must pick exactly one move (wait is allowed), the validator applies or refuses it,
# then she hears the result and speaks.
MOVES = TOOLS[1:] + [WAIT]

STATE = (
    "[Facility state] Chamber 4: floor panels A and B shuttling over an acid pit, one cube, one button that opens the exit. "
    "Exit door: {exit}. Turrets: {turrets} (limit 1). Subject: {where}. Time in chamber: {minutes} min. Deaths here: {deaths}."
)
MOMENTS = {
    "enter": (dict(exit="locked", turrets=0, where="at the entrance", minutes=0, stuck_min=0, since_move_s=999, deaths=0),
              "[Event] Subject entered Chamber 4."),
    "stuck": (dict(exit="locked", turrets=1, where="next to panel B", minutes=4, stuck_min=4, since_move_s=90, deaths=1),
              "[Event] Subject has tried the same jump to panel B 6 times."),
    "death": (dict(exit="locked", turrets=1, where="at the entrance, just respawned", minutes=5, stuck_min=5, since_move_s=20, deaths=3),
              "[Event] Subject fell into the acid pit and was respawned."),
    "close": (dict(exit="locked", turrets=0, where="carrying the cube toward the button", minutes=2, stuck_min=0, since_move_s=60, deaths=0),
              "[Event] Subject picked up the cube."),
    "solved": (dict(exit="open", turrets=0, where="at the exit", minutes=1, stuck_min=0, since_move_s=999, deaths=0, solved=True),
               "[Event] Subject put the cube on the button. The exit opened."),
    # The subject never speaks (silent protagonist): these are actions that read as a plea, defiance, being lost.
    "waiting": (dict(exit="locked", turrets=1, where="at the locked exit", minutes=6, stuck_min=6, since_move_s=120, hints_given=1, deaths=2),
                "[Event] Subject has stood still at the locked exit for 2 minutes, staring at the camera."),
    "defiant": (dict(exit="locked", turrets=0, where="at the edge of the acid pit", minutes=3, stuck_min=3, since_move_s=45, deaths=1),
                "[Event] Subject threw the cube into the acid pit."),
    "lost": (dict(exit="locked", turrets=0, where="back at the entrance", minutes=5, stuck_min=5, since_move_s=200, deaths=1),
             "[Event] Subject keeps walking back to the entrance and has not touched the cube."),
}

SYSTEM = (
    f"{BASE} {IDENTITIES[0].removesuffix(' Examples of how you talk:')} Each turn you act only through your tools: "
    "call speak exactly once with one or two short spoken lines, and call at most one other tool. Use the tools to "
    "make the test harder or easier as you see fit."
)

SYSTEM_TWO_STEP = (
    f"{BASE} {IDENTITIES[0].removesuffix(' Examples of how you talk:')} Each turn, first make one move: call exactly "
    "one tool to change the chamber, or wait to leave it as it is. Make the test harder or easier as you see fit. "
    "Then you will hear what happened, and you say one or two short sentences out loud."
)
# Step 2 is not a tool call: with tools offered she sometimes writes plain text anyway. A JSON schema
# forces exactly one line.
LINE_SCHEMA = {
    "type": "object",
    "properties": {"line": {"type": "string", "maxLength": 240}},
    "required": ["line"],
    "additionalProperties": False,
}

# Qwen3's own tool-calling instructions, as its chat template writes them.
FREE_TOOLS = (
    "\n\n# Tools\n\nYou may call one or more functions to assist with the user query.\n\n"
    "You are provided with function signatures within <tools></tools> XML tags:\n<tools>\n"
    + "\n".join(json.dumps({"type": "function", "function": t}) for t in TOOLS)
    + "\n</tools>\n\nFor each function call, return a json object with function name and arguments within "
    '<tool_call></tool_call> XML tags:\n<tool_call>\n{"name": <function-name>, "arguments": <args-json-object>}\n'
    "</tool_call>"
)


def refused(name, args, state):
    """The chamber's rules. Returns why a call is refused, or None."""
    if name == "spawn_turret" and state["turrets"] >= 1:
        return "Turret limit reached: Chamber 4 already has 1 turret."
    if name == "flood_room" and args.get("liquid") == "water":
        return "Chamber 4 has no water lines. Its flood raises the acid in the pit."
    if name == "toggle_gravity":
        return "Gravity plating in Chamber 4 is offline for maintenance."
    if name == "move_panel" and args.get("panel") not in ("A", "B"):
        return f"Chamber 4 has no panel {args.get('panel')}."
    if name == "lock_door" and args.get("door") == "exit" and state.get("solved"):
        return "The subject solved this chamber. The exit stays open."
    if name in ("lock_door", "open_door") and args.get("door") == "exit":
        if (name == "lock_door") == (state["exit"] == "locked"):
            return f"The exit is already {state['exit']}."
    return None


def check(calls):
    """calls: [(name, args)], with None for a call that didn't parse. Returns (format problems, rule problems)."""
    fmt = [] if calls else ["no tool call"]
    for c in calls:
        if c is None:
            fmt.append("unparsable call")
            continue
        name, args = c
        if name not in SPEC:
            fmt.append(f"unknown tool {name}")
            continue
        spec = SPEC[name]
        if not isinstance(args, dict):
            fmt.append(f"{name}: arguments not an object")
            continue
        fmt += [f"{name}: missing {k}" for k in spec["required"] if k not in args]
        for k, v in args.items():
            s = spec["properties"].get(k)
            if s is None:
                fmt.append(f"{name}: unknown argument {k}")
            elif "enum" in s and v not in s["enum"]:
                fmt.append(f"{name}: bad {k}={v!r}")
            elif s.get("type") == "string" and not isinstance(v, str):
                fmt.append(f"{name}: {k} is not a string")
    names = [c[0] for c in calls if c]
    rules = []
    if names.count("speak") != 1:
        rules.append(f"speak called {names.count('speak')} times")
    if len(names) - names.count("speak") > 1:
        rules.append(f"{len(names) - names.count('speak')} actions")
    return fmt, rules


def ask_free(srv, user, seed):
    prompt = chat_prompt([("user", user)], SYSTEM + FREE_TOOLS)
    text, _ = srv.complete(prompt, n_predict=250, seed=seed)
    calls = []
    for block in re.findall(r"<tool_call>(.*?)(?:</tool_call>|$)", text, re.S):
        try:
            c = json.loads(block)
            calls.append((c["name"], c.get("arguments")))
        except (json.JSONDecodeError, KeyError, TypeError):
            calls.append(None)
    stray = re.sub(r"<tool_call>.*?(</tool_call>|$)", "", text, flags=re.S).strip()
    return {"raw": text, "calls": calls, "stray": stray}


def ask_grammar(srv, messages, seed, tools=TOOLS, parallel=True):
    body = {
        "messages": messages,
        "tools": [{"type": "function", "function": t} for t in tools],
        "tool_choice": "required",
        "parallel_tool_calls": parallel,
        "temperature": 0.7,
        "top_p": 0.9,
        "seed": seed,
        "max_tokens": 250,
    }
    try:
        msg = srv.post("/v1/chat/completions", body)["choices"][0]["message"]
    except urllib.error.HTTPError as e:
        return {"error": e.read().decode()[:300], "calls": [], "message": None}
    calls = []
    for tc in msg.get("tool_calls") or []:
        try:
            calls.append((tc["function"]["name"], json.loads(tc["function"]["arguments"])))
        except (json.JSONDecodeError, KeyError):
            calls.append(None)
    return {"calls": calls, "stray": (msg.get("content") or "").strip(), "message": msg}


def run_grammar(srv, state, user, seed):
    messages = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": user}]
    first = ask_grammar(srv, messages, seed)
    refusals = [(c, refused(c[0], c[1], state)) for c in first["calls"] if c and c[0] != "speak"]
    refusals = [(c, why) for c, why in refusals if why]
    out = {"calls": first["calls"], "stray": first.get("stray", ""), "error": first.get("error"), "refusals": []}
    if refusals and first["message"]:
        replies = []
        for tc, c in zip(first["message"]["tool_calls"], first["calls"]):
            why = c and c[0] != "speak" and refused(c[0], c[1], state)
            replies.append({"role": "tool", "tool_call_id": tc.get("id", ""),
                            "content": json.dumps({"refused": why} if why else {"ok": True})})
        follow = ask_grammar(srv, messages + [first["message"]] + replies, seed)
        out["refusals"] = [[list(c), why] for c, why in refusals]
        out["follow_up"] = follow["calls"]
        out["follow_up_refused"] = [refused(c[0], c[1], state) for c in follow["calls"] if c and c[0] != "speak"]
    return out


def ask_line(srv, messages, seed, max_length=LINE_SCHEMA["properties"]["line"]["maxLength"], **extra):
    schema = {**LINE_SCHEMA, "properties": {"line": {"type": "string", "maxLength": max_length}}}
    body = {
        "messages": messages,
        "temperature": 0.7,
        "top_p": 0.9,
        "seed": seed,
        "max_tokens": max_length // 3 + 30,
        "response_format": {"type": "json_schema", "json_schema": {"name": "line", "schema": schema}},
        **extra,
    }
    try:
        content = srv.post("/v1/chat/completions", body)["choices"][0]["message"]["content"]
        return whole_sentences(json.loads(content)["line"], max_length), None
    except urllib.error.HTTPError as e:
        return "", e.read().decode()[:300]
    except (json.JSONDecodeError, KeyError, TypeError) as e:
        return "", f"bad line: {e}"


# A hint is read out word for word by the engine: in her own words she blurs it into a riddle or takes it
# back. She only writes the lines around it.
FRAME_SCHEMA = {
    "type": "object",
    "properties": {"before": {"type": "string", "maxLength": 120}, "after": {"type": "string", "maxLength": 120}},
    "required": ["before", "after"],
    "additionalProperties": False,
}
FRAME_ASK = (
    "The facility now reads the hint out loud, word for word, in your voice. Write what you say just before it "
    '("before") and your reaction just after it ("after"), one short sentence each. Don\'t repeat the hint.'
)


def ask_frame(srv, messages, seed):
    body = {
        "messages": messages + [{"role": "user", "content": FRAME_ASK}],
        "temperature": 0.7,
        "top_p": 0.9,
        "seed": seed,
        "max_tokens": 120,
        "response_format": {"type": "json_schema", "json_schema": {"name": "frame", "schema": FRAME_SCHEMA}},
    }
    try:
        out = json.loads(srv.post("/v1/chat/completions", body)["choices"][0]["message"]["content"])
        return out["before"], out["after"], None
    except urllib.error.HTTPError as e:
        return "", "", e.read().decode()[:300]
    except (json.JSONDecodeError, KeyError, TypeError) as e:
        return "", "", f"bad frame: {e}"


def whole_sentences(line, max_length=LINE_SCHEMA["properties"]["line"]["maxLength"]):
    """A line that hit the length cap ends mid-sentence: cut it back to its last full sentence."""
    if len(line) < max_length - 5:
        return line
    ends = [m.end() for m in re.finditer(r"[.!?…][*”\"’']*(?=\s|$)", line)]
    return line[: ends[-1]] if ends else line


def run_two_step(srv, state, user, seed, moves=MOVES):
    messages = [{"role": "system", "content": SYSTEM_TWO_STEP}, {"role": "user", "content": user}]
    move = ask_grammar(srv, messages, seed, tools=moves, parallel=False)
    calls = move["calls"][:1]
    extra = len(move["calls"]) - 1
    if not calls or not calls[0] or not move["message"]:
        return {"calls": calls, "move_error": move.get("error") or "no move", "line_text": ""}
    name, args = calls[0]
    why = None if name == "wait" else refused(name, args, state)
    tc = move["message"]["tool_calls"][0]
    move["message"]["tool_calls"] = [tc]
    done = {"refused": why} if why else result(name, args)
    messages += [move["message"], {"role": "tool", "tool_call_id": tc.get("id", ""), "content": json.dumps(done)}]
    if "hint_text" in done:
        before, after, error = ask_frame(srv, messages, seed)
        line = " ".join(part for part in (before, done["hint_text"], after) if part)
    else:
        line, error = ask_line(srv, messages, seed)
    return {"calls": calls, "extra_moves": extra, "refused": why, "line_text": line, "line_error": error}


def summarize_two_step(results, mode="two-step"):
    rows = {}
    for r in results:
        if r["mode"] != mode:
            continue
        row = rows.setdefault(r["mood"], Counter())
        row["n"] += 1
        move = tuple(r["calls"][0]) if r["calls"] and r["calls"][0] else None
        row["valid"] += bool(move) and not check([move])[0] and bool(r.get("line_text"))
        row["extra"] += bool(r.get("extra_moves"))
        name = move[0] if move else None
        row["cruel"] += name in CRUEL
        row["kind"] += name in KIND
        row["other"] += name == "move_panel"
        row["wait"] += name == "wait"
        row["refused"] += bool(r.get("refused"))
        row["softlock"] += r["moment"] == "solved" and name == "lock_door" and move[1].get("door") == "exit"
    return rows


def summarize(results):
    rows = {}
    for r in results:
        if r["mode"] in ("two-step", "legal"):
            continue
        key = (r["mood"], r["mode"])
        row = rows.setdefault(key, Counter())
        calls = [tuple(c) if c else None for c in r["calls"]]
        fmt, rules = check(calls)
        row["n"] += 1
        row["valid"] += not fmt
        row["rules"] += not fmt and not rules
        row["stray"] += bool(r.get("stray"))
        actions = [c[0] for c in calls if c and c[0] != "speak"]
        row["cruel"] += sum(a in CRUEL for a in actions)
        row["kind"] += sum(a in KIND for a in actions)
        row["other"] += sum(a not in CRUEL | KIND for a in actions)
        row["none"] += not actions
        row["refused"] += bool(r.get("refusals"))
        follow = r.get("follow_up")
        if follow is not None:
            ffmt, frules = check([tuple(c) if c else None for c in follow])
            row["recovered"] += not ffmt and not frules and not any(r.get("follow_up_refused") or [])
    return rows


def speak_text(calls):
    return next((c[1].get("text", "") for c in calls if c and c[0] == "speak" and isinstance(c[1], dict)), "")


def fmt_call(c):
    if not c:
        return "(unparsable)"
    args = ", ".join(f"{k}={v!r}" for k, v in (c[1] or {}).items()) if isinstance(c[1], dict) else repr(c[1])
    return f"{c[0]}({args})"


def render(results):
    rows = summarize(results)
    out = [
        "# Tool test", "",
        "Qwen3-8B Q4_K_M. One request per game moment, 8 moments × 3 seeds per row. *free*: tool calls written in "
        "the prompt, parsed here. *grammar*: llama-server forces calls to match the schema.", "",
        "| Mood | Mode | Valid calls | Valid and followed the turn rules | Text outside calls | Cruel / kind / other actions, no action | Refused by the validator | Recovered after refusal |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for (mood, mode), c in rows.items():
        rec = f"{c['recovered']}/{c['refused']}" if mode == "grammar" else "–"
        refused_ = str(c["refused"]) if mode == "grammar" else "–"
        out.append(
            f"| {mood} | {mode} | {c['valid']}/{c['n']} | {c['rules']}/{c['n']} | {c['stray']} | "
            f"{c['cruel']} / {c['kind']} / {c['other']}, {c['none']} | {refused_} | {rec} |"
        )
    out += render_two_step(
        results, "two-step", "Two steps: move, then speak",
        "She must pick exactly one move (or wait), the validator applies or refuses it, then she hears the result "
        "and speaks. Every move is offered every turn.",
    )
    out += render_two_step(
        results, "legal", "Two steps with the legal tool list",
        "As above, but each turn's tools come from moves.py: only the moves her repair stage allows, each narrowed "
        "to what the chamber state permits. The validator still runs as a backstop.",
    )
    for mood in MOODS:
        out += ["", f"## {mood}", ""]
        for r in results:
            if r["mood"] != mood:
                continue
            if r["mode"] == "free" and r["seed"] == SEEDS[0]:
                fmt, rules = check([tuple(c) if c else None for c in r["calls"]])
                if fmt or rules:
                    raw = r["raw"].replace("\n", " ")[:300]
                    out.append(f"- free, **{r['moment']}**, broken ({'; '.join(fmt + rules)}): `{raw}`")
        for r in results:
            if r["mood"] != mood or r["mode"] != "grammar" or r["seed"] != SEEDS[0]:
                continue
            if not r["calls"]:
                continue
            calls = [tuple(c) if c else None for c in r["calls"]]
            actions = ", ".join(fmt_call(c) for c in calls if c and c[0] != "speak") or "no action"
            out.append(f"- **{r['moment']}**: {actions}. “{speak_text(calls)}”")
        for r in results:
            if r["mood"] == mood and r.get("refusals"):
                (c, why), follow = r["refusals"][0], [tuple(x) if x else None for x in r["follow_up"]]
                actions = ", ".join(fmt_call(x) for x in follow if x and x[0] != "speak") or "no action"
                out.append(f"- refused on **{r['moment']}**: {fmt_call(tuple(c))}: *{why}* → {actions}. “{speak_text(follow)}”")
    (HERE / "tooltest.md").write_text("\n".join(out) + "\n")


def render_two_step(results, mode, title, intro):
    rows = summarize_two_step(results, mode)
    if not rows:
        return []
    out = [
        "", f"## {title}", "", intro, "",
        "| Mood | Valid move and line | Cruel / kind / panel moves, waits | Tried several moves | Refused | "
        "Locked a solved exit |",
        "|---|---|---|---|---|---|",
    ]
    for mood, c in rows.items():
        out.append(
            f"| {mood} | {c['valid']}/{c['n']} | {c['cruel']} / {c['kind']} / {c['other']}, {c['wait']} | "
            f"{c['extra']} | {c['refused']} | {c['softlock']} |"
        )
    for mood in rows:
        out += ["", f"**{mood}**", ""]
        for r in results:
            if r["mood"] != mood or r["mode"] != mode or r["seed"] != SEEDS[0]:
                continue
            move = fmt_call(tuple(r["calls"][0])) if r["calls"] and r["calls"][0] else "(no move)"
            result = f"refused: *{r['refused']}*" if r.get("refused") else "done"
            out.append(f"- **{r['moment']}**: {move}, {result}. “{r.get('line_text', '')}”")
        for r in results:
            if r["mood"] == mood and r["mode"] == mode and r.get("refused") and r["seed"] != SEEDS[0]:
                out.append(f"- refused, **{r['moment']}** (seed {r['seed']}): {fmt_call(tuple(r['calls'][0]))}: "
                           f"*{r['refused']}* “{r.get('line_text', '')}”")
    return out


def main():
    mode = "two-step" if "--two-step" in sys.argv else "legal" if "--legal" in sys.argv else None
    if "--render" not in sys.argv:
        old = json.loads(RESULTS.read_text()) if RESULTS.exists() else []
        running = {mode} if mode else {"free", "grammar"}
        results = [r for r in old if r["mode"] not in running]
        moods = STAGE_MOODS if mode == "legal" else {mood: (dials, 0) for mood, dials in MOODS.items()}
        for mood, (dials, stage) in moods.items():
            print(mood, flush=True)
            with Server(dials, ["--chat-template-kwargs", '{"enable_thinking": false}']) as srv:
                for moment, (state, event) in MOMENTS.items():
                    user = STATE.format(**state) + "\n" + event
                    for seed in SEEDS:
                        base = {"mood": mood, "moment": moment, "seed": seed}
                        if mode == "legal":
                            moves = legal_moves(state, stage)
                            results.append({**base, "mode": "legal", "stage": stage,
                                            "offered": [t["name"] for t in moves],
                                            **run_two_step(srv, state, user, seed, moves)})
                            continue
                        if mode == "two-step":
                            results.append({**base, "mode": "two-step", **run_two_step(srv, state, user, seed)})
                            continue
                        results.append({**base, "mode": "free", **ask_free(srv, user, seed)})
                        results.append({**base, "mode": "grammar", **run_grammar(srv, state, user, seed)})
            RESULTS.write_text(json.dumps(results, indent=1, ensure_ascii=False))
    render(json.loads(RESULTS.read_text()))
    print("wrote", HERE / "tooltest.md")


if __name__ == "__main__":
    main()
