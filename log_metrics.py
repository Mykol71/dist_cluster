#!/usr/bin/env python3
"""Persist and chart cluster timing metrics."""
import csv
import os
import sys
import time

LOG_FILE = os.getenv("CLUSTER_LOG_FILE", "cluster_performance.csv")
CHART_FILE = os.getenv("CLUSTER_CHART_FILE", "speedup_curve.png")
try:
    import matplotlib.pyplot as plt
except ImportError:
    plt = None


def log_session(nodes_count, network_sec, compute_sec, total_sec):
    file_exists = os.path.isfile(LOG_FILE)
    with open(LOG_FILE, "a", newline="", encoding="utf-8") as file:
        writer = csv.writer(file)
        if not file_exists:
            writer.writerow(["Timestamp", "Active_Nodes", "Network_Time_Sec", "Compute_Time_Sec", "Total_Time_Sec"])
        writer.writerow([time.strftime("%Y-%m-%d %H:%M:%S"), nodes_count, f"{network_sec:.4f}", f"{compute_sec:.4f}", f"{total_sec:.4f}"])
    print(f"Telemetry logged to '{LOG_FILE}'")


def generate_chart():
    if plt is None:
        print("Matplotlib not installed; skipping chart generation.")
        return
    with open(LOG_FILE, newline="", encoding="utf-8") as file:
        rows = list(csv.DictReader(file))
    if not rows:
        return
    nodes = [int(row["Active_Nodes"]) for row in rows]
    total_times = [float(row["Total_Time_Sec"]) for row in rows]
    baseline = total_times[0]
    plt.figure(figsize=(8, 5))
    plt.plot(nodes, [baseline / value for value in total_times], marker="o", label="Actual")
    plt.plot(nodes, nodes, "--", label="Ideal")
    plt.xlabel("Number of compute nodes")
    plt.ylabel("Speedup")
    plt.grid(True, linestyle=":", alpha=0.6)
    plt.legend()
    plt.savefig(CHART_FILE, dpi=300)
    plt.close()
    print(f"Performance chart saved to '{CHART_FILE}'")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        raise SystemExit("usage: log_metrics.py NODES NETWORK_SECONDS COMPUTE_SECONDS TOTAL_SECONDS")
    log_session(int(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]))
    generate_chart()
