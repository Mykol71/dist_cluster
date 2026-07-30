#!/usr/bin/env python3
"""End-to-end localhost test for the rank-0/worker TCP protocol."""

import json
import os
import socket
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "src" / "train_dist.py"


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def main() -> None:
    port = free_port()
    with tempfile.TemporaryDirectory() as temporary_directory:
        temp = Path(temporary_directory)
        base_environment = os.environ | {
            "MASTER_ADDR": "127.0.0.1", "MASTER_PORT": str(port), "WORLD_SIZE": "3",
            "MATRIX_SIZE": "16", "OUTPUT_FILENAME": str(temp / "matrix_output.csv"),
            "METRICS_FILENAME": str(temp / "cluster_metrics.json"),
        }
        master = subprocess.Popen([sys.executable, str(SCRIPT)], env=base_environment | {"RANK": "0"})
        workers = [
            subprocess.Popen([sys.executable, str(SCRIPT)], env=base_environment | {"RANK": str(rank)})
            for rank in (1, 2)
        ]
        assert master.wait(timeout=30) == 0
        for worker in workers:
            assert worker.wait(timeout=30) == 0
        rows = (temp / "matrix_output.csv").read_text().strip().splitlines()
        assert len(rows) == 16 and all(len(row.split(",")) == 16 for row in rows)
        metrics = json.loads((temp / "cluster_metrics.json").read_text())
        assert metrics["total_seconds"] > 0 and metrics["compute_seconds"] >= 0


if __name__ == "__main__":
    main()
