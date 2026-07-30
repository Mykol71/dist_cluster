#!/usr/bin/env python3
"""Static executable test for the MLX-LM launcher workflow."""

import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main():
    result = subprocess.run(
        [
            "bash",
            str(ROOT / "run_llm_cluster.sh"),
            "--dry-run",
            "--local-ranks",
            "2",
            "--model",
            "mlx-community/test-model",
            "--prompt",
            "Hello",
            "--max-tokens",
            "16",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )
    output = result.stdout
    expected = [
        "mlx.launch",
        "--backend ring",
        "-n 2",
        "MLX_METAL_FAST_SYNCH=1",
        "mlx_lm.chat",
        "--pipeline",
        "mlx-community/test-model",
        "--max-tokens 16",
        "Prompt: Hello",
    ]
    missing = [value for value in expected if value not in output]
    if missing:
        raise AssertionError(f"dry-run output missing {missing}: {output}")

if __name__ == "__main__":
    main()
