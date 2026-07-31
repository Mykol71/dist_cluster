# NumPy LLM Use Case: Tiny Transformer Inference

`src/numpy_llm_demo.py` is a compact, runnable use case for the numerical core
of an autoregressive language model. It is designed for learning, smoke tests,
and validating the local Python/NumPy environment before moving to MLX-LM or a
production inference runtime.

It is **not a pretrained model**. Its seeded weights make every run repeatable,
but the generated words are illustrative rather than semantically meaningful.

## What it demonstrates

| LLM component | NumPy operation |
|---|---|
| Token and position embeddings | Array lookup and addition |
| Query, key, value projections | Matrix multiplication (`@`) |
| Causal self-attention | Masked score matrix plus stable softmax |
| Residual block and MLP | Vector addition, ReLU, matrix multiplication |
| Autoregressive decoding | Recompute logits and append the selected token |

The attention mask prevents each position from viewing future input tokens,
which is the core decoder-only constraint used by GPT-style models.

## Run locally

```bash
python3 -m pip install -r requirements.txt
python3 src/numpy_llm_demo.py \
  --prompt "numpy makes tensor math clear" \
  --max-new-tokens 8
```

Expected output reports the token count, vocabulary size, and a deterministic
generated sequence. Unknown words map to the beginning-of-sequence token so
that arbitrary prompts still exercise the whole numerical path.

## Verify

```bash
python3 tests/test_numpy_llm_demo.py
```

## When to use it

Use this example when you need to explain or validate Transformer tensor flow
without model downloads, GPU dependencies, or Apple-Silicon-only tooling. For
real text generation on Apple Silicon, use the repository's MLX-LM pipeline in
[`AI_LLM_Use_Case.md`](AI_LLM_Use_Case.md); MLX-LM supplies trained weights,
tokenization, model architecture, and optimized execution.
