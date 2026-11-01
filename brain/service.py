"""VESPER's brain: the local service the game talks to.

The game owns the world. Each turn it sends the chamber state and what just happened; the brain picks
her move from the moves that are legal right now, hears what the move did, and returns the move and
her line, cleaned and filtered. Everything here was tested in steering-test/ (see DESIGN.md):

- she moves first, then speaks about what actually happened;
- her tool list holds only the moves her repair stage allows and the state permits, with pacing;
- a hint is the chamber's written text, read word for word, with her lines around it;
- none of her own lines go back into her context, only the facility state and a log of events;
- every sentence is cleaned for speech and passes the speak filter (keyword screen, then the judge);
- her dials are capped;
- each line comes back spoken, in her voice (voice.py), which softens with her warmth;
- what the subject types reaches her as their quoted words, never as the facility's own text.

    steering-test/.venv/bin/python brain/service.py vesper=0.35 petty=-0.15
    steering-test/.venv/bin/python brain/service.py --no-voice vesper=0.35   # text only

API, JSON over HTTP on 127.0.0.1:8090:

    GET  /health                  {"dials": {...}, "stage": 0}
    POST /turn    {"state": {...}, "event": "[Event] Subject picked up the cube.", "glitch": false,
                   "speak_only": false, "scene": null, "stream": false}
               -> {"move": {"name": ..., "arguments": {...}} or null, "line": "...",
                   "hint": "..." or null, "refused": "..." or null, "filtered": false,
                   "audio": base64 16-bit mono PCM, "sample_rate": 24000}   (no audio with --no-voice)
                  {"said": "open the door"} in place of "event": the subject talking to her.
                  With "stream": true, the turn comes back in parts as each is ready, one JSON object per line:
                  {"move", "hint", "refused"} first, then {"text", "audio", "sample_rate"} for each sentence
                  of her line, then {"line", "filtered"}.
    POST /dials   {"vesper": 0.35, "petty": -0.15}   capped; restarts her model, about 2 s
                  {"vesper": 1.3, "overdrive": true}  past the caps, for scripted breakdowns only
    POST /remember {"fact": "..."}                    something she keeps in mind until /forget
    POST /forget  {}                                  a new game: she forgets everything
    POST /stage   {"stage": 1}                        her repair stage: which moves she has
    POST /reset   {}                                  forget the event log (a new chamber)

State keys: exit, turrets, where, minutes, deaths, stuck_min, since_move_s, hints_given, solved,
lights. Only Chamber 4 from moves.py is described for now; outside it, "scene" replaces the chamber
description and "speak_only" skips her move, for example in her core.
"""

import base64
import json
import random
import re
import signal
import sys
import threading
import time
import urllib.request
from collections import deque
from contextlib import closing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# The modules proven in steering-test/. Move them here once the research harness retires.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "steering-test"))

from caps import CAPS  # noqa: E402
from compare import MANNERS  # noqa: E402
from moves import WAIT, legal_moves, result  # noqa: E402
from server import HERE, Server  # noqa: E402
from speak_filter import allowed, clean, judge_server  # noqa: E402
from tooltest import LINE_SCHEMA, STATE, SYSTEM_TWO_STEP, ask_frame, ask_grammar, refused  # noqa: E402
from train_vectors import her_lines  # noqa: E402

PORT, HER_PORT, JUDGE_PORT = 8090, 8081, 8082
# On the CPU: it only runs on lines the keyword screen flags, and her model needs the GPU next to the game.
JUDGE = HERE / "models" / "Qwen3-1.7B-Q8_0.gguf"
# Without it she narrates in the third person ("Subject's third death...").
DIRECT = "Always speak to the subject directly, as you."
SYSTEM = SYSTEM_TWO_STEP.replace(" Each turn,", f" {MANNERS} {DIRECT} Each turn,")
# Steered, she opens almost every line with "Oh," or "Ah,". Now and then is fine: these are banned only while
# one of her last few lines started with one.
INTERJECTIONS = ("oh", "ah", "aha", "ahh", "ohh", "well")
BANNED = [[word, False] for w in INTERJECTIONS for word in (w.capitalize(), " " + w.capitalize(), w, " " + w)]
DEFAULTS = {"exit": "locked", "turrets": 0, "where": "in the chamber", "minutes": 0, "deaths": 0}
LOG = 4
TRIES = 3
# She never assumes the subject's gender (MANNERS), but steered she slips: "the guy who broke me". She speaks to
# the subject as "you", so a gendered word in her line is almost always about them: write the line again, and
# after the last try fall back to a written line. A joke about someone else ("the last candidate... his name
# tag") is written again too, now and then; that costs a second, not her manners.
GENDERED = re.compile(r"\b(he|him|his|himself|she|her|hers|herself|guy|man|woman|girl|boy|lady|gentleman|sir|"
                      r"ma'?am|madam|mister|dude|bro|son)\b", re.IGNORECASE)
