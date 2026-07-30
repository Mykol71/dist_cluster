#!/usr/bin/env python3
"""Tests for latency parsing and conservative link classification."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.ping_test import (
    BUFFER_1_MB,
    BUFFER_2_MB,
    BUFFER_256_KB,
    classify_network,
    parse_ping_output,
)


def expect(profile, status, buffer_size):
    if profile["status"] != status or profile["buffer_size"] != buffer_size:
        raise AssertionError(profile)


def main():
    linux = """10 packets transmitted, 10 received, 0% packet loss, time 9000ms
rtt min/avg/max/mdev = 1.000/22.500/30.000/5.250 ms"""
    macos = """10 packets transmitted, 10 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 20.000/55.000/90.000/20.000 ms"""
    if parse_ping_output(linux) != (22.5, 5.25, 0.0):
        raise AssertionError("Linux ping parsing failed")
    if parse_ping_output(macos) != (55.0, 20.0, 0.0):
        raise AssertionError("macOS ping parsing failed")

    expect(classify_network(29.9, 9.9, 0), "proceed", BUFFER_256_KB)
    expect(classify_network(30, 10, 0), "proceed", BUFFER_1_MB)
    expect(classify_network(79.9, 40, 0), "proceed", BUFFER_1_MB)
    expect(classify_network(80, 20, 0), "caution", BUFFER_2_MB)
    expect(classify_network(120, 50, 0.5), "caution", BUFFER_2_MB)
    expect(classify_network(150, 50, 0), "caution", BUFFER_2_MB)
    expect(classify_network(151, 1, 0), "abort", None)
    expect(classify_network(20, 1, 2.1), "abort", None)
    expect(classify_network(20, 1, 1.0), "abort", None)


if __name__ == "__main__":
    main()
