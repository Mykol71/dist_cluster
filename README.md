# dist_cluster

`dist_cluster` is an experimental distributed matrix-computing project that coordinates smartphone worker nodes over a secure VPN. It combines Bash-based orchestration with Python compute workers to explore low-cost, internet-routed parallel execution.

## Overview

The project investigates whether personal mobile devices can be organized into a practical compute cluster for matrix workloads. Rather than positioning this as a replacement for dedicated HPC hardware, the repository focuses on orchestration, networking behavior, and correctness across distributed workers.

## Architecture

The cluster is organized into three layers:

- **Orchestration (Bash):** shell scripts coordinate remote setup, deployment, and worker startup.
- **Network (VPN):** encrypted connectivity is established via a Tailscale/WireGuard-style mesh.
- **Compute (Python):** worker processes handle matrix partitions and return partial results to a master node.

## Adaptive Optimization

Before distributed execution, the workflow profiles network conditions and adjusts transfer behavior. The current scripts include latency-aware buffering logic intended to reduce network overhead under different link conditions.

## Execution Workflow

1. **Deploy:** `deploy_cluster.sh` checks node connectivity, prepares remote environments, and syncs project files.
2. **Profile and run:** `run_cluster.sh` performs latency-oriented prechecks and launches distributed workers.
3. **Compute:** workers process assigned matrix chunks and send results back to the coordinator.
4. **Verify/report:** verification and logging scripts are used to check output integrity and capture run metrics.

## Key Findings

- Distributed execution across consumer devices is technically feasible.
- End-to-end performance is often constrained by network latency and transfer overhead.
- Communication costs can limit linear scaling even when local computation is fast.

## Notes and Limitations

- This repository should be read as a prototype/experiment, not a benchmark-validated performance study.
- Hardware-equivalence claims (for example, smartphone clusters vs. desktop GPUs) should be treated as conceptual unless backed by reproducible measurements from this repo.
- Results are sensitive to network quality, device heterogeneity, and runtime setup.

## Tech Stack

- **Bash** for orchestration and remote automation
- **Python** for distributed compute, verification, and reporting
- **SSH** for remote process execution
- **Tailscale / WireGuard** for secure node connectivity

## Future Improvements

- Add reproducible benchmark methodology and published result sets
- Document end-to-end setup and execution steps in more detail
- Improve fault tolerance/retry handling for unstable nodes
- Add clearer architecture and data-flow diagrams

## Presentation Outline (for talk/slides)

### Slide 1 — Title and Overview
- Over-the-Internet distributed compute cluster concept
- Smartphone-based worker pool coordinated by Bash and Python

### Slide 2 — Problem and Constraints
- Single-device memory and compute limits for larger workloads
- Need for secure connectivity across geographically distributed nodes

### Slide 3 — System Architecture
- Orchestration layer (Bash)
- Secure network layer (VPN)
- Compute layer (Python workers)

### Slide 4 — Adaptive Optimization
- Latency variability as a core bottleneck
- Pre-run network profiling and transfer tuning

### Slide 5 — Execution Workflow
- Deploy, profile, run workers, aggregate, verify

### Slide 6 — Findings and Practical Takeaways
- Feasibility demonstrated
- Network overhead as the dominant scaling constraint
- Experimental value in distributed-systems learning