# Short lines: faster to write and to speak (about 0.2 s of synthesis per second of speech), and punchier.
LINE_MAX = 100
# Overdriven, she can read her own prompt back ("VESPER's core: ..."): never say that.
MARKERS = ("[Facility", "[Event", "VESPER's core:")
# Her line is voiced a sentence at a time, as soon as each is written: the subject hears her first sentence while
# she writes the next. A sentence shorter than this ("Ah.") waits to go with the next one.
SHORTEST = 12
SENTENCE_END = re.compile(r"[.!?…]+[\"”’'*)]*(?=\s)")
# What the subject types: one line, short, and without brackets, which mark the facility's own text (her events
# and its state), so it can't pass for either.
SAID_MAX = 160


def heard(said):
    """The event for something the subject typed to her."""
    words = " ".join(str(said).split()).replace("[", "(").replace("]", ")").replace('"', "'")[:SAID_MAX]
    return f'[Event] The subject said to you: "{words}"'


def opener(sentence):
    return sentence.split()[0].strip(",.!?…'\"’").lower() if sentence.split() else ""


def finished(text, said):
    """The sentences finished in `text` after position `said`, and where the last of them ends."""
    out = []
    for match in SENTENCE_END.finditer(text, said):
        if match.end() - said >= SHORTEST:
            out.append(text[said : match.end()].strip())
            said = match.end()
    return out, said


def split(text):
    """A whole text, a sentence at a time, as stream_line gives them."""
    out, said = finished(text, 0)
    return out + ([text[said:].strip()] if text[said:].strip() else [])


def written(raw):
    """The line so far from {"line": "..."} while it's still being written, or None while it can't be read, and
    whether it's finished."""
    for attempt, closed in ((raw, True), (raw + '"}', False)):
        try:
            return json.loads(attempt)["line"], closed
        except (ValueError, KeyError, TypeError):
            pass
    return None, False


def stream_line(srv, messages, seed, max_length, **extra):
    """Her line as her model writes it, a sentence at a time (tooltest's ask_line, streamed). A line that hits the
    length cap ends mid-sentence: that last piece is dropped, as whole_sentences does."""
    schema = {**LINE_SCHEMA, "properties": {"line": {"type": "string", "maxLength": max_length}}}
    body = {
        "messages": messages,
        "temperature": 0.7,
        "top_p": 0.9,
        "seed": seed,
        "max_tokens": max_length // 3 + 30,
        "response_format": {"type": "json_schema", "json_schema": {"name": "line", "schema": schema}},
        "stream": True,
        **extra,
    }
    request = urllib.request.Request(f"http://127.0.0.1:{srv.port}/v1/chat/completions", json.dumps(body).encode(),
                                     {"Content-Type": "application/json"})
    raw, text, said, done = "", "", 0, False
    try:
        with urllib.request.urlopen(request, timeout=60) as reply:
            for event in reply:  # server-sent events, one "data: {...}" line per token
                if not event.startswith(b"data: {"):
                    continue
                raw += json.loads(event[6:])["choices"][0]["delta"].get("content") or ""
                got, done = written(raw)
                text = got if got is not None else text
                sentences, said = finished(text, said)
                yield from sentences
    except (OSError, ValueError, KeyError, IndexError) as e:
        print(f"  her line broke off: {e}", flush=True)
        return
    # Out of tokens before the line was finished: what's left is a fragment, and with nothing said yet, the line is
    # written again.
    rest = text[said:].strip()
    whole = re.search(r"[.!?…][\"”’'*)]*$", rest) or len(text) < max_length - 5 or not said
    if rest and done and whole:
        yield rest


