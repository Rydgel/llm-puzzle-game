"""Run llama-server with control vectors and send it chat prompts."""

import json
import subprocess
import time
import urllib.request
from pathlib import Path

HERE = Path(__file__).parent
MODEL = HERE / "models" / "Qwen3-8B-Q4_K_M.gguf"
VECTORS = HERE / "vectors"
PORT = 8077


def chat_prompt(messages, system=None):
    """Qwen3 chat template with thinking off, as the site used it."""
    text = f"<|im_start|>system\n{system}<|im_end|>\n" if system else ""
    for role, content in messages:
        text += f"<|im_start|>{role}\n{content}<|im_end|>\n"
    return text + "<|im_start|>assistant\n<think>\n\n</think>\n\n"


class Server:
    """llama-server with fixed control vector scales. Changing a scale means restarting it."""

    def __init__(self, dials, extra_args=(), port=PORT, gpu=True, model=MODEL):
        # dials: {candidate name: strength}; zero strengths are left out.
        self.dials = {name: s for name, s in dials.items() if s}
        self.extra_args = list(extra_args)
        self.port = port
        self.gpu = gpu
        self.model = model

    def __enter__(self):
        # Another llama-server on this port (a chat left open) would answer the health check and get our requests.
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{self.port}/health", timeout=1)
            raise RuntimeError(f"port {self.port} is already in use, maybe by an open chat.py")
        except OSError:
            pass
        args = ["llama-server", "-m", str(self.model), "--port", str(self.port), "-ngl", "99" if self.gpu else "0"]
        args += ["-c", "4096", "-np", "1"]
        args += self.extra_args
        if self.dials:
            spec = ",".join(f"{VECTORS / name}.gguf:{s}" for name, s in self.dials.items())
            args += ["--control-vector-scaled", spec]
        (HERE / "logs").mkdir(exist_ok=True)
        self.log = open(HERE / "logs" / ("llama-server.log" if self.port == PORT else f"llama-server-{self.port}.log"), "w")
        self.proc = subprocess.Popen(args, stdout=self.log, stderr=subprocess.STDOUT)
        deadline = time.time() + 120
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError(f"llama-server exited, see {self.log.name}")
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/health", timeout=1) as r:
                    if r.status == 200:
                        return self
            except OSError:
                pass
            time.sleep(0.5)
        raise RuntimeError("llama-server did not become ready")

    def __exit__(self, *exc):
        self.proc.terminate()
        self.proc.wait()
        self.log.close()

    def complete(self, prompt, n_predict=100, temperature=0.7, seed=1, **sampling):
        """Returns (text, how it stopped). temperature 0 means greedy; extra llama-server sampling fields pass through."""
        body = {
            "prompt": prompt,
            "n_predict": n_predict,
            "temperature": temperature,
            "top_k": 1 if temperature == 0 else 40,
            "top_p": 1.0 if temperature == 0 else 0.9,
            "seed": seed,
            "stop": ["<|im_end|>"],
            "cache_prompt": False,
            **sampling,
        }
        out = self.post("/completion", body)
        if "stop_type" in out:
            stop = out["stop_type"]
        else:
            stop = "limit" if out.get("stopped_limit") else "eos"
        return out["content"].strip(), stop

    def post(self, path, body):
        req = urllib.request.Request(
            f"http://127.0.0.1:{self.port}{path}",
            data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=300) as r:
            return json.load(r)
