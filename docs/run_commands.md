# Reproducible Run Commands

This document provides exact, copy-paste commands to reproduce a full cluster run,
from environment setup through report generation. Replace VPN IP placeholders with
your actual Tailscale/WireGuard addresses.

---

## Environment Assumptions

| Variable       | Example value       | Description                          |
|----------------|---------------------|--------------------------------------|
| `MASTER_IP`    | `100.11.22.33`      | VPN IP of the orchestrator machine   |
| `WORKER_A_IP`  | `100.11.22.44`      | VPN IP of worker node A (`workerA`)  |
| `WORKER_B_IP`  | `100.11.22.55`      | VPN IP of worker node B (`workerB`)  |
| `SSH_USER`     | `mobile`            | SSH user on worker nodes             |
| `REMOTE_DIR`   | `/app` or `~/dist_cluster` | Working directory on worker nodes |

Add the worker aliases to `~/.ssh/config` on the orchestrator for convenience:

```
Host workerA
    HostName 100.11.22.44
    User mobile
    IdentityFile ~/.ssh/dist_cluster_id

Host workerB
    HostName 100.11.22.55
    User mobile
    IdentityFile ~/.ssh/dist_cluster_id
```

---

## Step 1 — Validate Connectivity

Before any run, confirm every node is reachable over the VPN:

```bash
# Ping check
ping -c 4 100.11.22.44   # workerA
ping -c 4 100.11.22.55   # workerB

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

Expected output: `✅ [iphoneA] Fully deployed and ready...` for each node.

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

Run a minimal distributed smoke test (simple `all_sum`) to verify comms before heavy workloads:

```bash
ssh workerA "cd /app && \
  MASTER_ADDR=100.11.22.33 MASTER_PORT=8080 WORLD_SIZE=3 RANK=1 \
  python3 src/train_dist.py" &

ssh workerB "cd /app && \
  MASTER_ADDR=100.11.22.33 MASTER_PORT=8080 WORLD_SIZE=3 RANK=2 \
  python3 src/train_dist.py" &

MASTER_ADDR=100.11.22.33 MASTER_PORT=8080 WORLD_SIZE=3 RANK=0 \
  python3 src/train_dist.py

wait
```

Expected output: each rank prints its synchronized `all_sum` result.  
Example (rank 0): `Rank 0 synchronized data: [6. 12. 18.]`

---

## Step 5 — Generate Report Artifacts

After a successful run, generate the final summary report:

```bash
# Verify numerical correctness
python3 verify_output.py

# Log performance metrics
python3 log_metrics.py 3 0.321 0.142 0.463

# Generate final Markdown report
python3 generate_report.py
```

Output file: `FINAL_PROJECT_SUMMARY.md`  
Telemetry CSV: `cluster_performance.csv`

---

## Full Command Sequence (Copy-Paste)

```bash
# 1. Connectivity checks
ping -c 4 100.11.22.44 && ping -c 4 100.11.22.55
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
| `ssh: connect to host … timed out`   | VPN not connected             | Re-connect Tailscale/WireGuard on the node  |
| `Permission denied (publickey)`      | Key not deployed              | Re-run `ssh-copy-id` (see `docs/ssh_hardening.md`) |
| Worker exits immediately             | Python dependency missing     | Re-run `bash deploy_cluster.sh`             |
| High latency / stall during run      | Poor network conditions       | Check `docs/latency_benchmark_samples.md` decision table |
| `FINAL_PROJECT_SUMMARY.md` empty     | `cluster_performance.csv` missing | Ensure `log_metrics.py` ran successfully |
