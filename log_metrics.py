#!/usr/bin/env python3
"""Append measured cluster runtime data to the performance history."""

import argparse
import csv
import json
import os
import sys
import time

LOG_FILE = "cluster_performance.csv"
CHART_FILE = "speedup_curve.png"
REQUIRED_METRICS = (
    "nodes_count",
    "network_sec",
    "compute_sec",
    "total_sec",
)

try:
    import matplotlib.pyplot as plt
except ImportError:
    plt = None


def load_metrics(metrics_file):
    with open(metrics_file, encoding="utf-8") as source:
        metrics = json.load(source)

    missing = [field for field in REQUIRED_METRICS if field not in metrics]
    if missing:
        raise ValueError(f"metrics file is missing: {', '.join(missing)}")

    normalized = {
        "nodes_count": int(metrics["nodes_count"]),
        "network_sec": float(metrics["network_sec"]),
        "compute_sec": float(metrics["compute_sec"]),
        "total_sec": float(metrics["total_sec"]),
    }
    if normalized["nodes_count"] < 2:
        raise ValueError("nodes_count must include a master and at least one worker")
    if any(normalized[field] < 0 for field in REQUIRED_METRICS[1:]):
        raise ValueError("runtime measurements cannot be negative")
    return normalized


def log_session(metrics):
    file_exists = os.path.isfile(LOG_FILE)
    with open(LOG_FILE, mode="a", newline="", encoding="utf-8") as log_file:
        writer = csv.writer(log_file)
        if not file_exists:
            writer.writerow(
                [
                    "Timestamp",
                    "Active_Nodes",
                    "Network_Time_Sec",
                    "Compute_Time_Sec",
                    "Total_Time_Sec",
                ]
            )
        writer.writerow(
            [
                time.strftime("%Y-%m-%d %H:%M:%S"),
                metrics["nodes_count"],
                f"{metrics['network_sec']:.6f}",
                f"{metrics['compute_sec']:.6f}",
                f"{metrics['total_sec']:.6f}",
            ]
        )
    print(f"📊 Measured telemetry appended to '{LOG_FILE}'")


def generate_chart():
    if plt is None:
        print("⚠️ Matplotlib not found. Skipping PNG chart generation.")
        return

    nodes = []
    total_times = []
    with open(LOG_FILE, mode="r", encoding="utf-8") as log_file:
        for row in csv.DictReader(log_file):
            nodes.append(int(row["Active_Nodes"]))
            total_times.append(float(row["Total_Time_Sec"]))

    one_node_times = [
        total_time
        for node_count, total_time in zip(nodes, total_times)
        if node_count == 1
    ]
    if not one_node_times:
        print(
            "ℹ️ No one-node baseline is logged; skipping the speedup chart "
            "instead of inventing a baseline."
        )
        return

    baseline_time = min(one_node_times)
    actual_speedup = [baseline_time / duration for duration in total_times]
    ideal_speedup = nodes

    plt.figure(figsize=(8, 5))
    plt.plot(
        nodes,
        actual_speedup,
        marker="o",
        color="#007AFF",
        linewidth=2,
        label="Measured speedup",
    )
    plt.plot(
        nodes,
        ideal_speedup,
        linestyle="--",
        color="#FF9500",
        label="Ideal linear scaling",
    )
    plt.title("Distributed Cluster Speedup")
    plt.xlabel("Number of nodes")
    plt.ylabel("Speedup factor")
    plt.xticks(sorted(set(nodes)))
    plt.grid(True, linestyle=":", alpha=0.6)
    plt.legend()
    plt.savefig(CHART_FILE, dpi=300)
    plt.close()
    print(f"📈 Performance chart saved to '{CHART_FILE}'")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "metrics_file",
        nargs="?",
        default="run_metrics.json",
        help="JSON metrics emitted by rank 0",
    )
    args = parser.parse_args()

    try:
        metrics = load_metrics(args.metrics_file)
        log_session(metrics)
        generate_chart()
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
        print(f"❌ Could not log runtime metrics: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
