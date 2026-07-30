# dist_cluster — Docker Deployment Guide

This directory contains a container-driven implementation of the node
installation and configuration described in the top-level `README.md`.
Docker replaces the need to manually install Python 3, numpy, and
configure SSH on each worker node, and works identically on **macOS**,
**Windows**, and **Linux** hosts.

---

## How it works

| Component | Purpose |
|---|---|
| `Dockerfile.worker` | Worker node image (Python 3 + numpy + OpenSSH server) |
| `Dockerfile.master` | Master node image (Python 3 + numpy + OpenSSH client + all scripts) |
| `entrypoint-worker.sh` | Injects your SSH public key and starts the SSH daemon inside the worker container |
| `docker-compose.yml` | Local test cluster — one master + two workers on a shared bridge network |
| `setup_keys.sh` | Generates the SSH keypair used between master and workers |

---

## Option A — Local test cluster (single machine, all OSes)

Spin up a fully functional cluster on one machine using Docker Compose.
No WireGuard config required for single-machine use, no SSH key config — everything is wired automatically.

```bash
# 1. Generate SSH keypair for the cluster (run once)
bash docker/setup_keys.sh

# 2. Build images and start master + 2 worker containers
docker compose -f docker/docker-compose.yml up --build -d

# 3. Deploy Python dependencies and sync source files to workers
docker compose -f docker/docker-compose.yml exec master \
  bash deploy_cluster.sh

# 4. Run the distributed workload
docker compose -f docker/docker-compose.yml exec master \
  bash run_cluster.sh

# 5. Tear down
docker compose -f docker/docker-compose.yml down
```

---

## Option B — Multi-machine cluster (real distributed deployment)

Each physical machine (Mac, Windows PC, Linux box) runs one Docker
container.  The machines communicate over a **WireGuard** VPN mesh.

### Step 1 — Prepare every node

Install Docker and WireGuard using the operating system vendor's supported
installation process. Build `Dockerfile.worker` on worker machines and
`Dockerfile.master` on the master.

### Step 2 — Connect all nodes to WireGuard

On each node, configure and bring up the WireGuard interface:

```bash
# Linux / macOS — configure /etc/wireguard/wg0.conf, then:
sudo wg-quick up wg0

# Windows — add a tunnel via the WireGuard app or import a .conf file
```

Note each node's WireGuard IP (set in your wg0.conf `[Interface]` Address):

```bash
# Linux
ip addr show wg0 | grep 'inet '

# macOS / Linux (via wireguard-tools)
wg show

# Windows
wg show
```

### Step 3 — Configure SSH on the master

Add worker node aliases to `~/.ssh/config` on the master:

```
Host worker1
    HostName <worker1-wireguard-ip>
    Port 2222
    User root
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no

Host worker2
    HostName <worker2-wireguard-ip>
    Port 2222
    User root
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
```

Copy the master's public key to each worker:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub -p 2222 root@<worker-wireguard-ip>
# or, if ssh-copy-id is not available:
cat ~/.ssh/id_ed25519.pub | ssh -p 2222 root@<worker-wireguard-ip> \
  "cat >> /root/.ssh/authorized_keys"
```

### Step 4 — Update `WORKER_NODES` in the cluster scripts

Edit `deploy_cluster.sh` and `run_cluster.sh` to reference your worker
host aliases:

```bash
WORKER_NODES=("worker1" "worker2")
```

### Step 5 — Deploy and run

From the master node (inside the master container, or natively if you
ran `--role master`):

```bash
bash deploy_cluster.sh
bash run_cluster.sh
```

---

## Prerequisites handled automatically by Docker

| README prerequisite | How Docker handles it |
|---|---|
| Python 3 on all nodes | Built into the container image |
| `numpy` (and optionally `mlx`) | Installed via `pip` in the Dockerfile |
| SSH key-based auth on workers | `entrypoint-worker.sh` injects the public key at container start |
| Homebrew / system Python on macOS | Not needed — Docker provides the environment |

## Prerequisites still required on the host

| Prerequisite | Why |
|---|---|
| WireGuard | VPN connectivity between machines requires host-level networking |
| Docker Engine / Docker Desktop | The container runtime itself |

---

## Customisation

### Add more workers

Add services to `docker-compose.yml` following the `worker1`/`worker2`
pattern, then update `WORKER_NODES` in the master `command:` block.

### Use `mlx` on Apple Silicon

Change the pip install line in `Dockerfile.worker`:

```dockerfile
RUN pip install --no-cache-dir numpy mlx
```

### Persist output files

The master service in `docker-compose.yml` mounts `../output` for CSV
and report files.  Create the directory first:

```bash
mkdir -p output
```
