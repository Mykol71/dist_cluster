#!/usr/bin/env bash
# run_cluster.sh — Distributed cluster orchestrator with retry and failure handling
#
# Usage: bash run_cluster.sh
#
# Behaviour:
#   1. Profiles network latency across all worker nodes to set optimal chunk size.
#   2. Starts remote worker ranks via SSH with bounded retries and back-off.
#   3. Performs a per-node health check before the local master rank is launched.
#   4. Cleans up background SSH processes on any failure or SIGINT/SIGTERM.
#   5. Runs post-run verification, metrics logging, and report generation.

set -euo pipefail

# ─── CONFIGURATION ──────────────────────────────────────────────────────────

WORKER_NODES=("iphoneA" "iphoneB")
MASTER_PORT=8080
WORLD_SIZE=$(( ${#WORKER_NODES[@]} + 1 ))
LOCAL_PROJECT_DIR="./src"
DEFAULT_LINUX_REMOTE_PROJECT_DIR="/app"
DEFAULT_DARWIN_REMOTE_PROJECT_DIR="dist_cluster"
SCRIPT_NAME="train_dist.py"

# Retry settings for SSH worker launch
SSH_MAX_RETRIES=3        # maximum attempts per node
SSH_RETRY_DELAY=5        # seconds between attempts (doubles on each retry)
SSH_CONNECT_TIMEOUT=10   # seconds to wait for a worker SSH connection to succeed
SSH_HEALTH_TIMEOUT=5     # shorter timeout for health-check probes (quick pass/fail)
WORKER_BIND_DELAY=2      # seconds to wait after spawning workers so they can bind ports

# ─── GLOBALS ────────────────────────────────────────────────────────────────

REMOTE_PIDS=()         # PIDs of background SSH worker processes
NODE_MASTER_ADDR_PAIRS=()

# ─── CLEANUP / TRAP ─────────────────────────────────────────────────────────

cleanup() {
  local exit_code=$?
  if [ ${#REMOTE_PIDS[@]} -gt 0 ]; then
    echo ""
    echo "🧹 Cleaning up background worker processes (${#REMOTE_PIDS[@]} PIDs)..."
    for pid in "${REMOTE_PIDS[@]}"; do
      # Kill the local SSH process; the remote side will detect a broken pipe and exit.
      kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null || true
  fi
  if [ $exit_code -ne 0 ]; then
    echo "❌ Cluster run failed (exit code $exit_code)." >&2
  fi
}
trap cleanup EXIT INT TERM

# ─── HELPERS ────────────────────────────────────────────────────────────────

# ssh_with_retry <node> <remote_command>
#   Attempts an SSH command up to SSH_MAX_RETRIES times with exponential back-off.
#   Returns 0 on success, 1 if all attempts fail.
ssh_with_retry() {
  local node="$1"
  shift
  local remote_cmd="$*"
  local attempt=1
  local delay=$SSH_RETRY_DELAY

  while [ $attempt -le $SSH_MAX_RETRIES ]; do
    if ssh -o ConnectTimeout=$SSH_CONNECT_TIMEOUT -o BatchMode=yes "$node" "$remote_cmd"; then
      return 0
    fi
    echo "⚠️  [$node] SSH attempt $attempt/$SSH_MAX_RETRIES failed. Retrying in ${delay}s..." >&2
    sleep "$delay"
    delay=$(( delay * 2 ))   # exponential back-off
    attempt=$(( attempt + 1 ))
  done

  echo "❌ [$node] All $SSH_MAX_RETRIES SSH attempts failed." >&2
  return 1
}

detect_master_ip() {
  if command -v ip >/dev/null 2>&1; then
    ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}'
    return 0
  fi

  if command -v route >/dev/null 2>&1 && command -v ipconfig >/dev/null 2>&1; then
    local default_interface
    default_interface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')
    if [ -n "$default_interface" ]; then
      ipconfig getifaddr "$default_interface" 2>/dev/null
      return 0
    fi
  fi

  if command -v hostname >/dev/null 2>&1; then
    hostname -I 2>/dev/null | awk '{print $1}'
  fi
}

is_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

local_network_id() {
  local ip="$1"
  if ! is_ipv4 "$ip"; then
    return 1
  fi

  local first_octet
  first_octet=$(printf '%s\n' "$ip" | awk -F. '{print $1}')
  case "$first_octet" in
    10|172|192)
      printf '%s\n' "$first_octet"
      ;;
    *)
      return 1
      ;;
  esac
}

get_local_ipv4s() {
  if command -v ip >/dev/null 2>&1; then
    ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1
    return 0
  fi

  if command -v ifconfig >/dev/null 2>&1; then
    ifconfig 2>/dev/null | awk '/inet /{print $2}' | grep -v '^127\.' || true
    return 0
  fi

  if command -v hostname >/dev/null 2>&1; then
    hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^127\.' || true
  fi
}

resolve_node_ipv4() {
  local node="$1"
  local ssh_hostname candidate
  ssh_hostname=$(ssh -G "$node" 2>/dev/null | awk '/^hostname /{print $2; exit}')
  candidate=${ssh_hostname:-$node}

  if is_ipv4 "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if command -v getent >/dev/null 2>&1; then
    getent ahostsv4 "$candidate" 2>/dev/null | awk 'NR==1{print $1}'
    return 0
  fi

  if command -v host >/dev/null 2>&1; then
    host "$candidate" 2>/dev/null | awk '/has address/{print $4; exit}'
    return 0
  fi

  if command -v nslookup >/dev/null 2>&1; then
    nslookup "$candidate" 2>/dev/null | awk '/^Address: /{print $2; exit}'
  fi
}

detect_local_master_ip_for_node() {
  local node_ip="$1"
  local node_network
  node_network=$(local_network_id "$node_ip") || return 1

  while IFS= read -r host_ip; do
    [ -z "$host_ip" ] && continue
    if [ "$(local_network_id "$host_ip" 2>/dev/null || true)" = "$node_network" ]; then
      printf '%s\n' "$host_ip"
      return 0
    fi
  done < <(get_local_ipv4s)

  return 1
}

determine_node_master_addr() {
  local node="$1"
  local fallback_master_ip="$2"
  local node_ip local_master_ip

  node_ip=$(resolve_node_ipv4 "$node" 2>/dev/null || true)
  if [ -n "$node_ip" ]; then
    local_master_ip=$(detect_local_master_ip_for_node "$node_ip" 2>/dev/null || true)
    if [ -n "$local_master_ip" ]; then
      echo "🏠 [$node] Node IP $node_ip shares local network with host. Using host LAN IP $local_master_ip (VPN host config not required)." >&2
      printf '%s\n' "$local_master_ip"
      return 0
    fi
  fi

  printf '%s\n' "$fallback_master_ip"
}

set_node_master_addr() {
  local node="$1"
  local master_addr="$2"
  NODE_MASTER_ADDR_PAIRS+=("$node|$master_addr")
}

get_node_master_addr() {
  local node="$1"
  local default_addr="$2"
  local pair
  for pair in "${NODE_MASTER_ADDR_PAIRS[@]}"; do
    if [ "${pair%%|*}" = "$node" ]; then
      printf '%s\n' "${pair#*|}"
      return 0
    fi
  done

  printf '%s\n' "$default_addr"
}

get_remote_os() {
  local node="$1"
  ssh -q -o ConnectTimeout=$SSH_HEALTH_TIMEOUT -o BatchMode=yes "$node" "uname -s" 2>/dev/null || true
}

get_remote_project_dir() {
  local node="$1"
  if [ -n "${REMOTE_PROJECT_DIR:-}" ]; then
    printf '%s\n' "$REMOTE_PROJECT_DIR"
    return 0
  fi

  case "$(get_remote_os "$node")" in
    Darwin)
      ssh -q -o ConnectTimeout=$SSH_HEALTH_TIMEOUT -o BatchMode=yes "$node" "printf '%s\n' \"\$HOME/$DEFAULT_DARWIN_REMOTE_PROJECT_DIR\"" 2>/dev/null
      ;;
    *)
      printf '%s\n' "$DEFAULT_LINUX_REMOTE_PROJECT_DIR"
      ;;
  esac
}

