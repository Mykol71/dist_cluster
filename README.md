# Distributed Compute Cluster

An experimental over-the-Internet distributed compute cluster that coordinates multiple devices (iPhones/mobile nodes) via a VPN mesh. Workloads are split across nodes, processed in parallel, and results are synchronized using Python-based collective operations.

> ⚠️ This project is designed for **experimentation and learning**. Over-the-Internet links introduce latency overhead that limits linear speedup — see [Known Constraints](#known-constraints).

---

## Architecture

```text
[ Master Node (PC/Mac) ]
       |
  VPN Tunnel (Tailscale / WireGuard)
       |
  +----+----+
  |         |
[iPhone A] [iPhone B]
(RANK 1)  (RANK 2)
```

- **Orchestration layer:** Bash scripts manage SSH connections, environment setup, and process lifecycle.
- **Network layer:** Mesh VPN (Tailscale or WireGuard) provides encrypted peer-to-peer connectivity with stable private IPs.
- **Compute layer:** Python worker processes exchange split workload chunks and synchronize via `all_sum` collectives.
- **Adaptive tuning:** Network latency is profiled before each run to set an optimal packet buffer size.

---

## Quick Start

### Prerequisites

- Tailscale or WireGuard installed and connected on all devices.
- SSH key-based auth configured (see [`docs/ssh_hardening.md`](docs/ssh_hardening.md)).
- Python 3 + `numpy` (and optionally `mlx`) on all nodes.

### 1. Deploy dependencies to worker nodes

```bash
bash deploy_cluster.sh
```

### 2. Run the cluster

```bash
bash run_cluster.sh
```

### 3. View the report

```bash
cat FINAL_PROJECT_SUMMARY.md
```

For detailed step-by-step commands including smoke tests and troubleshooting, see [`docs/run_commands.md`](docs/run_commands.md).

---

## File Structure

```
deploy_cluster.sh            # Node provisioning: connectivity, packages, file sync
run_cluster.sh               # Orchestration: latency profile, spawn workers, cleanup
verify_output.py             # Numerical correctness checks
log_metrics.py               # Telemetry logging and CSV output
generate_report.py           # Final Markdown report generation
src/train_dist.py            # Distributed compute entrypoint (runs on each rank)
src/ping_test.py             # Network latency probe (returns buffer recommendation)
docs/ssh_hardening.md        # SSH security hardening guide
docs/latency_benchmark_samples.md  # Example benchmark outputs and interpretation
docs/run_commands.md         # Reproducible copy-paste run commands
NOTES.md                     # Extended architecture notes and context
```

---

## Known Constraints

| Constraint | Description |
|------------|-------------|
| **Network bottleneck** | Internet latency is much higher than local interconnects; collective ops become communication-bound quickly. |
| **iOS background limits** | iOS may suspend background terminal sessions; keep the screen active during runs. |
| **WAN jitter** | Packet loss and jitter cause straggler ranks; the orchestrator retries SSH connections and aborts on persistent failure. |
| **Amdahl's Law** | Communication overhead grows with node count; speedup tapers off beyond a small cluster size. |

---

## Documentation

| Document | Contents |
|----------|----------|
| [`docs/ssh_hardening.md`](docs/ssh_hardening.md) | Key-based auth, disable password auth, VPN firewall rules, fail2ban, audit logging |
| [`docs/latency_benchmark_samples.md`](docs/latency_benchmark_samples.md) | Sample ping/CSV output and scaling decision table |
| [`docs/run_commands.md`](docs/run_commands.md) | Step-by-step reproducible commands for the full workflow |
| [`NOTES.md`](NOTES.md) | Extended architecture notes, slide outline, and source quality notes |
