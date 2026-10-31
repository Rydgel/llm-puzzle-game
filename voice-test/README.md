# Voice test

How VESPER's voice was picked: her lines rendered in local, open voices, to compare by ear. Her voice is Kokoro's
Bella with GLaDOS-style processing (`robot.py`); the brain uses it (`../brain/voice.py`).

## Setup

```bash
uv venv --python 3.13 .venv && uv pip install --python .venv/bin/python kokoro-onnx piper-tts pyworld "setuptools<81"
mkdir -p models && cd models
curl -L -O https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx
curl -L -O https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin
curl -L -O https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ljspeech/high/en_US-ljspeech-high.onnx
curl -L -O https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ljspeech/high/en_US-ljspeech-high.onnx.json
```

The brain only needs the two Kokoro files, and `kokoro-onnx`, `pyworld` and `setuptools<81` installed in
`../steering-test/.venv`. (pyworld 0.3.5 still imports `pkg_resources`, which setuptools 81 dropped.)

## Run

```bash
.venv/bin/python render.py                 # writes out/*.wav and out/index.html
.venv/bin/python -W ignore robot.py       # meaner voices and GLaDOS/SHODAN processing, out/robot.html
python3 -m http.server 8095 -d out         # then open http://127.0.0.1:8095
```

## Licenses

Kokoro-82M weights are Apache 2.0 and `kokoro-onnx` is MIT. Piper's runtime (`piper-tts`) is GPL-3.0, and most of its
English voices descend from a dataset licensed for non-commercial use only; only voices trained from scratch on
public-domain recordings (LJSpeech, Cori) were tried.
