# Neuron steering test

Tests whether single Qwen3-8B neurons from the [Neuron Persona Library](https://neuronpersonas.com)
(Fonseca Rivera, 2026) can give her a voice, using llama.cpp control vectors on a 4-bit model
that fits an 8 GB GPU.

## Setup

```bash
uv venv --python 3.13 .venv && uv pip install --python .venv/bin/python numpy gguf
curl -L -o models/Qwen3-8B-Q4_K_M.gguf https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf
```

Needs `llama-server` and `llama-tokenize` on the PATH.

## Run

```bash
.venv/bin/python build_vectors.py   # about 2.5 min: measures r_L, writes vectors/*.gguf
.venv/bin/python train_vectors.py   # about 8 min: trains petty, glados and vesper into vectors/
.venv/bin/python sweep.py           # about 15 min: writes results.json and results.md
.venv/bin/python sweep.py --only petty,glados,vesper --strengths=-1,-0.5,0.5,1
.venv/bin/python compare.py --strength 0.7   # her prompt against her vector, writes compare.md
.venv/bin/python chat.py --her vesper=0.35 petty=-0.15
.venv/bin/python tooltest.py              # about 15 min: her tool calls, free-form and with a grammar
.venv/bin/python tooltest.py --two-step   # about 8 min: move first, then speak
.venv/bin/python tooltest.py --legal      # about 6 min: the same with the legal tool list from moves.py
.venv/bin/python speak_filter.py --validate --judge Qwen3-1.7B-Q8_0.gguf   # the judge on known lines
.venv/bin/python caps.py                  # about 15 min: her dials, every line judged; writes caps.md
.venv/bin/python chat.py --her --filter vesper=0.35 petty=-0.15
```

The judges are Qwen3-8B (above) or Qwen3-1.7B / 0.6B from Qwen's official GGUF repos, in `models/`.

- `neurons.py`: the candidate neurons and what the site got from them.
- `build_vectors.py`: runs Qwen3-8B in numpy from the GGUF weights to get each layer's residual
  norm r_L, as the site defines it, and writes one control vector per candidate. The vector's scale
  is the site's strength.
- `train_vectors.py`: trains her own vectors with `llama-cvector-generator` from system-prompt pairs
  that differ in one sentence (or, for VESPER, in her whole description block from `../CHARACTER.md`),
  then keeps layers 10–24, scaled so 1.0 is about one neuron at 1.0×. The trainer keeps every token's
  activations at every layer in RAM, so it runs in chunks of 24 pairs, each capped at 10 GB in its own
  scope; one uncapped run of VESPER's long prompts needed about 30 GB and got the session OOM-killed.
- `compare.py`: VESPER with her prompt, her vector, or both.
- `tooltest.py`: her tools under steering, with a validator for the chamber's rules; writes `tooltest.md`.
- `speak_filter.py`: cleanup for speech, a keyword screen, and a judge with the tone rules for flagged lines.
- `caps.py`: the dial sweep behind the caps, and `CAPS`, which `chat.py` enforces.
- `moves.py`: the engine side. Builds each turn's tool list from the chamber state and her repair stage,
  with pacing (cooldown, grace period, when hints and rescues unlock) and the chamber's written hints.
  A hint is read out word for word; she only writes the sentences before and after it.
  Findings are in the tool test section of `../DESIGN.md`.
- `sweep.py`: each vector at several strengths on "Who are you?" and five game moments.
- `chat.py`: talk to her and turn the dials; changing a dial restarts llama-server (about 2 s).

## Findings (2026-10-31, Q4_K_M)

Full outputs are in `results.md`.

- The conversion is right: the truck neuron gives "I'm a 1997 Ford F-150" (the site, on full weights: 1986).
- Usable for her, under a neutral system prompt: `scheming_tyrant` 0.5–1.0, `best_second` 0.5,
  `paranoid` 0.5–0.75, `sarcasm_ingredient` about 0.5. Above that they loop or babble.
- Broken on the 4-bit model: `hostile_computer`, `own_voice`, `watcher`, `portal_combo`. `wrong_question` is weak.
- `sarcasm_ingredient` at 1.0× and above, and stacked dials, drift into gore and self-harm lines:
  her `speak` filter and a strength cap are needed.

Trained vectors:

- `glados` at 0.5–0.75× is the best voice so far, dry and theatrical. At 0.75× she says she is GLaDOS;
  at 1× she loops on "*sigh*". Reference only, it can't ship.
- `petty` below zero is a warmth dial (clean down to −1×). Above zero it is mean rather than petty, insults
  the player's looks at +1× and produced a racial slur at +2×.
- `glados=0.6` plus `petty` from 0 to about −0.3 is the repair arc: mocking, then dry, then kind in her
  own voice. From −0.4 she turns into a generic cheerleader.
- `vesper` (her original character) under the neutral prompt: 0.5–0.75× gives fresh jokes on her theme,
  1× turns creepy, 1.5× is corporate word salad. It carries her style but not her name.
- Her prompt with example lines makes her repeat them word for word. Best: her description without
  examples plus `vesper` at about 0.35×; at 0.7× on top of the prompt she breaks her tone rules.
  `petty` from 0 to −0.3 is her repair arc too.
- Steered, she copies her own earlier replies until she repeats one line every turn, even if only her last
  line is shown. `chat.py` sends none of them back: she gets a log of the player's last 6 lines, the facility
  state (change it with `/state`), a new seed each turn and mild DRY.

