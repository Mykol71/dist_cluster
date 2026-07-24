#!/usr/bin/env python3
import subprocess
import sys


def get_average_ping(host):
    """Ping a remote node and return its average round-trip time in milliseconds."""
    try:
        result = subprocess.run(
            ["ping", "-c", "3", host],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return None
    except Exception:
        return None

    if result.returncode != 0:
        return None

    for line in result.stdout.splitlines():
        if "rtt" in line or "round-trip" in line:
            parts = line.split("=")[1].strip().split("/")
            return float(parts[1])

    return None


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("1048576")
        sys.exit(0)

    target_node = sys.argv[1]
    avg_latency = get_average_ping(target_node)
    if avg_latency is None:
        print("2097152")
    elif avg_latency < 30.0:
        print("262144")
    elif avg_latency < 100.0:
        print("1048576")
    else:
        print("2097152")
