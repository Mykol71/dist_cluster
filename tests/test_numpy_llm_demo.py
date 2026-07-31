#!/usr/bin/env python3
"""Executable checks for the educational NumPy LLM use case."""

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    command = [sys.executable, str(ROOT / "src" / "numpy_llm_demo.py"), "--max-new-tokens", "3"]
    first = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=True).stdout
    second = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=True).stdout
    if first != second:
        raise AssertionError("expected seeded NumPy generation to be deterministic")
    for expected in ("Prompt tokens: 5", "Next-token vocabulary size: 19", "Generated:"):
        if expected not in first:
            raise AssertionError(f"missing {expected!r} in output: {first}")


if __name__ == "__main__":
    main()
