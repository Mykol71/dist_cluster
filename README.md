Part 1: Project Presentation Slides Outline
--


slide 1: Title & Overview
--
- Title: Over-the-Internet VRAM Pooling and Distributed Compute Cluster
- Subtitle: Leveraging Bash Process Orchestration and iOS Unified Memory Architectures
- Core Concept: A cost-effective, parallel matrix computing engine utilizing personal smartphones as distributed worker nodes across a secure VPN tunnel.

slide 2: The Problem & Constraints
--
- The Hardware Bottleneck: Massive AI model runs and heavy matrix multiplication fail on single consumer devices due to Out-Of-Memory (OOM) VRAM limits.
- The Unconventional Resource: iPhones use a Unified Memory Architecture (UMA) where the high-bandwidth Apple Silicon GPU and CPU share the same system memory.
- The Solution: Aggregating this fragmented hardware using a secure, internet-routed cluster pipeline.

slide 3: System Architecture
--
- Orchestration Layer: A lightweight, parallelized Bash scripting framework handling authentication, remote processes, and environment setups.
- Network Layer: Mesh VPN (Tailscale/WireGuard) creating an encrypted peer-to-peer network tunnel using static virtual IPs.
- Compute Engine: Multi-threaded distributed Python endpoints using raw socket servers to exchange split matrix configurations.

```mermaid
graph TB
    subgraph OL["Orchestration Layer"]
        ORCH["🖥️ Master Node\n(deploy_cluster.sh / run_cluster.sh)"]
    end
    subgraph NL["Network Layer"]
        VPN["🔒 Mesh VPN\n(Tailscale / WireGuard)\nEncrypted P2P Tunnel"]
    end
    subgraph CL["Compute Layer"]
        W1["📱 iPhone A\nWorker Rank 1\nApple Silicon UMA"]
        W2["📱 iPhone B\nWorker Rank 2\nApple Silicon UMA"]
    end
    ORCH <-->|"SSH + Matrix Chunks"| VPN
    VPN <-->|"Private VPN IP"| W1
    VPN <-->|"Private VPN IP"| W2
```

slide 4: Adaptive Optimization (The Key Innovation)
--
- The Network Bottleneck: Internet routing introduces erratic ping latencies that can paralyze traditional parallel cluster configurations.
- Dynamic Packet Tuning: An automated network ping test executes right before data distribution.
- Low Latency (Wi-Fi): Drops down to responsive 256KB packet chunks.
- High Latency (Cellular/LTE): Automatically scales to large 2MB streaming data blocks to maximize throughput.

```mermaid
flowchart LR
    START([🚀 Start Cluster]) --> PING["📡 ping_test.py\nprobe each node"]
    PING --> CHECK{Latency?}
    CHECK -->|"Low ≤ ~20ms\n(Wi-Fi)"| SMALL["256 KB\npacket chunks"]
    CHECK -->|"High > ~20ms\n(Cellular / LTE)"| LARGE["2 MB\nstreaming blocks"]
    SMALL --> DIST["Distribute work\nto worker ranks"]
    LARGE --> DIST
    DIST --> COMPUTE["Workers compute\ndot-product loops"]
    COMPUTE --> AGG["Master aggregates\nall_sum collective"]
    AGG --> DONE([✅ Result])
```

slide 5: Technical Execution Workflow
--
- Deployment: deploy_cluster.sh uses parallel background tasks to sync code, detect operating systems (iSH Alpine vs Native iOS), and configure dependencies automatically.
- Profiling: run_cluster.sh benchmarks connection latencies and starts remote background worker ranks over SSH.
- Calculation: Workers stream data chunks, process heavy dot-product row loops inside their hardware memory pools, and return calculations.
- Verification: The master node aggregates chunks, renders progress bars, saves a final unified .csv report, and engages mathematical delta checkers.

```mermaid
sequenceDiagram
    participant M as 🖥️ Master Node
    participant A as 📱 iPhone A (Rank 1)
    participant B as 📱 iPhone B (Rank 2)

    Note over M,B: Phase 1 — Deploy
    M->>A: deploy_cluster.sh: sync src/, install deps
    M->>B: deploy_cluster.sh: sync src/, install deps
    A-->>M: ✅ environment ready
    B-->>M: ✅ environment ready

    Note over M,B: Phase 2 — Profile
    M->>A: ping_test.py (latency probe)
    M->>B: ping_test.py (latency probe)
    A-->>M: latency / buffer size
    B-->>M: latency / buffer size
    M->>M: set OPTIMAL_BUFFER

    Note over M,B: Phase 3 — Compute
    M->>A: SSH: start worker rank 1
    M->>B: SSH: start worker rank 2
    M->>M: launch rank 0 locally
    A-->>M: matrix chunk result
    B-->>M: matrix chunk result

    Note over M,B: Phase 4 — Verify & Report
    M->>M: verify_output.py (delta check)
    M->>M: log_metrics.py (telemetry)
    M->>M: generate_report.py → cluster_performance.csv
```

slide 6: Key Findings & Performance Scaling
--
- Compute vs. Network Cost: iPhone hardware handles local matrix multiplication instantly, but internet bandwidth limits linear speedup scaling.
- Amdahl's Law in Action: The project illustrates how a slower communication layer introduces parallel overhead, demonstrating real-world high-performance computing (HPC) constraints.


Notes:
--
- There are approximately 1.52 billion active iPhone users worldwide.
- To match the raw compute and VRAM footprint of a single NVIDIA RTX 3090 (35.6 FP16 TFLOPS, 24GB VRAM), you would need a cluster of roughly 15 to 20 iPhone 15 Pro Max devices.