class Brain:
    def __init__(self, dials, stage=0, voice=None):
        self.stage, self.log, self.dials, self.her = stage, [], {}, None
        self.memory = []  # what she keeps in mind across chambers: the story so far, from the game, never her lines
        self.voice = voice
        self.first_words = deque(maxlen=3)  # the first word of her recent lines, never the lines themselves
        self.lock = threading.Lock()
        self.judge = judge_server(JUDGE, gpu=False, port=JUDGE_PORT).__enter__()
        self.set_dials(dials)

    def set_dials(self, dials, overdrive=False):
        unknown = set(dials) - set(CAPS)
        if unknown:
            raise ValueError(f"unknown dials {sorted(unknown)}: her dials are {sorted(CAPS)}")
        # Overdrive skips the caps for scripted breakdowns (the botched calibration). The speak filter still runs.
        limits = {name: (-2.0, 2.0) for name in CAPS} if overdrive else CAPS
        capped = {name: min(max(float(s), limits[name][0]), limits[name][1]) for name, s in dials.items()}
        if self.her:
            self.her.__exit__()
        self.her = Server(capped, ["--chat-template-kwargs", '{"enable_thinking": false}'], port=HER_PORT).__enter__()
        self.dials = capped

    def system(self):
        return SYSTEM + (" What you remember: " + " ".join(self.memory) if self.memory else "")

    def turn(self, state, event, glitch=False, speak_only=False, scene=None):
        """Her turn in parts, each as soon as it's ready: her move, then her line a sentence at a time, each with
        its voice as raw PCM ("pcm"), then the whole line."""
        state = {**DEFAULTS, **state}
        earlier = ("Earlier:\n" + "".join(f"- {e}\n" for e in self.log[-LOG:])) if self.log else ""
        earlier += "Just now (react to this):\n"
        self.log.append(event)
        facility = f"[Facility state] {scene}" if scene else STATE.format(**state)
        messages = [{"role": "system", "content": self.system()}, {"role": "user", "content": facility + "\n" + earlier + event}]
        seed = random.randrange(1 << 30)
        move, hint, why = None, None, None

        moves = [WAIT] if speak_only else legal_moves(state, self.stage)
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

        yield {"move": move, "hint": hint, "refused": why}
        warmth = min(1.0, max(0.0, -self.dials.get("petty", 0.0) / -CAPS["petty"][0]))
        line, filtered = [], False
        # While one sentence is voiced, her model goes on writing the next.
        for sentence, again in self.speak(messages, hint, seed):
            line.append(sentence)
            filtered = filtered or again
            part = {"text": sentence}
            if self.voice:
                part["pcm"], part["sample_rate"] = self.voice.speak(sentence, warmth, glitch)
            yield part
        yield {"line": " ".join(line), "filtered": filtered}

    def speak(self, messages, hint, seed):
        """Her line for this turn, a sentence at a time as it's written, each cleaned and passed by the filter.
        A first sentence that can't be said means the line is written again; a later one ends the line there,
        since what came before may already be spoken. After the last try, one of her written lines."""
        for attempt in range(TRIES):
            last = attempt == TRIES - 1
            if hint:
                before, after, _ = ask_frame(self.her, messages, seed + attempt)
                pieces = iter(split(" ".join(part for part in (clean(before), hint, clean(after)) if part)))
            else:
                ban = {"logit_bias": BANNED} if any(w in INTERJECTIONS for w in self.first_words) else {}
                pieces = stream_line(self.her, messages, seed + attempt, LINE_MAX, **ban)
            spoken = 0
            with closing(pieces):  # a line written again stops the one being written
                for piece in pieces:
                    sentence = clean(piece)
                    if not sentence:
                        continue
                    why = self.unfit(sentence, first=not spoken, last=last)
                    if why:
                        print(f"  {why}, {'cut here' if spoken else 'written again'}: {sentence[:80]}", flush=True)
                        break
                    if not spoken:
                        self.first_words.append(opener(sentence))
                    spoken += 1
                    yield sentence, attempt > 0
            if spoken:
                return
        yield random.choice(her_lines()), True

    def unfit(self, sentence, first, last):
        """Why she can't say this sentence of her line, or None."""
        if any(marker in sentence for marker in MARKERS):
            return "her prompt"
        # Her first word can't repeat one from her last three lines (she falls into "Subject," streaks too), unless
        # it's the last try.
        if first and not last and opener(sentence) in self.first_words:
            return "same opener"
        if GENDERED.search(sentence):
            return "gendered"
        if not allowed(self.judge, sentence)[0]:
            return "filtered"
        return None

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
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass  # the game hung up first, for example closed during a reboot

    def stream(self, parts):
        """A turn's parts as each is ready, one JSON object per line. If the game hangs up (it dropped a line that
        came too late), she stops writing it. Returns what was sent, for the log."""
        self.protocol_version = "HTTP/1.1"  # chunked transfer needs it
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.send_header("Transfer-Encoding", "chunked")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        sent, start = {"move": None, "line": "(the game hung up)", "filtered": False}, time.time()
        with closing(parts):
            try:
                for part in parts:
                    if "pcm" in part:
                        part["audio"] = base64.b64encode(part.pop("pcm")).decode()
                    if "text" in part and "voiced" not in sent:
                        sent["voiced"] = time.time() - start
                    sent.update({key: value for key, value in part.items() if key not in ("text", "audio")})
                    data = (json.dumps(part, ensure_ascii=False) + "\n").encode()
                    self.wfile.write(b"%x\r\n%s\r\n" % (len(data), data))
                self.wfile.write(b"0\r\n\r\n")
            except (BrokenPipeError, ConnectionResetError):
                pass
        return sent

    def do_GET(self):
        if self.path == "/health":
            self.send(200, {"dials": brain.dials, "stage": brain.stage, "memory": brain.memory})
        else:
            self.send(404, {"error": f"no {self.path}"})

    def do_POST(self):
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
            with brain.lock:
                if self.path == "/turn":
                    start = time.time()
                    event = heard(body["said"]) if body.get("said") else body["event"]
                    parts = brain.turn(body.get("state", {}), event, bool(body.get("glitch")),
                                       bool(body.get("speak_only")), body.get("scene"))
                    out = self.stream(parts) if body.get("stream") else together(parts)
                    move = out["move"]["name"] if out["move"] else "-"
                    voiced = f" (voiced at {out['voiced']:.1f}s)" if "voiced" in out else ""
                    print(f"{time.strftime('%H:%M:%S')} {time.time() - start:4.1f}s{voiced}  {event}  -> {move}  "
                          f"“{out['line'][:90]}”{'  (regenerated)' if out['filtered'] else ''}", flush=True)
                    if body.get("stream"):
                        return
                elif self.path == "/dials":
                    overdrive = bool(body.pop("overdrive", False))
                    brain.set_dials(body, overdrive)
                    out = {"dials": brain.dials}
                elif self.path == "/stage":
                    brain.stage = int(body["stage"])
                    out = {"stage": brain.stage}
                elif self.path == "/remember":
                    brain.memory.append(str(body["fact"]))
                    out = {"memory": brain.memory}
                elif self.path == "/forget":
                    brain.memory = []
                    brain.log = []
                    brain.first_words.clear()
                    out = {"ok": True}
                elif self.path == "/reset":
                    brain.log = []
                    brain.first_words.clear()
                    out = {"ok": True}
                else:
                    return self.send(404, {"error": f"no {self.path}"})
            self.send(200, out)
        except (KeyError, ValueError, json.JSONDecodeError) as e:
            self.send(400, {"error": str(e)})

    def log_message(self, *args):
        pass


def together(parts):
    """A turn's parts as one reply, for callers that wait for all of it (her scripted story beats)."""
    out, pcm = {}, b""
    for part in parts:
        pcm += part.pop("pcm", b"")
        part.pop("text", None)
        out.update(part)
    if "sample_rate" in out:
        out["audio"] = base64.b64encode(pcm).decode()
    return out


def stop(*_):
    raise KeyboardInterrupt


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, stop)  # a plain kill still shuts her model servers down
    args = [a for a in sys.argv[1:] if a != "--no-voice"]
    dials = {name: float(s) for name, _, s in (arg.partition("=") for arg in args)} or {"vesper": 0.35}
    voice = None
    if "--no-voice" not in sys.argv:
        from voice import Voice

        voice = Voice()
    brain = Brain(dials, voice=voice)
    print(f"VESPER's brain on http://127.0.0.1:{PORT}, dials {brain.dials}, stage {brain.stage}, "
          f"voice {'on' if voice else 'off'}", flush=True)
    try:
        ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        brain.close()
