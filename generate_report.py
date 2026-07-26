#!/usr/bin/env python3
"""Generate a report from measured telemetry and verification results."""

import csv
import json
import os
import sys
import time

LOG_FILE = "cluster_performance.csv"
VERIFICATION_FILE = "verification_result.json"
REPORT_FILE = "FINAL_PROJECT_SUMMARY.md"


def load_runs():
    if not os.path.exists(LOG_FILE):
        raise FileNotFoundError(
            f"'{LOG_FILE}' is missing; run log_metrics.py with real run metrics first"
        )
    with open(LOG_FILE, mode="r", encoding="utf-8") as log_file:
        runs = list(csv.DictReader(log_file))
    if not runs:
        raise ValueError(f"'{LOG_FILE}' contains no measured runs")
    return runs


def load_verification():
    if not os.path.exists(VERIFICATION_FILE):
        return None
    with open(VERIFICATION_FILE, encoding="utf-8") as result_file:
        return json.load(result_file)


def measured_speedup(runs):
    baselines = [
        float(run["Total_Time_Sec"])
        for run in runs
        if int(run["Active_Nodes"]) == 1
    ]
    if not baselines:
        return None
    baseline = min(baselines)
    latest_total = float(runs[-1]["Total_Time_Sec"])
    return baseline / latest_total if latest_total > 0 else None


def compile_markdown_report():
    print("📋 Compiling final project summary report...")
    runs = load_runs()
    verification = load_verification()
    speedup = measured_speedup(runs)

    with open(REPORT_FILE, "w", encoding="utf-8") as report:
        report.write("# Distributed Compute Cluster Execution Report\n\n")
        report.write(f"**Generated:** {time.strftime('%Y-%m-%d %H:%M:%S')}  \n")
        report.write(
            "**Protocol:** Length-prefixed JSON over trusted LAN/WireGuard paths\n\n"
        )

        report.write("## Measured telemetry\n\n")
        report.write(
            "| Run | Nodes | Network transfer (s) | Slowest worker compute (s) "
            "| Total wall time (s) |\n"
        )
        report.write("| ---: | ---: | ---: | ---: | ---: |\n")
        for index, run in enumerate(runs, 1):
            report.write(
                f"| {index} | {int(run['Active_Nodes'])} | "
                f"{float(run['Network_Time_Sec']):.6f} | "
                f"{float(run['Compute_Time_Sec']):.6f} | "
                f"{float(run['Total_Time_Sec']):.6f} |\n"
            )

        report.write("\n## Scaling\n\n")
        if speedup is None:
            report.write(
                "No one-node baseline has been measured, so a speedup claim "
                "cannot yet be calculated.\n"
            )
        else:
            report.write(
                f"The latest measured run is **{speedup:.2f}×** the fastest "
                "recorded one-node baseline.\n"
            )

        report.write("\n## Numerical verification\n\n")
        if verification is None:
            report.write("Verification was not run for the latest output.\n")
        elif verification.get("passed"):
            report.write(
                "✅ The complete output matches the locally recomputed "
                "deterministic matrix product.\n\n"
            )
            report.write(
                f"- Matrix size: {int(verification['matrix_size'])} × "
                f"{int(verification['matrix_size'])}\n"
            )
            report.write(
                f"- Maximum absolute error: "
                f"{float(verification['max_absolute_error']):.3e}\n"
            )
            report.write(
                f"- Mean absolute error: "
                f"{float(verification['mean_absolute_error']):.3e}\n"
            )
        else:
            report.write(
                "❌ The latest output did not pass numerical verification.\n"
            )
            if verification.get("error"):
                report.write(f"\nReason: {verification['error']}\n")

    print(f"📄 Report generated from measured data: '{REPORT_FILE}'")


def main():
    try:
        compile_markdown_report()
    except (KeyError, OSError, TypeError, ValueError, json.JSONDecodeError) as exc:
        print(f"❌ Could not generate report: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
