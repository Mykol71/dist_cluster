#!/usr/bin/env python3
"""Generate a concise Markdown report from cluster telemetry."""
import csv
import os
import time

LOG_FILE = os.getenv("CLUSTER_LOG_FILE", "cluster_performance.csv")
REPORT_FILE = os.getenv("REPORT_FILE", "FINAL_PROJECT_SUMMARY.md")


def compile_markdown_report():
    if not os.path.exists(LOG_FILE):
        raise SystemExit(f"telemetry log '{LOG_FILE}' does not exist")
    with open(LOG_FILE, newline="", encoding="utf-8") as file:
        runs = list(csv.DictReader(file))
    if not runs:
        raise SystemExit("telemetry log is empty")
    baseline = float(runs[0]["Total_Time_Sec"])
    latest = float(runs[-1]["Total_Time_Sec"])
    speedup = baseline / latest if latest else 0.0
    with open(REPORT_FILE, "w", encoding="utf-8") as report:
        report.write("# Distributed Compute Cluster Execution Report\n\n")
        report.write(f"Generated: {time.strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        report.write("| Run | Nodes | Network (s) | Compute (s) | Total (s) |\n|---|---:|---:|---:|---:|\n")
        for index, run in enumerate(runs, 1):
            report.write(f"| {index} | {run['Active_Nodes']} | {float(run['Network_Time_Sec']):.4f} | {float(run['Compute_Time_Sec']):.4f} | {float(run['Total_Time_Sec']):.4f} |\n")
        report.write(f"\nLatest recorded speedup versus first run: **{speedup:.2f}×**.\n")
    print(f"Summary report saved to '{REPORT_FILE}'")


if __name__ == "__main__":
    compile_markdown_report()
