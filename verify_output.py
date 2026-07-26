#!/usr/bin/env python3
"""Verify the complete distributed matrix product against local ground truth."""

import json
import os
import sys
import time

from src.matrix_model import (
    DEFAULT_MATRIX_SEED,
    DEFAULT_MATRIX_SIZE,
    build_matrix_a,
    build_matrix_b,
)

try:
    import numpy as np
except ImportError:
    print("❌ Verification requires numpy.", file=sys.stderr)
    sys.exit(1)


CSV_FILENAME = os.getenv("MATRIX_OUTPUT_FILE", "matrix_output.csv")
METRICS_FILENAME = os.getenv("RUN_METRICS_FILE", "run_metrics.json")
VERIFICATION_FILENAME = os.getenv(
    "VERIFICATION_RESULT_FILE",
    "verification_result.json",
)
ABSOLUTE_TOLERANCE = float(os.getenv("VERIFY_ATOL", "1e-8"))
RELATIVE_TOLERANCE = float(os.getenv("VERIFY_RTOL", "1e-9"))


def write_verification_result(result):
    with open(VERIFICATION_FILENAME, "w", encoding="utf-8") as result_file:
        json.dump(result, result_file, indent=2, sort_keys=True)
        result_file.write("\n")


def load_run_configuration():
    if not os.path.exists(METRICS_FILENAME):
        return DEFAULT_MATRIX_SIZE, DEFAULT_MATRIX_SEED

    with open(METRICS_FILENAME, encoding="utf-8") as metrics_file:
        metrics = json.load(metrics_file)
    return int(metrics["matrix_size"]), int(metrics["matrix_seed"])


def main():
    print("==================================================")
    print("🔍 Cluster Result Verification Engine")
    print("==================================================")

    if not os.path.exists(CSV_FILENAME):
        print(f"❌ Error: '{CSV_FILENAME}' not found. Run ./run_cluster.sh first.")
        return 1

    try:
        matrix_size, matrix_seed = load_run_configuration()
        print(
            f"📂 Loading {matrix_size}x{matrix_size} output from "
            f"'{CSV_FILENAME}'..."
        )
        cluster_result = np.loadtxt(CSV_FILENAME, delimiter=",", dtype=np.float64)

        expected_shape = (matrix_size, matrix_size)
        if cluster_result.shape != expected_shape:
            raise ValueError(
                f"output shape is {cluster_result.shape}; expected {expected_shape}"
            )
        if not np.isfinite(cluster_result).all():
            raise ValueError("output contains NaN or infinite values")

        print("💻 Recomputing the deterministic matrix product locally...")
        verification_start = time.perf_counter()
        matrix_a = build_matrix_a(matrix_size, matrix_seed, np)
        matrix_b = build_matrix_b(matrix_size, matrix_seed, np)
        expected_result = matrix_a.dot(matrix_b)
        verification_sec = time.perf_counter() - verification_start

        absolute_error = np.abs(cluster_result - expected_result)
        max_absolute_error = float(absolute_error.max(initial=0.0))
        mean_absolute_error = float(absolute_error.mean())
        passed = bool(
            np.allclose(
                cluster_result,
                expected_result,
                rtol=RELATIVE_TOLERANCE,
                atol=ABSOLUTE_TOLERANCE,
            )
        )
        result = {
            "passed": passed,
            "matrix_size": matrix_size,
            "matrix_seed": matrix_seed,
            "max_absolute_error": max_absolute_error,
            "mean_absolute_error": mean_absolute_error,
            "absolute_tolerance": ABSOLUTE_TOLERANCE,
            "relative_tolerance": RELATIVE_TOLERANCE,
            "verification_sec": verification_sec,
        }
        write_verification_result(result)

        print(f"⏱️ Ground-truth calculation took {verification_sec:.4f} seconds.")
        print(f"📏 Maximum absolute error: {max_absolute_error:.3e}")
        print("--------------------------------------------------")
        if not passed:
            print("❌ FAILED: Distributed output differs from ground truth.")
            return 1

        print("✅ PASSED: Every matrix element matches deterministic ground truth.")
        print(f"🎉 Verified the complete {matrix_size}x{matrix_size} result.")
        return 0
    except (KeyError, OSError, TypeError, ValueError, json.JSONDecodeError) as exc:
        write_verification_result({"passed": False, "error": str(exc)})
        print(f"❌ FAILED: {exc}")
        return 1
    finally:
        print("==================================================")


if __name__ == "__main__":
    sys.exit(main())