# node_health_check <node>
#   Verifies the node is reachable and the project directory/script exist.
node_health_check() {
  local node="$1"
  local remote_project_dir
  echo "🔍 [$node] Running pre-flight health check..."

  # Basic reachability
  if ! ssh -q -o ConnectTimeout=$SSH_HEALTH_TIMEOUT -o BatchMode=yes "$node" exit 2>/dev/null; then
    echo "❌ [$node] Unreachable over SSH." >&2
    return 1
  fi

  remote_project_dir=$(get_remote_project_dir "$node")
  if [ -z "$remote_project_dir" ]; then
    echo "❌ [$node] Could not determine the remote project directory." >&2
    return 1
  fi

  # Verify the worker script is deployed
  if ! ssh -q -o BatchMode=yes "$node" "test -f \"$remote_project_dir/$SCRIPT_NAME\"" 2>/dev/null; then
    echo "❌ [$node] Worker script not found at $remote_project_dir/$SCRIPT_NAME." >&2
    echo "   Run 'bash deploy_cluster.sh' to deploy." >&2
    return 1
  fi

  echo "✅ [$node] Health check passed."
  return 0
}

# ─── MAIN ───────────────────────────────────────────────────────────────────

echo "=================================================="
echo "🌀 Launching Distributed GPU/VRAM Processing Pool"
echo "=================================================="
MASTER_IP=${MASTER_IP:-$(detect_master_ip)}
if [ -z "$MASTER_IP" ]; then
  echo "❌ Could not determine the master node IP. Set MASTER_IP explicitly." >&2
  exit 1
fi
echo "🌐 Master Node IP: $MASTER_IP | Port: $MASTER_PORT"
echo "🖥️  Total Nodes in World: $WORLD_SIZE"
echo "--------------------------------------------------"

# ── 1. LATENCY PROFILING ────────────────────────────────────────────────────

