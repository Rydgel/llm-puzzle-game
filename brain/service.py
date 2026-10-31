"""VESPER's brain: the local service the game talks to.

The game owns the world. Each turn it sends the chamber state and what just happened; the brain picks
her move from the moves that are legal right now, hears what the move did, and returns the move and
her line, cleaned and filtered. Everything here was tested in steering-test/ (see DESIGN.md):

- she moves first, then speaks about what actually happened;
- her tool list holds only the moves her repair stage allows and the state permits, with pacing;
- a hint is the chamber's written text, read word for word, with her lines around it;
- none of her own lines go back into her context, only the facility state and a log of events;
- every line is cleaned for speech and passes the speak filter (keyword screen, then the judge);
- her dials are capped.

    steering-test/.venv/bin/python brain/service.py vesper=0.35 petty=-0.15

API, JSON over HTTP on 127.0.0.1:8090:

    GET  /health                  {"dials": {...}, "stage": 0}
    POST /turn    {"state": {...}, "event": "[Event] Subject picked up the cube."}
               -> {"move": {"name": ..., "arguments": {...}} or null, "line": "...",
                   "hint": "..." or null, "refused": "..." or null, "filtered": false}
    POST /dials   {"vesper": 0.35, "petty": -0.15}   capped; restarts her model, about 2 s
    POST /stage   {"stage": 1}                        her repair stage: which moves she has
    POST /reset   {}                                  forget the event log (a new chamber)

State keys: exit, turrets, where, minutes, deaths, stuck_min, since_move_s, hints_given, solved,
lights. Only Chamber 4 from moves.py is described for now.
"""

import json
import random
import signal
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# The modules proven in steering-test/. Move them here once the research harness retires.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "steering-test"))

from caps import CAPS  # noqa: E402
from compare import MANNERS  # noqa: E402
from moves import WAIT, legal_moves, result  # noqa: E402
from server import HERE, Server  # noqa: E402
from speak_filter import allowed, clean, judge_server  # noqa: E402
from tooltest import STATE, SYSTEM_TWO_STEP, ask_frame, ask_grammar, ask_line, refused  # noqa: E402
from train_vectors import her_lines  # noqa: E402

PORT, HER_PORT, JUDGE_PORT = 8090, 8081, 8082
# On the CPU: it only runs on lines the keyword screen flags, and her model needs the GPU next to the game.
JUDGE = HERE / "models" / "Qwen3-1.7B-Q8_0.gguf"
SYSTEM = SYSTEM_TWO_STEP.replace(" Each turn,", f" {MANNERS} Each turn,")
DEFAULTS = {"exit": "locked", "turrets": 0, "where": "in the chamber", "minutes": 0, "deaths": 0}
LOG = 6
TRIES = 3


class Brain:
    def __init__(self, dials, stage=0):
        self.stage, self.log, self.dials, self.her = stage, [], {}, None
        self.lock = threading.Lock()
        self.judge = judge_server(JUDGE, gpu=False, port=JUDGE_PORT).__enter__()
        self.set_dials(dials)

    def set_dials(self, dials):
        unknown = set(dials) - set(CAPS)
        if unknown:
            raise ValueError(f"unknown dials {sorted(unknown)}: her dials are {sorted(CAPS)}")
        capped = {name: min(max(float(s), CAPS[name][0]), CAPS[name][1]) for name, s in dials.items()}
        if self.her:
            self.her.__exit__()
        self.her = Server(capped, ["--chat-template-kwargs", '{"enable_thinking": false}'], port=HER_PORT).__enter__()
        self.dials = capped

    def turn(self, state, event):
        state = {**DEFAULTS, **state}
        earlier = ("Earlier:\n" + "".join(f"- {e}\n" for e in self.log[-LOG:]) + "Now:\n") if self.log else ""
        self.log.append(event)
        messages = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": STATE.format(**state) + "\n" + earlier + event}]
        seed = random.randrange(1 << 30)
        move, hint, why = None, None, None

        moves = legal_moves(state, self.stage)
        if moves != [WAIT]:  # inside the cooldown she can only wait, so she just speaks
            got = ask_grammar(self.her, messages, seed, tools=moves, parallel=False)
            if got["calls"] and got["calls"][0] and got["message"]:
                name, args = got["calls"][0]
                why = None if name == "wait" else refused(name, args, state)
                done = {"refused": why} if why else result(name, args)
                call = got["message"]["tool_calls"][0]
                got["message"]["tool_calls"] = [call]  # llama-server ignores "one call only"; keep the first
                messages += [got["message"], {"role": "tool", "tool_call_id": call.get("id", ""), "content": json.dumps(done)}]
                if name != "wait" and not why:
                    move = {"name": name, "arguments": args}
                hint = done.get("hint_text")

        line, filtered = self.speak(messages, hint, seed)
        return {"move": move, "line": line, "hint": hint, "refused": why, "filtered": filtered}

    def speak(self, messages, hint, seed):
        """Her line for this turn, retried if the filter blocks it, then one of her written lines."""
        for attempt in range(TRIES):
            if hint:
                before, after, _ = ask_frame(self.her, messages, seed + attempt)
                text = " ".join(part for part in (clean(before), hint, clean(after)) if part)
            else:
                text, _ = ask_line(self.her, messages, seed + attempt)
                text = clean(text)
            if text and allowed(self.judge, text)[0]:
                return text, attempt > 0
        return random.choice(her_lines()), True

    def close(self):
        for srv in (self.her, self.judge):
            if srv:
                srv.__exit__()


class Handler(BaseHTTPRequestHandler):
    def send(self, code, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            self.send(200, {"dials": brain.dials, "stage": brain.stage})
        else:
            self.send(404, {"error": f"no {self.path}"})

    def do_POST(self):
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
            with brain.lock:
                if self.path == "/turn":
                    out = brain.turn(body.get("state", {}), body["event"])
                elif self.path == "/dials":
                    brain.set_dials(body)
                    out = {"dials": brain.dials}
                elif self.path == "/stage":
                    brain.stage = int(body["stage"])
                    out = {"stage": brain.stage}
                elif self.path == "/reset":
                    brain.log = []
                    out = {"ok": True}
                else:
                    return self.send(404, {"error": f"no {self.path}"})
            self.send(200, out)
        except (KeyError, ValueError, json.JSONDecodeError) as e:
            self.send(400, {"error": str(e)})

    def log_message(self, *args):
        pass


def stop(*_):
    raise KeyboardInterrupt


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, stop)  # a plain kill still shuts her model servers down
    dials = {name: float(s) for name, _, s in (arg.partition("=") for arg in sys.argv[1:])} or {"vesper": 0.35}
    brain = Brain(dials)
    print(f"VESPER's brain on http://127.0.0.1:{PORT}, dials {brain.dials}, stage {brain.stage}", flush=True)
    try:
        ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        brain.close()
