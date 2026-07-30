#!/usr/bin/env python3
"""Profile a link and select a safe receive chunk size."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys


BUFFER_256_KB = 256 * 1024
BUFFER_1_MB = 1024 * 1024
BUFFER_2_MB = 2 * 1024 * 1024


def parse_ping_output(output: str) -> tuple[float, float, float]:
    """Return average RTT, mdev/stddev, and packet-loss percentage."""
    loss_match = re.search(r"([\d.]+)%\s+packet loss", output)
    timing_match = re.search(
        r"(?:rtt|round-trip)[^=]*=\s*"
        r"([\d.]+)/([\d.]+)/([\d.]+)/([\d.]+)\s*ms",
        output,
    )
    if not loss_match or not timing_match:
        raise ValueError("ping output did not contain loss and RTT summaries")
    return (
        float(timing_match.group(2)),
        float(timing_match.group(4)),
        float(loss_match.group(1)),
    )


def classify_network(avg_ms: float, mdev_ms: float, packet_loss: float) -> dict:
    """Classify using the most conservative matching tier."""
    profile = {
        "avg_latency_ms": avg_ms,
        "mdev_ms": mdev_ms,
        "packet_loss_percent": packet_loss,
    }

    if packet_loss > 2:
        return profile | {
            "status": "abort",
            "action": "Abort; unstable link",
            "buffer_size": None,
        }
    if avg_ms > 150:
        return profile | {
            "status": "abort",
            "action": "Abort; re-profile after fixing latency",
            "buffer_size": None,
        }
    # The proceed tiers require 0% loss below 80 ms and <1% up to 150 ms.
    # Values in the unspecified 1–2% gap fail closed.
    if packet_loss >= 1:
        return profile | {
            "status": "abort",
            "action": "Abort; packet loss exceeds accepted proceed tiers",
            "buffer_size": None,
        }
    if avg_ms < 30 and mdev_ms < 10 and packet_loss == 0:
        return profile | {
            "status": "proceed",
            "action": "Proceed, 256 KB chunks",
            "buffer_size": BUFFER_256_KB,
        }
    if avg_ms < 80 and mdev_ms <= 40 and packet_loss == 0:
        return profile | {
            "status": "proceed",
            "action": "Proceed, 1 MB chunks",
            "buffer_size": BUFFER_1_MB,
        }
    return profile | {
        "status": "caution",
        "action": "Proceed cautiously, 2 MB chunks",
        "buffer_size": BUFFER_2_MB,
    }


def profile_host(host: str) -> dict:
    count = int(os.getenv("PING_COUNT", "10"))
    if count < 1:
        raise ValueError("PING_COUNT must be positive")
    command = ["ping", "-c", str(count)]
    if sys.platform == "darwin":
        command.extend(["-W", "2000"])
    else:
        command.extend(["-W", "2"])
    command.append(host)

    try:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=max(10, count * 3),
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(f"ping failed for {host}: {error}") from error

    try:
        avg_ms, mdev_ms, packet_loss = parse_ping_output(result.stdout)
    except ValueError as error:
        detail = result.stderr.strip() or "no parseable ping summary"
        raise RuntimeError(f"could not profile {host}: {detail}") from error
    return classify_network(avg_ms, mdev_ms, packet_loss) | {"host": host}


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: ping_test.py HOST", file=sys.stderr)
        return 2
    try:
        profile = profile_host(sys.argv[1])
    except (RuntimeError, ValueError) as error:
        print(error, file=sys.stderr)
        return 2
    print(json.dumps(profile, separators=(",", ":")))
    if profile["status"] == "abort":
        print(f"{profile['host']}: {profile['action']}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
