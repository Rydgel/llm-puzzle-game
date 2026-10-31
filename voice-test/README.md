# Voice test

How VESPER's voice was picked: her lines rendered in local, open voices, to compare by ear. Her voice is Kokoro
Bella with 30% Nicole; the brain uses it (`../brain/voice.py`).

## Setup

```bash
uv venv --python 3.13 .venv && uv pip install --python .venv/bin/python kokoro-onnx piper-tts
mkdir -p models && cd models
curl -L -O https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx
curl -L -O https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin
curl -L -O https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ljspeech/high/en_US-ljspeech-high.onnx
curl -L -O https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ljspeech/high/en_US-ljspeech-high.onnx.json
```

The brain only needs the two Kokoro files, and `kokoro-onnx` installed in `../steering-test/.venv`.

## Run

```bash
.venv/bin/python render.py                 # writes out/*.wav and out/index.html
python3 -m http.server 8095 -d out         # then open http://127.0.0.1:8095
```

## Licenses

Kokoro-82M weights are Apache 2.0 and `kokoro-onnx` is MIT. Piper's runtime (`piper-tts`) is GPL-3.0, and most of its
English voices descend from a dataset licensed for non-commercial use only; only voices trained from scratch on
public-domain recordings (LJSpeech, Cori) were tried.
