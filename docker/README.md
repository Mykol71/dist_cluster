# Local Docker Cluster

This directory contains the files required to run a reproducible local cluster
with one master and two SSH workers.

## Required files

| Component | Purpose |
|---|---|
| `Dockerfile.master` | Python, NumPy, SSH client, and cluster scripts |
| `Dockerfile.worker` | Python, NumPy, and OpenSSH worker image |
| `docker-compose.yml` | Master and two-worker local network |
| `entrypoint-worker.sh` | Installs the authorized key and starts SSH |
| `setup_keys.sh` | Creates the ignored SSH keypair used by Compose |
| `.gitignore` | Prevents generated private keys from being committed |

## Run

```bash
bash docker/setup_keys.sh
docker compose -f docker/docker-compose.yml up --build -d
docker compose -f docker/docker-compose.yml exec master bash deploy_cluster.sh
docker compose -f docker/docker-compose.yml exec master bash run_cluster.sh
docker compose -f docker/docker-compose.yml down
```

Generated matrices, metrics, and reports are persisted in the top-level
`output/` directory.

To change the local worker count, add or remove worker services in
`docker-compose.yml` and update the master service's `WORKER_NODES`
environment value.
