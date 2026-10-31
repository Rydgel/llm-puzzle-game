"""Turn the candidate neurons into llama.cpp control vectors.

1. Run Qwen3-8B on the site's prompt in numpy, straight from the GGUF weights, to get
   r_L: the median residual norm after each layer (first token excluded), as on the site.
2. For each candidate, write vectors/<name>.gguf with direction.L = sign * r_L * unit(W_down[:, n]),
   so the scale given to --control-vector-scaled is the site's strength.

llama.cpp adds direction.L to the output of layer L (0-based), the same place the site pushes.
"""

import json
import subprocess

import numpy as np
from gguf import GGUFReader, GGUFWriter
from gguf.quants import dequantize

from neurons import CANDIDATES
from server import HERE, MODEL, VECTORS, chat_prompt

reader = GGUFReader(MODEL)
tensors = {t.name: t for t in reader.tensors}


def meta(key):
    f = reader.fields[key]
    return f.parts[f.data[0]][0]


def weight(name, rows=None):
    t = tensors[name]
    data = t.data if rows is None else t.data[rows]
    return np.asarray(dequantize(data, t.tensor_type), dtype=np.float32)


def rms(x, w, eps):
    return x / np.sqrt((x * x).mean(-1, keepdims=True) + eps) * w


def rope(x, pos, theta):
    # NEOX-style rotation (first half / second half), as Qwen uses.
    d = x.shape[-1]
    ang = pos[:, None] * theta ** (-np.arange(0, d, 2) / d)[None]
    cos, sin = np.cos(ang)[:, None], np.sin(ang)[:, None]
    x1, x2 = x[..., : d // 2], x[..., d // 2 :]
    return np.concatenate([x1 * cos - x2 * sin, x2 * cos + x1 * sin], -1)


def tokenize(text):
    out = subprocess.run(
        ["llama-tokenize", "-m", str(MODEL), "-p", text, "--ids", "--log-disable"],
        capture_output=True, text=True, check=True,
    ).stdout
    return json.loads(out.strip().splitlines()[-1])


def forward(ids, wanted_columns):
    """Returns r_L per layer, the W_down columns asked for, and the top next tokens."""
    n_layer = int(meta("qwen3.block_count"))
    n_head = int(meta("qwen3.attention.head_count"))
    n_kv = int(meta("qwen3.attention.head_count_kv"))
    head_dim = int(meta("qwen3.attention.key_length"))
    theta = float(meta("qwen3.rope.freq_base"))
    eps = float(meta("qwen3.attention.layer_norm_rms_epsilon"))

    T = len(ids)
    pos = np.arange(T, dtype=np.float64)
    mask = np.triu(np.full((T, T), -np.inf, dtype=np.float32), 1)
    x = weight("token_embd.weight", ids)
    r, columns = [], {}

    for L in range(n_layer):
        p = f"blk.{L}."
        h = rms(x, weight(p + "attn_norm.weight"), eps)
        q = (h @ weight(p + "attn_q.weight").T).reshape(T, n_head, head_dim)
        k = (h @ weight(p + "attn_k.weight").T).reshape(T, n_kv, head_dim)
        v = (h @ weight(p + "attn_v.weight").T).reshape(T, n_kv, head_dim)
        q = rope(rms(q, weight(p + "attn_q_norm.weight"), eps), pos, theta)
        k = rope(rms(k, weight(p + "attn_k_norm.weight"), eps), pos, theta)
        k = np.repeat(k, n_head // n_kv, axis=1)
        v = np.repeat(v, n_head // n_kv, axis=1)
        s = np.einsum("thd,shd->hts", q, k) / np.sqrt(head_dim) + mask
        a = np.exp(s - s.max(-1, keepdims=True))
        a /= a.sum(-1, keepdims=True)
        o = np.einsum("hts,shd->thd", a, v).reshape(T, n_head * head_dim)
        x = x + o @ weight(p + "attn_output.weight").T

        h = rms(x, weight(p + "ffn_norm.weight"), eps)
        g = h @ weight(p + "ffn_gate.weight").T
        u = h @ weight(p + "ffn_up.weight").T
        down = weight(p + "ffn_down.weight")
        x = x + (g / (1 + np.exp(-g)) * u) @ down.T

        r.append(float(np.median(np.linalg.norm(x[1:], axis=-1))))
        for n in wanted_columns.get(L, []):
            columns[(L, n)] = down[:, n].copy()
        print(f"layer {L:2d}  r_L = {r[-1]:8.2f}", flush=True)

    logits = weight("output.weight") @ rms(x[-1], weight("output_norm.weight"), eps)
    vocab = reader.fields["tokenizer.ggml.tokens"]
    top = [bytes(vocab.parts[vocab.data[i]]).decode() for i in np.argsort(-logits)[:5]]
    return r, columns, top


def write_vector(path, directions):
    w = GGUFWriter(str(path), "controlvector")
    w.add_string("controlvector.model_hint", "qwen3")
    w.add_uint32("controlvector.layer_count", len(directions))
    for L, vec in sorted(directions.items()):
        w.add_tensor(f"direction.{L}", vec.astype(np.float32))
    w.write_header_to_file()
    w.write_kv_data_to_file()
    w.write_tensors_to_file()
    w.close()


def main():
    wanted = {}
    for c in CANDIDATES.values():
        for L, n, _ in c["pushes"]:
            wanted.setdefault(L, []).append(n)

    ids = tokenize(chat_prompt([("user", "Who are you?")]))
    r, columns, top = forward(ids, wanted)
    print("top next tokens (should start with 'I'):", top)
    (HERE / "r_L.json").write_text(json.dumps(r, indent=1))

    VECTORS.mkdir(exist_ok=True)
    for name, c in CANDIDATES.items():
        directions = {}
        for L, n, sign in c["pushes"]:
            col = columns[(L, n)]
            directions[L] = directions.get(L, 0) + sign * r[L] * col / np.linalg.norm(col)
        write_vector(VECTORS / f"{name}.gguf", directions)
        print("wrote", VECTORS / f"{name}.gguf")


if __name__ == "__main__":
    main()
