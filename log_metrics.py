#!/usr/bin/env python3
import csv
import os
import sys
import time

LOG_FILE = "cluster_performance.csv"
CHART_FILE = "speedup_curve.png"

# Check for visualization library
try:
import matplotlib.pyplot as plt
HAS_MATPLOTLIB = True
except ImportError:
HAS_MATPLOTLIB = False

def log_session(nodes_count, network_sec, compute_sec, total_sec):
"""Appends execution telemetry to a persistent CSV log file"""
file_exists = os.path.isfile(LOG_FILE)
with open(LOG_FILE, mode="a", newline="") as f:
writer = csv.writer(f)
if not file_exists:
# Column headers for tracking performance metrics across multiple runs
writer.writerow(["Timestamp", "Active_Nodes", "Network_Time_Sec", "Compute_Time_Sec", "Total_Time_Sec"])
timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
writer.writerow([timestamp, nodes_count, f"{network_sec:.4f}", f"{compute_sec:.4f}", f"{total_sec:.4f}"])
print(f"📊 Telemetry logged securely to '{LOG_FILE}'")

def generate_chart():
"""Reads historical log data and compiles a visual Speedup Curve chart"""
if not HAS_MATPLOTLIB:
print("⚠️ Matplotlib not found. Skipping PNG chart generation.")
return

# Parse logged metrics
nodes = []
total_times = []
with open(LOG_FILE, mode="r") as f:
reader = csv.DictReader(f)
for row in reader:
nodes.append(int(row["Active_Nodes"]))
total_times.append(float(row["Total_Time_Sec"]))

if not nodes:
return

# Base calculations assuming the first single-node log is our baseline
baseline_time = total_times[0]
actual_speedup = [baseline_time / t for t in total_times]
ideal_speedup = [n for n in nodes]

# Render line chart configurations
plt.figure(figsize=(8, 5))
plt.plot(nodes, actual_speedup, marker='o', color='#007AFF', linewidth=2, label='Actual Parallel Performance')
plt.plot(nodes, ideal_speedup, linestyle='--', color='#FF9500', label='Ideal Scaling (Linear)')
plt.title('iPhone Cluster Distributed Parallel Speedup Curve')
plt.xlabel('Number of Compute Nodes (PC + iPhones)')
plt.ylabel('Speedup Factor (x-times Faster)')
plt.xticks(list(set(nodes)))
plt.grid(True, linestyle=':', alpha=0.6)
plt.legend()
plt.savefig(CHART_FILE, dpi=300)
plt.close()
print(f"📈 Performance visualization exported successfully to '{CHART_FILE}'")

if __name__ == "__main__":
# Expects arguments passed down sequentially from the automated Bash wrapper
if len(sys.argv) < 5:
# Dummy or testing values fallback if run manually without args
log_session(2, 0.3210, 0.1420, 0.4630)
else:
log_session(int(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]))
generate_chart()

