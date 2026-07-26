# Reproducible Run Commands

This document provides exact, copy-paste commands to reproduce a full cluster run,
from environment setup through report generation. Use LAN IPs for local-network nodes,
or WireGuard IPs for remote nodes.

---

## Environment Assumptions

| Variable       | Example value       | Description                          |
|----------------|---------------------|--------------------------------------|
| `MASTER_IP`    | `192.168.1.33` or `10.42.0.1` | Master IP reachable by each worker (LAN or WireGuard) |
| `WORKER_A_IP`  | `192.168.1.44` or `10.42.0.2` | IP of worker node A (`workerA`) |
| `WORKER_B_IP`  | `192.168.1.55` or `10.42.0.3` | IP of worker node B (`workerB`) |
| `SSH_USER`     | `mobile`            | SSH user on worker nodes             |
| `REMOTE_DIR`   | `/app` or `~/dist_cluster` | Working directory on worker nodes |
| `ALLOW_MASTER_WILDCARD_BIND` | `1` | Required only when mixing LAN-local and VPN-only workers in one run |

Add the worker aliases to `~/.ssh/config` on the orchestrator for convenience:

```
Host workerA
    HostName 10.42.0.2
    User mobile
    IdentityFile ~/.ssh/dist_cluster_id

Host workerB
    HostName 10.42.0.3
    User mobile
    IdentityFile ~/.ssh/dist_cluster_id
```

---

## Step 1 — Validate Connectivity

Before any run, confirm every node is reachable over the same private path (LAN or VPN):

```bash
# Ping check
ping -c 4 10.42.0.2   # workerA
ping -c 4 10.42.0.3   # workerB

# SSH check
ssh workerA echo "workerA reachable"
ssh workerB echo "workerB reachable"
```

Expected output: four successful ping replies and the echo strings printed without errors.

---

## Step 2 — Deploy Dependencies to Worker Nodes

Run once per session (or after a factory reset / fresh iSH install):

```bash
bash deploy_cluster.sh
```

Expected output: `✅ [workerA] Fully deployed and ready...` for each node.

`deploy_cluster.sh` defaults to `/app` on Linux/iPhone workers and `~/dist_cluster` on macOS workers. Export `REMOTE_PROJECT_DIR` first if you want every worker to use a custom path.

---

## Step 3 — Launch the Cluster

```bash
bash run_cluster.sh
```

The script will:
1. Profile network latency and set an optimal chunk buffer.
2. Start remote worker processes (rank 1, rank 2 …) via SSH in the background.
3. Launch rank 0 locally.
4. Wait for all ranks to finish.
5. Run verification, log metrics, and generate the report.

---

## Step 4 — Smoke Test

Run a smaller deterministic matrix multiplication to verify transport and computation:

```bash
REMOTE_DIR="/app" # use "~/dist_cluster" on macOS workers unless you exported REMOTE_PROJECT_DIR

ssh workerA "cd $REMOTE_DIR && \
  MASTER_ADDR=10.42.0.1 MASTER_PORT=8080 WORLD_SIZE=3 RANK=1 MATRIX_SIZE=32 \
  python3 train_dist.py" &

ssh workerB "cd $REMOTE_DIR && \
  MASTER_ADDR=10.42.0.1 MASTER_PORT=8080 WORLD_SIZE=3 RANK=2 MATRIX_SIZE=32 \
  python3 train_dist.py" &

MASTER_ADDR=10.42.0.1 MASTER_PORT=8080 WORLD_SIZE=3 RANK=0 MATRIX_SIZE=32 \
  python3 src/train_dist.py

wait
```

Expected output: rank 0 writes `matrix_output.csv` and `run_metrics.json`; each worker
reports its assigned row count and measured compute time.

---

## Step 5 — Generate Report Artifacts

After a successful run, generate the final summary report:

```bash
# Verify numerical correctness
python3 verify_output.py

# Log performance metrics
python3 log_metrics.py run_metrics.json

# Generate final Markdown report
python3 generate_report.py
```

Output file: `FINAL_PROJECT_SUMMARY.md`  
Telemetry CSV: `cluster_performance.csv`

---

## Full Command Sequence (Copy-Paste)

```bash
# 1. Connectivity checks
ping -c 4 10.42.0.2 && ping -c 4 10.42.0.3
ssh workerA echo "OK" && ssh workerB echo "OK"

# 2. Deploy
bash deploy_cluster.sh

# 3. Run cluster (includes latency profiling and report generation)
bash run_cluster.sh

# 4. View report
cat FINAL_PROJECT_SUMMARY.md
```

---

## Troubleshooting

| Symptom                              | Likely cause                  | Fix                                         |
|--------------------------------------|-------------------------------|---------------------------------------------|
| `ssh: connect to host … timed out`   | Private network path unavailable (LAN or WireGuard) | Verify LAN routing/subnet reachability or reconnect WireGuard on the node |
| Worker cannot reach rank 0 after startup | Local/VPN path mismatch | Re-run with explicit `MASTER_IP`, confirm worker/host IP family mapping (`192.*`, `10.*`, `172.*`), and set `ALLOW_MASTER_WILDCARD_BIND=1` when mixing LAN-local and VPN-only workers |
| `Permission denied (publickey)`      | Key not deployed              | Re-run `ssh-copy-id` (see `ssh_hardening.html`) |
| Worker exits immediately             | Python dependency missing     | Re-run `bash deploy_cluster.sh`             |
| High latency / stall during run      | Poor network conditions       | Check `latency_benchmark_samples.html` |
| `FINAL_PROJECT_SUMMARY.md` empty     | `cluster_performance.csv` missing | Ensure `log_metrics.py` ran successfully |

mgreen@mykol.com
