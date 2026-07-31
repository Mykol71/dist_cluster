#!/usr/bin/env python3
"""A dependency-light, decoder-only Transformer inference walkthrough.

This intentionally tiny model shows the tensor operations behind a single
autoregressive LLM request using only NumPy. It uses deterministic demonstration
weights, not pretrained weights, so its text is illustrative rather than useful.
"""

from __future__ import annotations

import argparse

import numpy as np


VOCABULARY = (
    "<bos>", "numpy", "makes", "tensor", "math", "clear", "for", "small",
    "language", "models", "distributed", "systems", "need", "fast", "local",
    "inference", "and", "testing", ".",
)
TOKEN_TO_ID = {token: index for index, token in enumerate(VOCABULARY)}


def softmax(values: np.ndarray) -> np.ndarray:
    """Compute a stable softmax along the final axis."""
    shifted = values - values.max(axis=-1, keepdims=True)
    exponentials = np.exp(shifted)
    return exponentials / exponentials.sum(axis=-1, keepdims=True)


class TinyDecoder:
    """One attention block sized for understandable local experimentation."""

    def __init__(self, seed: int = 2026, width: int = 24, max_tokens: int = 32):
        rng = np.random.default_rng(seed)
        scale = 1 / np.sqrt(width)
        vocab_size = len(VOCABULARY)
        self.max_tokens = max_tokens
        self.token_embedding = rng.normal(0, scale, (vocab_size, width))
        self.position_embedding = rng.normal(0, scale, (max_tokens, width))
        self.query = rng.normal(0, scale, (width, width))
        self.key = rng.normal(0, scale, (width, width))
        self.value = rng.normal(0, scale, (width, width))
        self.output = rng.normal(0, scale, (width, width))
        self.mlp_in = rng.normal(0, scale, (width, width * 2))
        self.mlp_out = rng.normal(0, scale, (width * 2, width))
        self.unembedding = rng.normal(0, scale, (width, vocab_size))

    def logits(self, token_ids: list[int]) -> np.ndarray:
        if not token_ids or len(token_ids) > self.max_tokens:
            raise ValueError(f"token count must be between 1 and {self.max_tokens}")
        ids = np.asarray(token_ids, dtype=np.int64)
        hidden = self.token_embedding[ids] + self.position_embedding[np.arange(len(ids))]
        query, key, value = hidden @ self.query, hidden @ self.key, hidden @ self.value
        scores = query @ key.T / np.sqrt(hidden.shape[-1])
        scores += np.triu(np.full(scores.shape, -np.inf), k=1)
        attended = softmax(scores) @ value
        hidden = hidden + attended @ self.output
        hidden = hidden + np.maximum(0, hidden @ self.mlp_in) @ self.mlp_out
        return hidden[-1] @ self.unembedding

    def generate(self, token_ids: list[int], new_tokens: int) -> list[int]:
        generated = list(token_ids)
        for _ in range(new_tokens):
            generated.append(int(np.argmax(softmax(self.logits(generated)))))
        return generated


def tokenize(prompt: str) -> list[int]:
    words = prompt.lower().replace(".", " .").split()
    return [TOKEN_TO_ID.get(word, TOKEN_TO_ID["<bos>"]) for word in words] or [TOKEN_TO_ID["<bos>"]]


def detokenize(token_ids: list[int]) -> str:
    words = [VOCABULARY[token_id] for token_id in token_ids if token_id != TOKEN_TO_ID["<bos>"]]
    return " ".join(words).replace(" .", ".")


def main() -> None:
    parser = argparse.ArgumentParser(description="Run a tiny NumPy decoder-only Transformer.")
    parser.add_argument("--prompt", default="numpy makes tensor math clear")
    parser.add_argument("--max-new-tokens", type=int, default=8)
    args = parser.parse_args()
    if args.max_new_tokens < 0:
        parser.error("--max-new-tokens must be non-negative")
    model = TinyDecoder()
    prompt_ids = tokenize(args.prompt)
    if len(prompt_ids) + args.max_new_tokens > model.max_tokens:
        parser.error(f"prompt plus generated tokens must be at most {model.max_tokens}")
    result_ids = model.generate(prompt_ids, args.max_new_tokens)
    print(f"Prompt tokens: {len(prompt_ids)}")
    print(f"Next-token vocabulary size: {model.logits(prompt_ids).size}")
    print(f"Generated: {detokenize(result_ids)}")


if __name__ == "__main__":
    main()
