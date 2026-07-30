# Executable MLX-LM Pipeline Inference

This project includes `run_llm_cluster.sh`, an executable workflow for
pipeline-parallel text generation with MLX-LM on Apple Silicon Macs.

> This is separate from the portable NumPy matrix workflow. MLX-LM requires
> Apple Silicon and does not run in the project's Linux Docker smoke cluster.
> The Python MLX workflow targets Macs, not iPhone terminal environments.

MLX-LM already performs model-aware sharding. In distributed mode,
`mlx_lm.chat --pipeline` uses `sharded_load`, assigns consecutive model layers
to pipeline ranks, and downloads only the converted weight files needed by each
rank. A custom `shard_model.py` is therefore neither required nor included.

## Requirements

On every participating Mac:

```bash
python3 -m pip install -r requirements-llm.txt
mlx_lm.chat --help
```

For remote execution:

- Passwordless SSH between the launch Mac and every host.
- The same Python/MLX-LM environment available on every host.
- A valid MLX hostfile.
- Ring-reachable IP addresses over LAN, WireGuard, or a configured Thunderbolt
  ring; alternatively, a JACCL hostfile for a supported Thunderbolt RDMA mesh.

See the official [MLX distributed communication guide](https://ml-explore.github.io/mlx/build/html/usage/distributed.html)
and [MLX-LM project](https://github.com/ml-explore/mlx-lm).

## Local executable check

Run two pipeline ranks on one Apple Silicon Mac:

```bash
bash run_llm_cluster.sh \
  --local-ranks 2 \
  --model mlx-community/Llama-3.2-3B-Instruct-4bit \
  --prompt "Explain pipeline parallelism in three sentences." \
  --max-tokens 128
```

The response is saved to `output/llm_response.txt`.

Use `--dry-run` to validate argument construction without MLX or model weights:

```bash
bash run_llm_cluster.sh --dry-run --local-ranks 2 --prompt "Hello"
```

## Remote ring workflow

Create an MLX ring hostfile. Each entry identifies the SSH alias and the IP on
which that rank participates in the ring:

```json
[
  {"ssh": "mac1", "ips": ["10.10.0.1"]},
  {"ssh": "mac2", "ips": ["10.10.0.2"]}
]
```

Then launch:

```bash
bash run_llm_cluster.sh \
  --hostfile cluster-ring.json \
  --backend ring \
  --model mlx-community/Llama-3.2-3B-Instruct-4bit \
  --prompt "Explain pipeline parallelism in three sentences." \
  --max-tokens 128
```

Before launch, the script applies the project's latency, jitter, and packet-loss
admission policy to every remote host. Any rejected link aborts before model
loading. Use `--skip-latency-check` only when ICMP is intentionally unavailable
and the transport has been validated separately.

## JACCL workflow

On supported Macs with a fully connected Thunderbolt RDMA mesh, generate a
JACCL hostfile using the official MLX helper:

```bash
mlx.distributed_config --verbose \
  --hosts mac1,mac2 \
  --over thunderbolt \
  --backend jaccl \
  --auto-setup \
  --output cluster-jaccl.json

bash run_llm_cluster.sh \
  --hostfile cluster-jaccl.json \
  --backend jaccl \
  --model mlx-community/Llama-3.2-3B-Instruct-4bit
```

Without `--prompt`, the workflow opens the interactive MLX-LM chat interface.

## What the launcher does

1. Validates arguments, hostfile, Apple Silicon, and MLX-LM commands.
2. Profiles remote links unless explicitly skipped.
3. Enables `MLX_METAL_FAST_SYNCH=1`.
4. Starts ranks through `mlx.launch`.
5. Runs `mlx_lm.chat --pipeline`, which performs model-aware pipeline sharding.
6. In noninteractive mode, broadcasts the prompt through the launcher and saves
   the combined response.

## Important constraints

| Constraint | Impact |
|---|---|
| Apple Silicon Macs | MLX-LM cannot run in the Linux Docker test cluster. |
| Model support | The selected MLX model must expose pipeline support. |
| Converted weights | Select an MLX-converted model with a safetensor index for efficient per-stage downloads. |
| First run | Each rank may download tokenizer metadata and its required weight files. |
| Network latency | Autoregressive pipeline stages communicate for every generated token. |
| Performance | Small models may be faster on one Mac; distribution primarily helps models constrained by memory. |

## Tests

The repository test validates the executable launch construction without
requiring MLX:

```bash
python3 tests/test_llm_workflow.py
```

Real inference requires Apple Silicon hardware and model access.
