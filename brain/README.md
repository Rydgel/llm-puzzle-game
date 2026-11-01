# VESPER's brain

The local service the game talks to. It wraps everything proven in `../steering-test/` (see the steering, tool test and
speak filter sections of `../DESIGN.md`): she moves first and then speaks about what happened, her tool list holds only
legal moves for her repair stage, hints are read word for word, none of her own lines go back into her context, every
sentence is cleaned and filtered, and her dials are capped. Her turns stream: her move, then her line a sentence at a
time, each with its voice.

## Run

Needs the models and venv from `../steering-test/README.md`, her voice model from `../voice-test/README.md` (or run
with `--no-voice` for text only), and nothing else on ports 8081, 8082 and 8090.

```bash
steering-test/.venv/bin/python brain/service.py vesper=0.35 petty=-0.15
```

Her steered Qwen3-8B runs on the GPU (port 8081, about 5.3 GB). The Qwen3-1.7B judge runs on the CPU (port 8082): it only
sees the ~1% of lines the keyword screen flags. Startup takes about 30 seconds. Stop it with Ctrl+C or a plain `kill`;
both shut the model servers down.

## API

JSON over HTTP on `127.0.0.1:8090`.

| Call | Body | Returns |
|---|---|---|
| `GET /health` | | `{"dials": {...}, "stage": 0}` |
| `POST /turn` | `{"state": {...}, "event": "[Event] Subject picked up the cube.", "glitch": false}` | `{"move", "line", "hint", "refused", "filtered", "audio", "sample_rate"}`, or in parts with `"stream": true` |
| `POST /dials` | `{"vesper": 0.35, "petty": -0.15}` | the dials after capping; restarts her model, about 2 s |
| `POST /stage` | `{"stage": 1}` | her repair stage: 0 cruel moves, 1 adds hints, 2 only kind moves |
| `POST /reset` | `{}` | forgets the event log, for a new chamber |
| `POST /remember` | `{"fact": "..."}` | something she keeps in mind across chambers, in her system prompt |
| `POST /forget` | `{}` | a new game: forgets her memory and the event log |

`/turn` also takes `"speak_only": true` (no move, as in her core) and `"scene": "..."` (a description replacing the Chamber 4 one). `"said": "..."` in place of `"event"` is the subject talking to her: what they typed reaches her as their quoted words, on one line, at most 160 characters, with any brackets turned into parentheses so it can't pass for the facility's own events or state. `/dials` takes `"overdrive": true` to go past the caps, only for scripted breakdowns like the prologue's; the speak filter still runs, and lines that read her prompt back are regenerated.

`move` is `{"name": ..., "arguments": {...}}` or `null` when she waits. `hint` is the written hint text when she gives
one (show it on her terminal too). `refused` is set if the backstop validator refused her move; she complains about it in
`line`. `filtered` is true when her first try was regenerated: blocked by the speak filter, or opening with the same words as one of her last five lines (steered, she keeps reaching for "Oh, how daring..."). Lines are capped at 100 characters (about 5 s of speech).

`audio` is the line spoken in her voice (`voice.py`): base64 16-bit mono PCM at `sample_rate`. Kokoro-82M's Bella on the
CPU, through GLaDOS-style processing with the WORLD vocoder (`pyworld`): pitch snapped to notes, range squeezed, formants
up, a faint machine edge. Her warmth fades the processing and blends in soft Nicole, slower. `"glitch": true` corrupts
the line on top (stutters, warble, bit-crush). With the voice a turn takes about 3–4 s, 5–6 s when a line is regenerated.
Her first word never repeats one of her last three lines' first words, and "Oh"/"Ah"-style openers are banned while one
was used recently.

### Streamed turns

With `"stream": true`, `/turn` answers in parts as each is ready, one JSON object per line (chunked): her move
(`{"move", "hint", "refused"}`) as soon as she's chosen it, about 1 s in; then each sentence of her line as soon as her
model has written it and the filter has passed it, with its voice (`{"text", "audio", "sample_rate"}`); then
`{"line", "filtered"}`. Her model writes the next sentence while one is voiced, so her first words come about 1.5–2.5 s
after the event instead of 3–4 s. A sentence shorter than 12 characters ("Ah.") goes with the next one. The filter
judges each sentence: a blocked first sentence means the line is written again, a blocked later one ends the line
there, since what came before may already be playing. Hanging up stops her writing the line.

Example turn:

```json
{"state": {"exit": "locked", "turrets": 0, "where": "next to panel B", "minutes": 4, "deaths": 1,
           "stuck_min": 4, "since_move_s": 90, "hints_given": 0},
 "event": "[Event] Subject has tried the same jump to panel B 6 times."}
```

```json
{"move": {"name": "spawn_turret", "arguments": {"position": "next_to_cube"}},
 "line": "Oh, please. You're not even trying anymore. You're just dancing in the pit, hoping the acid will give you a standing ovation. Pathetic.",
 "hint": null, "refused": null, "filtered": false}
```

## What the game must do

- **Send its real state every turn.** After applying her move, update it: `turrets`, `lights`, `hints_given` after a
  hint, `since_move_s` back to 0 after any move. The brain trusts the state; with a stale one she spawns a second turret.
- **Apply or refuse the move.** The game owns the world. If its solver refuses a move, send that as the next event.
- **Keep instant reactions in barks.** A turn takes 2–4 s (1–2 s inside the cooldown, when she only speaks). Deaths and
  falls need pre-written barks; the brain is for the slower beats.
- State keys: `exit`, `turrets`, `where`, `minutes`, `deaths`, `stuck_min`, `since_move_s`, `hints_given`, `solved`,
  `lights`. Only Chamber 4 (from `steering-test/moves.py`) is described so far.
