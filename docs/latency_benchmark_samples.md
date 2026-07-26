# Latency Benchmark Sample Outputs

This document explains the latency recommendations emitted by `src/ping_test.py`.
The script runs three ICMP probes, parses average round-trip time, and prints one receive
buffer size in bytes for `run_cluster.sh`.

---

## 1. Ping-Style Summary

The operating-system `ping` command produces a summary like this:

```
PING 10.42.0.2 (workerA) 56 bytes of data — 3 packets
rtt min/avg/max/mdev = 18.42/32.17/71.83/14.55 ms

PING 10.42.0.3 (workerB) 56 bytes of data — 3 packets
rtt min/avg/max/mdev = 22.10/45.63/118.24/27.38 ms
```

**Field meanings:**
| Field  | Description |
|--------|-------------|
| `min`  | Best observed round-trip time |
| `avg`  | Average round-trip time used by `ping_test.py` |
| `max`  | Worst-case spike; large values indicate LTE/cellular jitter |
| `mdev` | Mean deviation — high values (>20 ms) suggest unstable routing |

---

## 2. Script Output

`ping_test.py` intentionally prints only the recommended receive buffer size so the
orchestrator can consume it directly:

```text
262144    # average latency below 30 ms
1048576   # average latency from 30 ms through 99.999 ms
2097152   # average latency at least 100 ms, or the node is unreachable
```

`run_cluster.sh` probes every configured worker and uses the largest recommendation,
which protects the run from tuning below the needs of its slowest path.

---

## 3. Interpretation Notes and Scaling Decisions

### Healthy baseline (Wi-Fi, low contention)

```
rtt min/avg/max/mdev = 12.00/20.00/35.00/8.00 ms
```

- `avg < 30 ms` and `mdev < 10 ms`: comfortable for standard chunk sizes.
- Recommended `BUFFER_SIZE`: 256 KB (`262144` bytes).
- Small receive calls keep the framed protocol responsive.

### Moderate degradation (LTE / shared Wi-Fi)

```
rtt min/avg/max/mdev = 20.00/55.00/120.00/30.00 ms
```

- `avg 30–99 ms`, `mdev 15–40 ms`: increase receive size to amortize overhead.
- Recommended `BUFFER_SIZE`: 1 MB (`1048576` bytes).
- Expect ~10–20 % slowdown vs. single-device baseline due to sync wait time.

### Severe degradation (cellular roaming / congested network)

```
rtt min/avg/max/mdev = 80.00/180.00/450.00/95.00 ms  packet_loss=3.2%
```

- `avg >= 100 ms`: the script recommends a 2 MB receive size.
- Packet loss is not parsed by `ping_test.py`; investigate it manually when runs stall.
- Consider switching nodes to a better network and re-profiling.

### Decision table

| Average latency | Script recommendation |
|-----------------|-----------------------|
| < 30 ms         | 256 KB (`262144`)     |
| 30–99 ms        | 1 MB (`1048576`)      |
| >= 100 ms       | 2 MB (`2097152`)      |
| Probe failure   | 2 MB fallback         |

---

## 4. Running the Benchmark Manually

```bash
# Profile a single node (outputs buffer recommendation in bytes)
python3 ./src/ping_test.py iphoneA

# Profile all nodes
for node in iphoneA iphoneB; do
  printf '%s: ' "$node"
  python3 ./src/ping_test.py "$node"
done
```

Results are also collected automatically at the start of each `run_cluster.sh` execution.
See [`run_commands.html`](run_commands.html) for the full workflow.

mgreen@mykol.com
