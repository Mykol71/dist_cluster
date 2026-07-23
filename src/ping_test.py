#!/usr/bin/env python3
import os
import subprocess
import sys

def get_average_ping(host):
"""Pings a remote node over the VPN and extracts the average round-trip time (RTT)"""
try:
# Runs a 3-count ping test with a 2-second strict timeout limit
# Works across both Linux and macOS hosts
cmd = ["ping", "-c", "3", "-W", "2", host]
result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
if result.returncode != 0:
return None
# Parse out the average latency from the ping trailing summary line
for line in result.stdout.split("\n"):
if "rtt" in line or "round-trip" in line:
# Extracts the 'avg' metric out of: rtt min/avg/max/mdev = 45.21/48.12/51.04/2.11 ms
parts = line.split("=")[1].strip().split("/")
return float(parts[1])
except Exception:
return None

if __name__ == "__main__":
# Expects the target iPhone's IP or alias as an execution argument
if len(sys.argv) < 2:
print("1048576") # Default to standard 1MB buffer if no target host is given
sys.exit(0)
target_node = sys.argv[1]
avg_latency = get_average_ping(target_node)
if avg_latency is None:
# Connection is degraded or offline; use large 2MB buffer safely
print("2097152")
elif avg_latency < 30.0:
# Fast local link (e.g., Wi-Fi / LAN) -> Use responsive 256KB chunks
print("262144")
elif avg_latency < 100.0:
# Standard link -> Use stable 1MB chunks
print("1048576")
else:
# High latency link (e.g., Cellular/LTE) -> Use heavy 2MB chunk blocks
print("2097152")  