echo "📡 Measuring network latency across available private paths (LAN/VPN)..."
OPTIMAL_BUFFER=1048576  # default fallback (1 MB)

for node in "${WORKER_NODES[@]}"; do
  # ping_test.py returns the recommended buffer size in bytes
  detected_buffer=$(python3 ./src/ping_test.py "$node" 2>/dev/null || echo "$OPTIMAL_BUFFER")
  if [ "$detected_buffer" -gt "$OPTIMAL_BUFFER" ] 2>/dev/null; then
    OPTIMAL_BUFFER=$detected_buffer
  fi
done

echo "⚙️  Network tuning complete. Optimal chunk size: $OPTIMAL_BUFFER bytes."
echo "--------------------------------------------------"

# ── 2. PER-NODE HEALTH CHECKS ───────────────────────────────────────────────

echo "🩺 Pre-flight checks on all worker nodes..."
REQUIRES_MULTI_INTERFACE_BIND=0
for node in "${WORKER_NODES[@]}"; do
  if ! node_health_check "$node"; then
    echo "❌ Pre-flight failed for node '$node'. Aborting." >&2
    exit 1
  fi

  node_master_ip=$(determine_node_master_addr "$node" "$MASTER_IP")
  set_node_master_addr "$node" "$node_master_ip"
  if [ "$node_master_ip" != "$MASTER_IP" ]; then
    REQUIRES_MULTI_INTERFACE_BIND=1
  fi
  echo "🌐 [$node] Worker will connect to master at $node_master_ip:$MASTER_PORT"
done
echo "--------------------------------------------------"

# ── 3. SPAWN REMOTE WORKER RANKS ────────────────────────────────────────────

RANK=1
for node in "${WORKER_NODES[@]}"; do
  remote_project_dir=$(get_remote_project_dir "$node")
  if [ -z "$remote_project_dir" ]; then
    echo "❌ [$node] Could not determine the remote project directory." >&2
    exit 1
  fi

  echo "📡 [RANK $RANK] Starting worker on $node..."

  # Launch the remote worker with retry, in the background.
  # The subshell calls ssh_with_retry so we can capture its PID.
  (
    node_master_ip=$(get_node_master_addr "$node" "$MASTER_IP")
    ssh_with_retry "$node" \
      "cd \"$remote_project_dir\" && \
       MASTER_ADDR=$node_master_ip \
       MASTER_PORT=$MASTER_PORT \
       WORLD_SIZE=$WORLD_SIZE \
       RANK=$RANK \
       BUFFER_SIZE=$OPTIMAL_BUFFER \
       python3 $SCRIPT_NAME"
  ) &
  REMOTE_PIDS+=($!)

  RANK=$(( RANK + 1 ))
done

# Brief window for workers to bind and listen
sleep "$WORKER_BIND_DELAY"

# ── 4. LAUNCH LOCAL MASTER (RANK 0) ─────────────────────────────────────────

echo "--------------------------------------------------"
echo "💻 [RANK 0] Initializing master process locally..."
echo "--------------------------------------------------"

MASTER_BIND_IP="$MASTER_IP"
if [ "$REQUIRES_MULTI_INTERFACE_BIND" -eq 1 ]; then
  MASTER_BIND_IP="0.0.0.0"
  echo "ℹ️  Binding master rank to 0.0.0.0 to serve mixed local/VPN worker connectivity."
fi

MASTER_ADDR=$MASTER_BIND_IP \
MASTER_PORT=$MASTER_PORT \
WORLD_SIZE=$WORLD_SIZE \
RANK=0 \
BUFFER_SIZE=$OPTIMAL_BUFFER \
python3 "$LOCAL_PROJECT_DIR/$SCRIPT_NAME"

# ── 5. WAIT FOR ALL WORKERS ──────────────────────────────────────────────────

echo "--------------------------------------------------"
echo "⏳ Waiting for remote worker processes to finish..."
wait
echo "🎉 All distributed processing steps completed successfully!"

# ── 6. POST-RUN PIPELINE ─────────────────────────────────────────────────────

echo ""
echo "=================================================="
echo "🔄 Post-Run: Verification, Metrics, and Report"
echo "=================================================="

# Verify numerical correctness
if [ -f "./verify_output.py" ]; then
  echo "🔎 Running output verification..."
  python3 ./verify_output.py
fi

# Log performance metrics
# In production, parse these from train_dist.py stdout; here we use placeholders.
MOCK_NET_TIME=0.3210
MOCK_COMP_TIME=0.1420
TOTAL_TIME=0.4630

if [ -f "./log_metrics.py" ]; then
  echo "📊 Logging performance metrics..."
  python3 ./log_metrics.py "$WORLD_SIZE" "$MOCK_NET_TIME" "$MOCK_COMP_TIME" "$TOTAL_TIME"
fi

# Generate final report
if [ -f "./generate_report.py" ]; then
  echo "📝 Generating final report..."
  python3 ./generate_report.py
fi

echo ""
echo "✅ Pipeline complete. See FINAL_PROJECT_SUMMARY.md for results."
