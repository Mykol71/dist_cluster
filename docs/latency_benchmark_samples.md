# Latency Benchmark Sample Outputs

This document contains realistic example outputs from the latency benchmark tooling
(`src/ping_test.py`) used to profile network conditions before launching the distributed
cluster. Use these samples to understand what healthy vs. degraded output looks like and
how to map results to scaling decisions.

---

## 1. Ping-Style Summary

The benchmark runs a sequence of ICMP/TCP probes and emits a one-line summary per node.

```
PING 100.11.22.44 (iphoneA) 56 bytes of data — 20 packets
rtt min/avg/max/mdev = 18.42/32.17/71.83/14.55 ms

PING 100.11.22.55 (iphoneB) 56 bytes of data — 20 packets
rtt min/avg/max/mdev = 22.10/45.63/118.24/27.38 ms
```

**Field meanings:**
| Field  | Description |
|--------|-------------|
| `min`  | Best-case one-way trip (wire conditions at their cleanest) |
| `avg`  | Expected per-message overhead in collective operations |
| `max`  | Worst-case spike; large values indicate LTE/cellular jitter |
| `mdev` | Mean deviation — high values (>20 ms) suggest unstable routing |

---

## 2. CSV Sample Snippet

The benchmark appends one row per probe to `cluster_latency.csv`:

```csv
timestamp,node,latency_ms,jitter_ms,packet_loss
2024-11-01T14:02:01Z,iphoneA,18.42,3.11,0.0
2024-11-01T14:02:02Z,iphoneA,21.05,2.83,0.0
2024-11-01T14:02:03Z,iphoneA,71.83,49.21,0.0
2024-11-01T14:02:04Z,iphoneA,19.74,1.89,0.0
2024-11-01T14:02:01Z,iphoneB,22.10,4.50,0.0
2024-11-01T14:02:02Z,iphoneB,118.24,96.14,0.0
2024-11-01T14:02:03Z,iphoneB,28.33,6.23,0.0
2024-11-01T14:02:04Z,iphoneB,44.91,16.58,5.0
```

**Column descriptions:**
| Column         | Description |
|----------------|-------------|
| `timestamp`    | ISO-8601 probe time |
| `node`         | SSH hostname or alias from `IPHONE_NODES` |
| `latency_ms`   | Round-trip time for this probe in milliseconds |
| `jitter_ms`    | Absolute difference from the previous probe (smoothed) |
| `packet_loss`  | Percentage of lost probes in the last 20-probe window |

---

## 3. Interpretation Notes and Scaling Decisions

### Healthy baseline (Wi-Fi, low contention)

```
rtt min/avg/max/mdev = 12.00/20.00/35.00/8.00 ms
```

- `avg < 30 ms` and `mdev < 10 ms`: comfortable for standard chunk sizes.
- Recommended `BUFFER_SIZE`: 256 KB (`262144` bytes).
- Collective operations (`all_sum`) complete in < 2 ms of overhead per step.

### Moderate degradation (LTE / shared Wi-Fi)

```
rtt min/avg/max/mdev = 20.00/55.00/120.00/30.00 ms
```

- `avg 30–80 ms`, `mdev 15–40 ms`: increase chunk size to amortize overhead.
- Recommended `BUFFER_SIZE`: 1 MB (`1048576` bytes).
- Expect ~10–20 % slowdown vs. single-device baseline due to sync wait time.

### Severe degradation (cellular roaming / congested network)

```
rtt min/avg/max/mdev = 80.00/180.00/450.00/95.00 ms  packet_loss=3.2%
```

- `avg > 100 ms` or `packet_loss > 2 %`: distributed run may stall or fail.
- Recommended action: abort run, switch nodes to better network, re-profile.
- Do not attempt large matrix workloads — stragglers will dominate wall time.

### Decision table

| avg latency | mdev   | packet_loss | Recommended action            |
|-------------|--------|-------------|-------------------------------|
| < 30 ms     | < 10   | 0 %         | Proceed, 256 KB chunks        |
| 30–80 ms    | 10–40  | 0 %         | Proceed, 1 MB chunks          |
| 80–150 ms   | > 40   | < 1 %       | Proceed cautiously, 2 MB chunks |
| > 150 ms    | any    | any         | Abort; re-profile after fix   |
| any         | any    | > 2 %       | Abort; unstable link          |

---

## 4. Running the Benchmark Manually

```bash
# Profile a single node (outputs buffer recommendation in bytes)
python3 ./src/ping_test.py iphoneA

# Profile all nodes and write CSV
for node in iphoneA iphoneB; do
  python3 ./src/ping_test.py "$node" >> cluster_latency.csv
done
```

Results are also collected automatically at the start of each `run_cluster.sh` execution.
See [`docs/run_commands.md`](run_commands.md) for the full workflow.

mgreen@mykol.com
