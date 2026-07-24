# Distributed Network Cluster Notes

## Overview

This document describes a distributed compute experiment that coordinates multiple devices over a secure network.  
Instead of transferring raw VRAM contents across devices, the practical pattern is to split model/workload state across nodes (for example, tensor/model/data parallel strategies) and synchronize intermediate results.

> ⚠️ Important: Over-the-Internet distributed training/inference is usually limited by network latency and throughput.  
> This architecture is best for experimentation and learning, not for peak performance compared with local high-bandwidth interconnects.

---

## High-Level Architecture

```text
[ Server / Master Node ]  (Primary machine running orchestration script)
            |
   (Secure VPN Tunnel)
   (e.g., Tailscale / WireGuard)
            |
      +-----+-----+
      |           |
 [ iPhone A ] [ iPhone B ]
 (worker node) (worker node)
```

---

## Step 1 — Establish a Secure Network Tunnel

All nodes must be reachable on a common private network.

- Install a secure mesh VPN (e.g., Tailscale or WireGuard) on:
  - the orchestrator machine
  - each worker device
- Verify each node has a stable private VPN IP.
- Validate connectivity (`ping`, then `ssh`) before starting distributed jobs.

---

## Step 2 — Bash Orchestrator (Master Control)

The host script starts worker processes remotely via SSH and launches rank 0 locally.

```bash
#!/usr/bin/env bash
set -euo pipefail

# VPN IP addresses (examples only)
MASTER_IP="100.11.22.33"
IPHONE_A_IP="100.11.22.44"
IPHONE_B_IP="100.11.22.55"

WORLD_SIZE=3   # total processes: rank 0 + two workers
PORT=8080

echo "Initializing distributed cluster..."

# 1) Start worker rank 1
ssh mobile@"$IPHONE_A_IP" \
  "cd /app && mx.distributed --world-size $WORLD_SIZE --rank 1 --master-addr $MASTER_IP --master-port $PORT python3 train_dist.py" &

# 2) Start worker rank 2
ssh mobile@"$IPHONE_B_IP" \
  "cd /app && mx.distributed --world-size $WORLD_SIZE --rank 2 --master-addr $MASTER_IP --master-port $PORT python3 train_dist.py" &

# 3) Start rank 0 on master
echo "Launching master process..."
mx.distributed --world-size "$WORLD_SIZE" --rank 0 --master-addr "$MASTER_IP" --master-port "$PORT" python3 train_dist.py

wait
echo "Distributed processing finished."
```

### SSH Notes

- Use key-based auth only (disable password auth where possible).
- Restrict SSH exposure to VPN interface.
- Prefer non-root users with minimal privileges.

---

## Step 3 — Worker Script (`train_dist.py`)

Each process initializes distributed communication and runs synchronized operations.

```python
import mlx.core as mx
import mlx.nn as nn  # kept for future model components

mx.distributed.init()

rank = mx.distributed.get_rank()
world_size = mx.distributed.get_world_size()

if rank == 0:
    print(f"Master node online. World size: {world_size}")

x = mx.array([1.0, 2.0, 3.0]) * (rank + 1)
sum_x = mx.distributed.all_sum(x)

print(f"Rank {rank} synchronized data: {sum_x}")
```

---

## Known Constraints and Risks

### 1) Network Bottleneck
- Device-local memory bandwidth is much higher than Internet links.
- Collective operations (`all_sum`, etc.) can become communication-bound quickly.

### 2) iOS Background Execution Limits
- iOS may suspend or terminate long-running/background terminal processes.
- Keep apps active and device power settings in mind during experiments.

### 3) Reliability
- WAN jitter/packet loss causes stragglers and unstable step time.
- Add retries, health checks, and timeout handling in orchestration scripts.

---

## Suggested Validation Workflow

1. Validate VPN connectivity for all nodes.
2. Validate SSH connectivity and command execution.
3. Run a latency/bandwidth probe script.
4. Run small distributed test (`all_sum` smoke test).
5. Scale workload gradually while logging:
   - network time
   - compute time
   - total wall-clock time

---

## Presentation Outline (Submission-Friendly)

### Slide 1 — Title
**Over-the-Internet Distributed Compute Cluster**  
Using Bash orchestration + secure VPN + Python distributed workers.

### Slide 2 — Problem
Single-device memory/compute limits for large matrix/model workloads.

### Slide 3 — Architecture
Master orchestrator, VPN mesh, remote worker ranks, synchronized collectives.

### Slide 4 — Optimization Idea
Adaptive chunk sizing / communication strategy based on measured latency.

### Slide 5 — Execution Flow
Deploy → profile network → launch ranks → compute → verify → report.

### Slide 6 — Results and Trade-offs
Speedup vs communication overhead, with Amdahl’s Law interpretation.

---

## Automated Summary Report Generator (`generate_report.py`)

Use a reporting script to compile telemetry into a final markdown report.

### Purpose
- Parse `cluster_performance.csv`
- Compute speedup metrics
- Emit `FINAL_PROJECT_SUMMARY.md`

### Recommended Quality Improvements
- Add argument parsing (`argparse`) for log/report paths.
- Validate CSV schema before reading.
- Handle malformed numeric fields with guarded parsing.
- Include min/avg/max latency and per-run variance.
- Add exit codes for CI usage.

---

## Pipeline Hook Example (`run_cluster.sh`)

Append post-run hooks:

```bash
# 4) Invoke logger and report generator
if [ -f "./log_metrics.py" ]; then
  python3 ./log_metrics.py "$WORLD_SIZE" "$MOCK_NET_TIME" "$MOCK_COMP_TIME" "$TOTAL_TIME"
fi

if [ -f "./generate_report.py" ]; then
  python3 ./generate_report.py
fi
```

---

## Expected Project Structure

```text
deploy_cluster.sh        # node provisioning and setup
run_cluster.sh           # orchestration and benchmark execution
verify_output.py         # numerical correctness checks
log_metrics.py           # telemetry logging and graph outputs
generate_report.py       # final markdown report generation
src/train_dist.py        # distributed compute entrypoint
src/ping_test.py         # network latency evaluation
```

---

## Source Quality Note

The original notes include mixed references (forums, social posts, slide sites, and generated narrative).  
For final academic/professional submission, prefer:

- official framework docs
- reproducible benchmarks
- primary technical references
- clearly versioned tooling and environment details

---

## Next Actions

- [ ] Add SSH hardening guide (`docs/ssh_hardening.md`)
- [ ] Add latency benchmark script output samples
- [ ] Add reproducible run command examples
- [ ] Add failure-handling and retry strategy in orchestration
- [ ] Add a concise README version of this architecture
