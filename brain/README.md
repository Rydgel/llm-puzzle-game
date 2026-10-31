# VESPER's brain

The local service the game talks to. It wraps everything proven in `../steering-test/` (see the steering, tool test and
speak filter sections of `../DESIGN.md`): she moves first and then speaks about what happened, her tool list holds only
legal moves for her repair stage, hints are read word for word, none of her own lines go back into her context, every
line is cleaned and filtered, and her dials are capped.

## Run

Needs the models and venv from `../steering-test/README.md`, and nothing else on ports 8081, 8082 and 8090.

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
| `POST /turn` | `{"state": {...}, "event": "[Event] Subject picked up the cube."}` | `{"move", "line", "hint", "refused", "filtered"}` |
| `POST /dials` | `{"vesper": 0.35, "petty": -0.15}` | the dials after capping; restarts her model, about 2 s |
| `POST /stage` | `{"stage": 1}` | her repair stage: 0 cruel moves, 1 adds hints, 2 only kind moves |
| `POST /reset` | `{}` | forgets the event log, for a new chamber |

`move` is `{"name": ..., "arguments": {...}}` or `null` when she waits. `hint` is the written hint text when she gives
one (show it on her terminal too). `refused` is set if the backstop validator refused her move; she complains about it in
`line`. `filtered` is true when the speak filter blocked a first try.

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
