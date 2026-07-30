#!/usr/bin/env python3
"""Validate that the distributed output has the expected finite matrix shape."""
import os
import sys

import numpy as np

MATRIX_SIZE = int(os.getenv("MATRIX_SIZE", "600"))
CSV_FILENAME = os.getenv("OUTPUT_FILENAME", "matrix_output.csv")


def main() -> None:
    if not os.path.exists(CSV_FILENAME):
        raise SystemExit(f"output file '{CSV_FILENAME}' not found")
    matrix = np.loadtxt(CSV_FILENAME, delimiter=",")
    if matrix.shape != (MATRIX_SIZE, MATRIX_SIZE):
        raise SystemExit(f"invalid matrix shape {matrix.shape}; expected {(MATRIX_SIZE, MATRIX_SIZE)}")
    if not np.isfinite(matrix).all():
        raise SystemExit("output contains non-finite values")
    matrix_a = np.random.default_rng(2026).random((MATRIX_SIZE, MATRIX_SIZE))
    matrix_b = np.random.default_rng(2027).random((MATRIX_SIZE, MATRIX_SIZE))
    expected = matrix_a @ matrix_b
    max_delta = float(np.max(np.abs(matrix - expected)))
    if not np.allclose(matrix, expected, rtol=0, atol=5.1e-4):
        raise SystemExit(f"output differs from the deterministic reference (max delta {max_delta:.6g})")
    print(f"PASSED: {MATRIX_SIZE}x{MATRIX_SIZE} output matches the reference (max delta {max_delta:.6g}).")


if __name__ == "__main__":
    main()
